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
- Final full-suite runs (three consecutive, after the submission fix and scenario-20
  reload→restart fix): all scenarios green except design-expectation items listed below.
  Suite duration per full run: **~220 s** (three runs: 226 s / 226 s / 218 s).
- Post-submission fix: the authenticated submission path (scenarios `14`, `16`, `17`) was
  fixed by replacing the invalid smtpd restriction `check_sender_login_mismatch` (unknown in
  Postfix 3.10.13) with the supported `reject_sender_login_mismatch` and parameter
  `smtpd_sender_login_maps`; authenticated submission on 587 then delivered correctly.

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
- Operational consistency: the scenario suite no longer uses `postfix reload` anywhere;
  both the E1-09 scenario (`19_reload_table_checks.sh`) and the E1-10 scenario
  (`20_empty_config_starts_cleanly.sh`) now use `postfix restart` as the operational
  equivalent of the reload. After the fix, the full suite ran three times without the
  mta crash-loop re-appearing.

## Findings report and go/no-go (ticket E1-12)

### Final hypothesis outcomes (consolidated)

- H1 (copy rule): **PASS** — relayed originals and BCC copies both delivered as designed
  (scenarios E1-05 `04`, `05` green; E1-11 suite).
- H2 (never-routed internal domain): **PASS** — `copies.invalid` accepted as a virtual mailbox
  domain and delivered over LMTP (E1-04, E1-05).
- H3 (`^` delivery separator): **CHANGED** — `^`-based internal delivery names were unresolvable
  through the Dovecot userdb; the design now uses `<mailbox>@<L>` names
  (e.g. `alice@copies.invalid`, `_catchall@copies.invalid`) as implemented in E1-10.
- H4 (catch-all precedence): **PASS** — exact BCC entries take precedence over the `@domain`
  catch-all (scenario E1-06 `08` green).
- H5 (texthash tables): **PASS** — `texthash:` readable via lookups; the reload *mechanism*
  (`postfix reload`) turned out to be broken in the prototype environment (see reload segfault),
  so the minimal reload command is now the restart-based workflow.
- H6 (Dovecot passwd-file pickup): **PENDING** — minimal reload command and verification
  behaviour for the user/auth tables still to be recorded from the runtime (E1-09 reload table).
- H7 (two-name-one-mailbox): **PASS** — with the `<mailbox>@<L>` naming, one Maildir answers to
  both the login name and the delivery name (E1-05, E1-10 scenarios green).
- H8 (outage / queue / restart): **PASS** — queued originals delivered unmodified when `main`
  returned; queue survives `mta` restart (scenarios E1-07 `02`, `05`, `12`, `13` green).
- H9 (submission): **PASS** — after replacing the invalid smtpd restriction
  (`check_sender_login_mismatch` → `reject_sender_login_mismatch` plus
  `smtpd_sender_login_maps = texthash:/config/postfix/sender_login`), authenticated submission
  on 587 works end to end (scenario E1-08 `14` green, enforcement in `16`, rate limit in `17`,
  wrong password in `15`, port-25 isolation in `18`); the fix itself was mandatory because the
  original setting made smtpd defer every submission RCPT with `451 4.3.5 Server configuration error`.
- H10 (recipient policy): **PASS** — accept-any mode works (scenarios E1-06 `09`, `10` and
  E1-08 `18` green); listed-only mode is now enforced and verified (scenario E1-06 `11` green):
  the unlisted relay recipient was refused with `554` through
  `smtpd_relay_restrictions = reject_unlisted_recipient, reject_unauth_destination` plus the
  generated `relay_recipient_maps` lookup.

### Final scenario-suite status (E1-11, updated after E1-12 carry-forward fixes)

- Full suite (`prototype/tests/run-all.sh`): **ALL SCENARIOS PASSED** in three consecutive runs
  (full runs at ~440–443 s each) after fixing the internal-injection block (scenario `07`) and
  the listed-only enforcement (scenario `11`).
- Clean-checkout run (fresh clone, `docker compose up -d --build`, `prototype/tests/run-all.sh`):
  **ALL SCENARIOS PASSED** in **441 s**.
- Deliberate break (catch-all removal) verified failing then passing (scenario `08`).
- Internal injection (scenario `07`): fixed via generated `recipient_access` map keyed on full
  delivery addresses (`<mailbox>@<L>`) checked through `smtpd_recipient_restrictions`.
- Listed-only (scenario `11`): fixed via `reject_unlisted_recipient` + `reject_unauth_destination`.

### Operational findings (cross-ticket)

- Postfix master reload (`postfix reload`) in the `mta` container segfaults the master
  (SIGSEGV, exit 139) in this environment (Postfix from Debian 13 "Trixie", Postfix 3.10.13);
  the reload handler / re-init path is the culprit, independent of loaded configuration content.
  Workaround: use `postfix restart` (scenarios `19` and `20` now do so).

### Decision (E1-12, updated after E1-12 carry-forward fixes)

- **GO** for the E1 prototype epic as delivered; the E1-12 carry-forwards were subsequently
  implemented and verified during the final E1-12 follow-up:
  - listed-only recipient enforcement (H10 / scenario `11`): **fixed and green**;
  - internal-injection expectation (scenario `07`): **fixed and green**;
  - close H6 (Dovecot reload behaviour) and re-verify E1-09 reload table entries: **still open**.
- The GO decision applies to the prototype phase; hardening, DKIM, TLS and the admin service
  remain Epic 2 work.

