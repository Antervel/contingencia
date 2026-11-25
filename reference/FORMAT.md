# Format specification for the generated configuration files — Epic 1, ticket E1-10

This document specifies, precisely, the format of every file under
`reference/generated/`, so that the Rust admin service can render the same bytes
from `reference/state/` and the snapshot tests in Epic 4 have a byte-exact
contract.

## Conventions

- Line endings: LF (Unix), with a final newline at the end of each file.
- Header comments: no timestamps (ticket requirement — deterministic output).
- Generated file names and locations are listed in `reference/README.md`.

## Postfix generated files

### `generated/postfix/relay_domains`

- Header comment (exact wording): `# Relay domains for the prototype (ticket E1-10).`
  followed by the continuation comment lines from the golden file.
- Line format: one relay domain per line, bare key, no value.
- Ordering: relay domains sorted by domain, byte-wise ascending.

### `generated/postfix/transport`

- Header comment (exact wording): `# Transport map for the prototype (ticket E1-10).`
  followed by the continuation comment lines from the golden file.
- Line format: `<domain> <transport>`, single space separator; transport value
  is `relay:[main]:25`.
- Ordering: by domain, byte-wise ascending.

### `generated/postfix/virtual_mailboxes`

- Header comment (exact wording): `# Internal mailbox domain L (copies.invalid) delivery addresses (ticket E1-10).`
- Line format: `<internal> <original>`.
- Internal name: from mailbox `<mailbox>@<domain>` → `<mailbox>^<domain>@<L>`;
  catch-all `_catchall@<domain>` → `_catchall^<domain>@<L>`.
- Ordering: by internal address, byte-wise ascending.

### `generated/postfix/recipient_bcc`

- Header comment (exact wording): `# BCC map for the prototype (ticket E1-10).`
- Line format: `<original> <internal>`.
- Exact-address entries: `<mailbox>@<domain> <mailbox>^<domain>@<L>`.
- Catch-all entries: `@<domain> _catchall^<domain>@<L>`.
- Ordering: exact-address entries first (sorted by domain, then local part),
  then catch-all entries (sorted by domain).

### `generated/postfix/relay_recipients`

- Header comment (exact wording): `# Relay recipient policy for the prototype (ticket E1-10).`
- Line format: bare address per line (listed-recipient policy entries).
- Ordering: sorted by address, byte-wise ascending.

### `generated/postfix/sender_login`

- Header comment (exact wording): `# Sender login policy (ticket E1-10).`
- Line format: `<sender> <login>`.
- Ordering: sorted by sender, byte-wise ascending.

### `generated/dovecot/users`

- Header comment (exact wording): `# Dovecot passwd-file for the prototype (mounted read-only at /config, ticket E1-10).`
- Line format: passwd-file fields `user:password:uid:gid:(gecos):home:(shell):extra`.
- One line per name: login `<mailbox>@<domain>` with SHA-512 crypt password;
  delivery `<mailbox>^<domain>@<L>` with empty password.
- Ordering: per mailbox, grouped by mailbox domain then local part (byte-wise);
  within a mailbox, login line precedes delivery line.

## Empty-file case

- All generated tables may be empty (first start of the finished system; the
  admin renders the initial empty config on first run). Empty files are valid for
  Postfix and Dovecot (see ticket E1-10 "How to test").

## File permissions and ownership

- Prototype: files under `prototype/config/` are mounted read-only into `mta`
  and `imap`.
- Finished system: files under `/data/config/generated/`, owned by the admin
  service user, mode 600 for secrets (password hashes), group-readable otherwise.

## Validation rules for user-supplied values

- Reject: whitespace/space in local part or domain, `^` in local part or domain
  (reserved separator), control characters, uppercase (must be lowercased) — with
  reasoning per case.

## Apply sequence (distilled from ticket E1-09)

Distilled from the E1-09 reload behavior and technical.md section 4.4:

| Kind of change | Files changed | Reload (container) | Verification |
|---|---|---|---|
| Mailbox added / changed / removed | `generated/postfix/{recipient_bcc,virtual_mailboxes,sender_login}`, `generated/dovecot/users` | `postfix reload` (mta); `doveadm reload` (imap) | Postfix lookups for changed addresses; `doveadm user` for both names; `doveadm auth test` for changed passwords |
| Domain added / removed | `generated/postfix/{relay_domains,transport}`, ... | `postfix reload` (mta) | Postfix lookups (`postmap -q`) |
| Recipient policy switched | `generated/postfix/{relay_recipients,relay_domains}` | `postfix reload` (mta) | Postfix lookups / `postconf -n` |
| Queue lifetime changed | Postfix main settings | `postfix reload` (mta) | `postconf` |
| Submission / auth / rate-limit changes | `master.cf`, Postfix main settings | restart of `mta` for `master.cf`; `postfix reload` for main settings | `postfix check`, lookups, auth tests |
| Dovecot mailbox added / password changed / removed | `generated/dovecot/users` | `doveadm reload` (imap) | `doveadm user`; `doveadm auth test` |
| Bulk edit | all affected generated files above | per-kind reloads | per-kind verifications, once for the whole set |

## Outputs

The `reference/` folder, `FORMAT.md`, and the apply sequence table (ticket E1-10 outputs).
