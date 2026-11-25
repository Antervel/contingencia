# Contingency Mail Appliance — prototype (Epic 1)

This repository contains the **prototype** of the Contingency Mail Appliance: a small set of Docker containers that act as a backup mail server while the client's real mail server (`main`) is down.

This folder is the starting point of **Epic 1** (`sdlc/components/mta_imapd/`): it proves the core mail flow with hand-written configuration files before anything is generated automatically.

## What this prototype is

A Docker Compose stack with three services on one private network:

| Service | Purpose | State |
|---|---|---|
| `mta` | Mail transfer agent (Postfix). Accepts mail, relays the original to `main`, delivers copies. | Placeholder (sleeping) — real image in ticket E1-04 |
| `imap` | Mail delivery and mailbox server (Dovecot). Stores copies, serves IMAP/LMTP/SASL. | Dovecot (from `imap/Dockerfile`), config in `prototype/config/dovecot/` (ticket E1-03) |
| `main` | Fake `main` SMTP sink (the real appliance) — Mailpit: accepts any recipient/sender, stores every message raw, web UI + REST API. | `axllent/mailpit` (E1-02) |

The hand-written configuration lives in `prototype/config/` (mounted read-only at `/config` in both `mta` and `imap`). The mail store and the delivery queue are persistent named volumes.

## Start / stop

```bash
docker compose up --build
docker compose down
```

## Ports (testing only)

All published ports are bound to `127.0.0.1` on the host and exist only for the prototype:

| Service | Container port | Host port |
|---|---|---|
| `mta` | 25 (SMTP) | 2525 |
| `mta` | 587 (submission) | 5587 |
| `imap` | 143 (IMAP) | 1143 |
| `main` | 25 (SMTP sink) | 2526 |
| `main` | 8025 (web/API) | 8025 |

The final system will not publish IMAP or submission.

## Layout

```
compose.yaml              prototype stack
mta/                      Dockerfile and entrypoint for Postfix (E1-04)
imap/                     Dockerfile and entrypoint for Dovecot (E1-03)
prototype/
  config/                 hand-written config files, mounted read-only at /config
  tests/                  scenario scripts (E1-11)
reference/                cleaned, commented golden files (E1-10)
docs/                     findings and decisions (E1-12)
```

## Test fixtures

All tickets use the same invented addresses under the reserved `.test` and `.invalid` domains: see **section 3 – Test fixtures used throughout** of [`sdlc/components/mta_imapd/EPIC.md`](sdlc/components/mta_imapd/EPIC.md#3-test-fixtures-used-throughout).
