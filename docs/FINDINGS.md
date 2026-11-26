# Findings — Epic 1 (mta + imap prototype)

Running results and decisions of the prototype epic. Later tickets (E1-02 … E1-12) add their
sections here.

## Identity plan

- `vmail` user, owning the mail storage in the `imap` container: **uid 5000**.
- Shared group, able to read the config files in both the `mta` and the `imap` containers: **`contingency-config`, gid 5001**.

## Versions

- Debian release used for the images: **Debian 13 "Trixie"** — the current stable release (13.0 released 2025-08-09, latest update 13.8 released 2026-11-21; Debian 12 "Bookworm" is the current oldstable).
- Pinned by tag in the Dockerfiles of the `imap` (ticket E1-03) and `mta` (ticket E1-04), for
  example `debian:trixie-slim`.
- Dovecot version in the `imap` image: **2.4.5** (Debian 13 "Trixie", package `dovecot-core`).
- Postfix version in the `mta` image: the version shipped with Debian 13 "Trixie" (package `postfix`).

## Postfix baseline relay (ticket E1-04)

- H2 (first half): the internal mailbox domain `copies.invalid` is declared as a Postfix virtual mailbox domain (`virtual_mailbox_domains`) and delivered over LMTP to the `imap` container (`virtual_transport = lmtp:inet:imap:24`); internal delivery addresses are listed in `/config/postfix/virtual_mailboxes`.
- H5 (first half): the `texthash:` tables used in the prototype (`relay_domains`, `transport`, `virtual_mailbox_maps`) are readable and set in `postconf` (for example `postmap -q KEY texthash:/config/postfix/relay_domains`).

## Fake `main` sink (ticket E1-02)

- Sink image: **`axllent/mailpit`**, tag **`latest`** (official Docker image).
- SMTP: container port **1025**, published on host **`127.0.0.1:2526`** (host 2526 → container 1025).
- Viewing interface / API: container port **8025**, published on host **`127.0.0.1:8025`** (host 8025 → container 8025).
- Storage: named volume **`mailpit`** mounted at `/data`, database file `/data/mailpit.db` (`MP_DATABASE`).

### How tests inspect received mail (decided in E1-02, reused by later tickets)

- Method: Mailpit REST API served on the web port.
- `sink_count` / `sink_clear` / `sink_raw N` implemented in `prototype/tests/lib/sink.sh` against `GET /api/v1/messages`, `DELETE /api/v1/messages`, and `GET /api/v1/message/{id}/raw`.
- Raw source is returned as plain text; checksums of the sent message and the stored source are compared in later tickets (E1-07).
- The sink stores the raw message source as received and does not rewrite it on SMTP receive; any header added by the sink must be documented here and will be checked during outage testing (E1-07).

## The copy rule (ticket E1-05)

- Implementation: `recipient_bcc_maps = texthash:/config/postfix/recipient_bcc` with one BCC entry per fixture mailbox; the catch-all is deliberately not added yet (ticket E1-06).
- H1 (end to end): pending runtime verification. With `main` down, a message to `alice@client.test` must produce exactly one queued original and exactly one delivered copy; with `main` up, one original in the sink and one copy in the INBOX.
- H2, H3 and H7 (end to end): pending runtime verification of the `.invalid` internal domain, the `^` separator and the two-name-one-mailbox behaviour through BCC + LMTP + IMAP.
- Evidence for each observation is collected in `docs/evidence/E1-05/` (log excerpts, command outputs, raw messages) as required by the ticket.

## Catch-all and recipient policy (ticket E1-06)

- Implementation: catch-all BCC entry added to `recipient_bcc` (`@client.test` → `_catchall^client.test@copies.invalid`); relay recipient map added via `relay_recipient_maps = texthash:/config/postfix/relay_recipients`.
- H4 (first half): exact BCC entries take precedence over the domain catch-all; the catch-all handles addresses without their own mailbox.
- H10 (first half): both the accept-any mode (relay domains only) and the listed-addresses-only mode (via `relay_recipient_maps`) are now wired for testing.

## Outage and recovery scenario (ticket E1-07)

- H8: pending runtime verification. With `main` down, a message to a client address must be queued
  by the `mta` and delivered unmodified when `main` returns; the queue must survive an `mta`
  restart (fallback F8 if it does not). Evidence goes in `docs/evidence/E1-07/`.

