# EPIC 1: Mail-flow prototype (`mta` + `imap`)

**Project:** Contingency Mail Appliance
**Epic ID:** E1
**Status:** Ready to start
**Source documents:** `contingency-appliance-PRD.md`, `technical.md` (section 9, step 1)

---

## 1. Why this epic exists

The whole appliance rests on a trick: mail for `a@client.test` is **relayed** to `main` (the original), while a **copy** is delivered into a local mailbox that the user later opens with webmail. The copy is made by a Postfix recipient BCC rule, sent to an internal address (`a^client.test@copies.invalid`), delivered by Dovecot over LMTP, and stored in the same mailbox the user logs into as `a@client.test`.

We have reasoned about this from documentation and experience, but **we have not run it**. Several steps are marked **(verify)** in `technical.md`. If any of them is wrong, the design changes. Every later piece of work (`dkim`, `webmail`, and above all the Rust `admin` service that generates configuration) builds on the answers.

This epic therefore builds the **smallest possible working system** with hand-written configuration files, proves or disproves each assumption, and leaves behind:

1. a working `mta` + `imap` pair in Docker Compose;
2. **reference configuration files** ("golden files") that the Rust admin service must later reproduce exactly;
3. an automated test script that re-runs every scenario;
4. a written findings report with a go/no-go decision and any design changes.

Nothing in this epic is throwaway except the hand-written *process* of creating the files. The files, the test script and the findings are all inputs to later epics.

## 2. Scope

### In scope

- The `mta` container (Postfix) and the `imap` container (Dovecot), each a Debian-based image that we build.
- A fake `main` server (an SMTP sink we can start and stop) and a fake "outside world" recipient, to simulate outages and external delivery.
- Plain-text, hand-written configuration for both containers, kept in a shared config volume the way the final system will.
- Delivery of the original (to `main`) and the copy (to the local mailbox).
- Catch-all behavior and the "accept any address" vs "listed addresses only" policy.
- Authenticated submission on port 587 with sender-address enforcement and a rate limit, **without** DKIM signing.
- How each kind of configuration change is picked up by the running services (which reload command, if any).
- Persistence of the queue and the mail store across container restarts.

### Out of scope (later epics)

- DKIM signing and the `dkim` container (Epic 2).
- Roundcube and the `webmail` container (Epic 3).
- The Rust `admin` service, its web interface, and anything that generates files automatically (Epic 4).
- TLS on port 25, health checks, install documentation, and production hardening (Epic 5).
- Full integration tests of the whole appliance and the staging trial with a real `main` (Epic 6).
- Spam and virus filtering (excluded from the product).

## 3. Test fixtures used throughout

All tickets use the same names so results are comparable. These are invented names under the reserved `.test` and `.invalid` top-level domains, so nothing can leak onto the real internet.

| Item | Value |
|---|---|
| Client domain A | `client.test`, with a catch-all |
| Client domain B | `other.test`, no catch-all |
| Internal mailbox domain `L` | `copies.invalid` |
| Separator | `^` |
| Mailboxes in `client.test` | `alice@client.test` (password `alice-pass`), `bob@client.test` (password `bob-pass`), and the catch-all mailbox `_catchall@client.test` (password `catchall-pass`) |
| Mailbox in `other.test` | `carol@other.test` (password `carol-pass`) |
| Internal (delivery) names | `alice^client.test@copies.invalid`, `bob^client.test@copies.invalid`, `_catchall^client.test@copies.invalid`, `carol^other.test@copies.invalid` |
| Unknown address for catch-all tests | `nobody@client.test` |
| Unknown address, no catch-all | `nobody@other.test` |
| Fake `main` | container `main`, host name `main`, port 25 |
| Fake outside world | recipient domain `outside.test`, routed to the same sink in the prototype only |

The passwords are for the prototype only.

## 4. Target layout of the prototype

```
/
├── compose.yaml                 prototype stack: mta, imap, main (sink)
├── mta/                         Dockerfile and entrypoint for Postfix
├── imap/                        Dockerfile and entrypoint for Dovecot
├── prototype/
│   ├── config/                  hand-written files, mounted as the shared config volume
│   │   ├── postfix/
│   │   └── dovecot/
│   └── tests/                   scenario scripts (ticket E1-11)
├── reference/                   cleaned, commented golden files (ticket E1-10)
└── sdlc/
    └── FINDINGS.md              results and decisions (ticket E1-12)
```

In the prototype the shared config volume is a plain folder on the host, mounted read-only into `mta` and `imap`. In the finished system the admin service will write it. For now, a human edits the files.

## 5. Hypotheses to confirm or refute

Each hypothesis is covered by one or more tickets, and each gets a **PASS / FAIL / CHANGED** result in `FINDINGS.md`.

