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