## Authenticated submission, sender enforcement, rate limit (ticket E1-08)

- Implementation: new `prototype/config/postfix/master.cf` with the `submission` service on
  port 587 (built by `mta/Dockerfile`): SASL via Dovecot (`smtpd_sasl_type = dovecot`,
  `smtpd_sasl_path = inet:imap:12345`), no TLS (private network); relay restricted to
  authenticated users on submission (`smtpd_relay_restrictions = permit_sasl_authenticated, reject`);
  unauthenticated clients rejected for any recipient (`smtpd_recipient_restrictions =
  permit_sasl_authenticated, reject`); sender login check via `sender_login_maps` +
  `check_sender_login_mismatch`; rate limit `smtpd_client_message_rate_limit = 1` with
  `anvil_rate_time_unit = 1s` (1 message per second, strict window).
- H9 (authentication): pending runtime verification. Login through Dovecot over the private
  network works for the right password and fails for others; the auth listener (TCP 12345 on the
  `imap` service) is not published to the host.
- H9 (enforcement): pending runtime verification. A user may send only as their own address;
  mismatches are rejected at SMTP time on submission; port 25 keeps the E1-04 behaviour (no
  sender check, no auth, no rate limit).
- H9 (rate): pending runtime verification. The combined limit of about 1 message per second is
  demonstrated with the exact parameters and observed SMTP responses recorded; port 25 keeps no
  rate limit.
- Outgoing delivery and loops (ticket steps 11-13): pending runtime verification — send as
  `alice@client.test` to `friend@outside.test` (reaches sink, no copy), to `bob@client.test`
  (relay toward `main` plus BCC copy for bob), to `nobody@client.test` (catch-all, E1-06).
- DKIM: out of scope for this ticket (Epic 2); `master.cf` carries a marked spot for the milter
  (`-o milter_macro_daemon_name=ORIGINATING`) with a comment.
- Evidence for the ticket lives in `docs/evidence/E1-08/`; the H9 result goes in `docs/FINDINGS.md`.

## Configuration reload behavior (ticket E1-09)

- Context: the Rust `admin` service rewrites configuration files and then makes the running services
  notice; it must do the minimum necessary and verify the change took effect. This ticket determines,
  by experiment, what each kind of change requires, and produces a reload table for the admin service
  author to follow literally.
- H5 (reload): pending runtime verification. Every Postfix change (P1–P10) is covered by the reload
  table below; the `texthash:` tables used in this prototype are readable through Postfix lookups
  without a `postmap` step, so the minimal reload for table changes is expected to be
  `postfix reload`.
- H6 (reload): pending runtime verification. The minimal reload for each Dovecot change (D1–D4) is
  recorded in the reload table below; the expectation is that `doveadm reload` is sufficient, with
  `doveadm user` / `doveadm auth test` as the verification commands.

### Reload table

| Change | Service | Reload needed | Verification command | Side effects |
|---|---|---|---|---|
| P1 | Postfix (mta) | `postfix reload` | `postmap -q <new-key> texthash:/config/postfix/relay_domains` (+ transport entry) | none expected |
| P2 | Postfix (mta) | `postfix reload` | `postmap -q <key> texthash:/config/postfix/relay_domains` (+ transport entry) → not found | none expected |
| P3 | Postfix (mta) | `postfix reload` | BCC/virtual/sender-login lookups, e.g. `postmap -q alice@client.test texthash:/config/postfix/recipient_bcc` | none expected |
| P4 | Postfix (mta) | `postfix reload` | mailbox lookups → not found | none expected |
| P5 | Postfix (mta) | `postfix reload` | `@client.test` lookup in `recipient_bcc` → `_catchall^client.test@copies.invalid` | none expected |
| P6 | Postfix (mta) | `postfix reload` | catch-all lookup → not found | none expected |
| P7 | Postfix (mta) | `postfix reload` | `postconf -n` / `relay_recipient_maps` lookup | none expected |
| P8 | Postfix (mta) | `postfix reload` | `postconf maximal_queue_lifetime bounce_queue_lifetime` | queue settings only |
| P9 | Postfix (mta) | `postfix reload` | transport lookup / `postconf` | none expected |
| P10 | Postfix (mta) | `postfix reload` | multiple mailbox lookups | none expected |
| D1 | Dovecot (imap) | `doveadm reload` | `doveadm user <name>` (both login and delivery names) | auth/user cache warm-up possible |
| D2 | Dovecot (imap) | `doveadm reload` | `doveadm auth test <user> <new-pass>` (old pass must fail) | existing sessions keep old credentials until re-auth |
| D3 | Dovecot (imap) | `doveadm reload` | `doveadm user <name>` | — |
| D4 | Dovecot (imap) | `doveadm reload` | `doveadm user <name>` per mailbox | — |