| ID | Hypothesis | Tickets |
|---|---|---|
| H1 | Postfix's recipient BCC rule makes a copy of mail that is only being **relayed** (not delivered locally). | E1-05 |
| H2 | A never-routed name ending in `.invalid` is accepted by Postfix as a `virtual_mailbox_domains` entry and as a BCC destination. | E1-04, E1-05 |
| H3 | The `^` character is accepted everywhere it appears: BCC target, virtual mailbox map, LMTP recipient, Dovecot user name. | E1-05 |
| H4 | An exact-address BCC entry takes precedence over an `@domain` catch-all entry, so a known address is **not also** copied to the catch-all. | E1-06 |
| H5 | The `texthash:` table type works for every Postfix table we need, and changes are picked up with a known, minimal command. | E1-04, E1-09 |
| H6 | Dovecot picks up changes to the passwd-file with a known, minimal command (ideally `doveadm reload` or nothing at all). | E1-03, E1-09 |
| H7 | A passwd-file with two lines per mailbox gives one Maildir that answers to both `a@client.test` (login) and `a^client.test@copies.invalid` (delivery), and the second name cannot be used to log in. | E1-03, E1-05 |
| H8 | The original message stays queued while `main` is down, arrives **unmodified** when `main` returns, and the queue survives a restart of `mta`. | E1-07 |
| H9 | Submission on 587 authenticates through Dovecot over the network, the sender-login map stops one user from sending as another, and the rate limit behaves as we expect (1 message per second). | E1-08 |
| H10 | "Accept any address" and "listed addresses only" can both be configured and behave as described in the PRD. | E1-06 |

## 6. Fallbacks if a hypothesis fails

These are decided *in advance* so a failure leads to a quick change rather than a debate.

| Fallback ID and failure | Fallback |
|---|---|
| F1: H1 fails (no copy for relayed mail) | Make each client domain a **local** domain on the backup, with its mailboxes at `a@client.test` directly, and BCC every recipient to `a@relay.client.test`, which a transport map routes to `main`. Same admin experience, different plumbing. |
| F2: H2 fails (`.invalid` rejected) | Use another never-routed name, such as one under `.test` or `.localdomain`, chosen at install time as already planned. |
| F3: H3 fails (`^` rejected somewhere) | Replace the separator with `=`. Avoid `+`, which Postfix treats as an address extension delimiter. |
| F4: H4 fails (catch-all also copies known addresses) | Generate catch-all entries only for domains' unlisted addresses by using a regexp or pcre map that excludes known local parts, or drop the catch-all from v1. |
| F5: H5 fails (`texthash` unsuitable somewhere) | Use `hash:` tables for that table, with a `postmap` step run inside `mta` by the admin service. |
| F6: H6 fails (Dovecot needs a restart) | Restart `imap` after every user change. Acceptable, because the admin service can do it. |
| F8: H8 fails (queue not persistent) | Fix the volume mapping. This is a plumbing error, not a design problem. |
| F9: H9 fails (SASL over TCP unreliable) | Fall back to a Unix socket shared by a volume between the two containers. |

## 7. Tickets

| ID | Title | Size | Depends on |
|---|---|---|---|
| E1-01 | Repository skeleton and prototype Compose stack | S | none |
| E1-02 | Fake `main` and fake outside world (SMTP sink) | S | E1-01 |
| E1-03 | `imap` container: Dovecot with two-name mailboxes | M | E1-01 |
| E1-04 | `mta` container: baseline Postfix relay to `main` | M | E1-01, E1-02, E1-03 |
| E1-05 | The copy rule: relay the original, deliver the copy | L | E1-03, E1-04 |
| E1-06 | Catch-all and recipient policy | M | E1-05 |
| E1-07 | Outage and recovery scenario | M | E1-05 |
| E1-08 | Authenticated submission, sender enforcement, rate limit | L | E1-03, E1-05 |
| E1-09 | Configuration reload behavior | M | E1-06, E1-08 |
| E1-10 | Reference ("golden") configuration files and format spec | M | E1-06, E1-08, E1-09 |
| E1-11 | Automated scenario test script | M | E1-05 (grows with each ticket) |
| E1-12 | Findings report and go/no-go | S | all above |

Suggested order of work: 01, 02, 03, 04, 05, then 06, 07 and 08 in any order, then 09, 10, 11 (started early, finished last), and 12.

Sizes: S = about half a day, M = about one day, L = one to two days. These are rough, for planning only.

## 8. Definition of done for the epic

The epic is complete when **all** of these are true:

1. `docker compose up` brings up `mta`, `imap` and the fake `main` from a clean checkout, with no manual steps beyond creating the config files that are already in the repository.
2. Every hypothesis H1 to H10 has a result recorded in `sdlc/FINDINGS.md`, with evidence (command output or log lines).
3. The automated test script runs every scenario from tickets E1-05 to E1-09 and passes.
4. The `reference/` folder contains commented example files for every generated file type, plus the format specification that tells the Rust admin service author exactly how to produce them from state.
5. Every fallback that was triggered has been applied, and `technical.md` has been updated so it matches what actually works (every **(verify)** marker either resolved or turned into a documented fact).
6. A go/no-go decision for starting Epic 2 is recorded.

## 9. Risks specific to this epic

- **Trusting a pass without looking at the evidence.** A test that "passes" because the mail arrived somewhere unexpected is worse than a failure. Every ticket requires reading the actual queue, logs and mailbox contents, not just checking a result line.
- **Prototype drift.** If someone fixes a problem by editing a file inside a running container, the fix is lost. All changes must be made in the repository files.
- **Version differences.** The behavior of Postfix and Dovecot differs between versions. The Debian release used in the Dockerfiles must be recorded in `FINDINGS.md`, because the final system will use the same one.
- **Scope creep into later epics.** DKIM, webmail, and the admin service must not be started here, however tempting.

## 10. Conventions for all tickets

- Work on a branch per ticket. Commit configuration files with explanatory comments inside them.
- Every ticket ends by updating `sdlc/FINDINGS.md` with its results, even when it passes.
- Record every command used to test, in the ticket's "How to test" section, so someone else can repeat it.
- When something fails, save the log lines that show why before changing anything.
