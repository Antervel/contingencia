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