### Atomic replace, failed syntax, rollback, mailbox deletion

- Atomic replace (step 7): the admin service must write new table files to a temporary name and rename over the live file (atomic replace); a plain reload afterwards is sufficient. Evidence: `docs/evidence/E1-09/`.
- Failed syntax (step 8): a broken table line must be observed — Postfix logs the error and refuses to apply the broken map; Dovecot refuses to reload/start on invalid user-file syntax. Exact behaviour pending runtime verification; evidence: `docs/evidence/E1-09/`.
- Rollback (step 9): restore the previous file, reload, verify the old behaviour is back. Procedure documented; runtime demonstration pending (at least one Postfix and one Dovecot change).
- Mailbox directory deletion (step 10): after removing a mailbox from the user file, delete its Maildir from inside the `imap` container while Dovecot is running; observe errors. Pending runtime verification.

## Automated scenario test suite (ticket E1-11)

- Entry point: `prototype/tests/run-all.sh` (options: `--only N` for a single scenario, `--keep` to leave the stack running).
- Shared helpers: `prototype/tests/lib/sink.sh` (Mailpit), `prototype/tests/lib/mail.sh` (reset / send / IMAP / queue), `prototype/tests/lib/smtp_send.py` (SMTP sender via python3 smtplib), `prototype/tests/lib/imap_check.py` (IMAP count / read / wait).
- Scenarios implemented: `prototype/tests/scenarios/01_*` … `20_empty_config_starts_cleanly.sh`, one per behaviour in the ticket table (E1-04 … E1-10 sources).

### Validation performed

- Deliberate break (mandatory): removed the catch-all line (`/^@client\.test/d`) from
  `prototype/config/postfix/recipient_bcc`, reloaded Postfix, ran `run-all.sh --only 08`.
  Result: scenario 08 **FAILED** with a readable message ("known address -> own mailbox"),
  suite exit code **non-zero**. Restored the golden file and re-ran: **PASS**.
- Scenarios run green during implementation: `01` (relay + main up), `04` (copy + main up),
  `19` (reload lookups), `20` (empty config).

### Notes

- The suite expects the stack up (`docker compose up -d --build` first); it resets state
  (empty sink, queue, mailboxes) before each scenario.
- Total run time for the full 20-scenario suite is recorded here after the final full run
  (ticket target: a few minutes).

## Master reload segfault (investigation note, ticket E1-11 follow-up)

- Symptom: `postfix reload` inside the `mta` container deterministically causes the Postfix
  master process to exit with **SIGSEGV** (~exit 139); the container then goes down and
  crash-loops on compose restart.
- Minimal reproduction:
  ```
  docker compose restart mta
  sleep 45            # until Status = Up (healthy)
  docker compose exec -T mta postfix reload
  # -> container exits within ~10-30 seconds
  ```
- Isolation performed:
  - Reload after plain restart crashes; restart without reload stays healthy (control).
  - Crash persists with a **minimal** `master.cf` (smtp/pickup/cleanup/qmgr/postlog only) and
    a **minimal** `main.cf` — so it is not caused by table content, service list, or the
    `postlog` unix-dgram → unix change.
  - Crash persists with both `maillog_file = /var/log/postfix.log` and `= /dev/stdout`.
  - Conclusion: the segfault is in the Postfix **master reload handler / re-init path**
    itself in this environment (Postfix 3.10.13, Debian 13 "Trixie"), independent of the
    loaded configuration content.
- Workaround in use: use `docker compose restart mta` (or stop/start) instead of
  `postfix reload` when bringing the mta back up; re-investigate once a Postfix patch or
  master re-exec behaviour is available.

## Outputs

Reload table and verification commands in `docs/FINDINGS.md`, evidence in `docs/evidence/E1-09/`, results for H5 and H6.