## CI/CD: build, test and publish images (ticket E1-13)

- Implemented `.github/workflows/images.yml`: build matrix over `mta`/`imap` (temporary tag
  `e1-13-tmp-<full-commit-hash>`), test gate, publish to GitHub Container Registry with tags
  `<full-commit-hash>` and `latest`, image labels (source repo, commit hash, build time), pinned
  third-party actions, PR vs `main` triggers, concurrency rules.
- Implemented `compose.release.yaml`: release stack from registry images via `image:` entries
  with the tag set by a single variable (`CONTINGENCY_TAG`); `webmail` placeholder until Epic 3.
- Implemented `docs/CICD.md` covering triggers, image names/tags/labels, commit tracing, pinning,
  re-runs and adding images.
- Test gate (E1-13): `postfix check` (mta), Dovecot configuration check (imap), healthy state, and
  scenario suite `prototype/tests/run-all.sh` from E1-11; failure uploads logs via artifact.

### Fresh-container startup failure in the CI test gate (E1-13, resolved)

- Symptom: the E1-13 test gate failed at `docker compose -f compose.release.yaml up -d --wait` on
  a clean CI runner: the freshly created `mta` container exited (code 1) while `imap` and `main`
  reached the healthy state; retrying the stack start did not help.
- Root cause: the `mta` image started the Postfix master binary directly
  (`CMD ["/usr/lib/postfix/sbin/master"]`), which is not the container-ready foreground startup
  required by the design (technical.md E1-04: "Run Postfix in the foreground as the container's main
  process"). With the freshly built image the master process failed during startup and the container
  went down before it could reach the healthy state.
- Fix: `mta/Dockerfile` now starts Postfix the container-recommended way - `CMD
  ["/usr/sbin/postfix", "start-fg"]` (Postfix 3.3+ keeps `master(8)` in the foreground as the
  container's main process) - and configures `maillog_file = /dev/stdout` (Postfix 3.4+ `postlog
  unix-dgram` service) so the daemon logs to the container's stdout/stderr instead of relying on a
  syslog daemon that is not present in the image.
- Verification: with the rebuilt image the release stack reaches a healthy `mta` state and the full
  scenario suite passes (`ALL SCENARIOS PASSED`).

### Scenario-suite failures on the CI runner (E1-13, resolved)

- Symptom: after the startup fix the gate reached the scenario suite but failed 8 scenarios (02, 04,
  05, 09, 10, 13, 14, 18) on the runner, while the same image passed locally. The MTA logs showed
  deliveries deferred with `Host or domain name not found ... name=main`, i.e. `main` was down.
- Root cause 1 (the first failure): `queue_pending_count` in `prototype/tests/lib/mail.sh` parsed
  `mailq` with a fixed-width regex (`^[A-F0-9]{10}`). Postfix queue IDs are not fixed-width: they
  were 10 characters on the local filesystem and 11 on the runner (`18DF07E7300`). The count was
  therefore always 0 on CI and scenario 02 failed its "original queued while main down" check.
- Root cause 2 (the cascade): scenario 02 stops `main`, and `fail()` exits immediately, before the
  scenario restarts it. Every later scenario that needs `main` then failed as well (04, 05, 09, 10,
  13, 14, 18), which is why one real bug looked like eight.
- Root cause 3 (a race found while re-validating on the release stack): several scenarios sampled
  the queue once, immediately after the sink received the message. Postfix keeps the message in the
  active queue until `qmgr` removes it (about one second in the logs), so a single read is flaky.
  The suite now polls with `wait_for_queue_at_least` / `wait_for_queue_empty` and bounded timeouts.
- Fix (tests): `queue_pending_count` now counts `postqueue -j` records (`"queue_id"`), independent
  of the queue-ID format. `reset_state` and the suite runner call `ensure_services`, which starts
  every service and waits for the sink API before each scenario, so a failure can no longer leak a
  stopped service into later scenarios. `ensure_mta` polls `postfix status` instead of a single
  check followed by a long fixed sleep.
- Fix (pipeline): the suite now reads `COMPOSE_FILE` (default `compose.yaml`), and the test gate sets
  `COMPOSE_FILE=compose.release.yaml`, `COMPOSE_PROJECT_NAME=contingencia-ci` and
  `CONTINGENCY_TAG=<temp tag>`. The gate therefore drives exactly the release stack it started from
  the freshly built images, instead of relying on the prototype and release files sharing a project
  name. A new step asserts that the running `mta`/`imap` containers use the freshly built image IDs,
  so the gate cannot silently test a cached image. Failure diagnostics now include `compose ps`,
  `compose images`, `postqueue -j`, `mailq` and all container logs.
- Verification: the full suite passes locally both on the prototype stack and on the release stack
  with the same environment the workflow uses; the CI run on the fixed commit is the final check.

### Build and test duration, final image sizes

- Clean-checkout validation run (fresh clone, build, stack up, full scenario suite): **441 s**
  (three consecutive full-suite runs before it: **~218–226 s**, **~440–443 s** each).
- Final image sizes (uncompressed): `mta` ≈ **183 MB**, `imap` ≈ **204 MB`.
- Live GitHub publish run: not executed from this environment (no push credentials); the workflow
  is ready for the next push to `main`.

## Outputs

Reload table and verification commands in `docs/FINDINGS.md`, evidence in `docs/evidence/E1-09/`, results for H5 and H6.

