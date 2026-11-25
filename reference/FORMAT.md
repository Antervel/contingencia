# Format specification for the generated configuration files — Epic 1, ticket E1-10

This document specifies, precisely, the format of every file under
`reference/generated/`, so that the Rust admin service can render the same bytes
from `reference/state/` and the snapshot tests in Epic 4 have a byte-exact
contract.

## Conventions

- Line endings: LF (Unix), with a final newline at the end of each file.
- Header comments: no timestamps (ticket requirement — deterministic output).
- Generated file names and locations are listed in `reference/README.md`.
- Table files with two fields (transport, virtual_mailboxes, recipient_bcc,
  sender_login) use a **single ASCII space** as field separator; no quoting is
  used, values are plain ASCII.

## Header comments (exact text)

Every generated file starts with a header comment block, followed by a blank
line, then its data lines (if any). The header comment blocks are exactly:

### `generated/postfix/relay_domains`

```
# Relay domains for the prototype (ticket E1-10).
#
# Client domains accepted from any client and relayed to the fake main sink
# ([main]:25). In the final system these are generated from the admin state; in
# the prototype they are hand-written from the fixtures of EPIC.md section 3.
```

### `generated/postfix/transport`

```
# Transport map for the prototype (ticket E1-10).
#
# Relay every relay domain to the fake main sink at [main]:25 (square brackets:
# no MX lookup, so mail cannot loop back to the appliance).
```

### `generated/postfix/virtual_mailboxes`

```
# Internal mailbox domain L (copies.invalid) delivery addresses (ticket E1-10).
#
# One internal delivery address per fixture mailbox, delivered over LMTP to
# the imap container (virtual_transport = lmtp:inet:imap:24).
```

### `generated/postfix/recipient_bcc`

```
# BCC map for the prototype (ticket E1-10).
#
# One BCC copy per fixture mailbox, plus the catch-all for the client domain that
# has one. The catch-all is the domain-wide BCC entry; exact-address entries take
# precedence over it (hypothesis H4). The catch-all for `other.test` does not exist
# in the fixtures and is deliberately absent here.
```

### `generated/postfix/relay_recipients`

```
# Relay recipient policy for the prototype (ticket E1-10).
#
# Addresses allowed to relay mail while the "listed addresses only" policy is
# active (EPIC FR-3). In accept-any mode this table is not used and the relay
# domains are sufficient.
```

### `generated/postfix/sender_login`

```
# Sender login policy (ticket E1-10).
#
# Maps an envelope sender address to the SMTP AUTH login name that is allowed
# to use it. Postfix enforces this on the submission service via
# check_sender_login_mismatch (master.cf). Port 25 does not apply this check.
```

### `generated/dovecot/users`

```
# Dovecot passwd-file for the prototype (mounted read-only at /config, ticket E1-10).
#
# Format: user:password:uid:gid:(gecos):home:(shell):extra_fields
#   - login name:       alice@client.test        -> password set, this is the mailbox user
#   - delivery name:    alice^client.test@copies.invalid -> no password, login disabled, same home
#
# Internal mailbox domain "L" is copies.invalid; the separator is "^" (EPIC section 3.2/H3).
```

## Postfix generated files

### `generated/postfix/relay_domains`

- Header comment: as specified in the "Header comments (exact text)" section.
- Line format: one relay domain per line, bare key, no value, single entry per
  line, no quoting.
- Ordering: relay domains sorted by domain, byte-wise ascending.

### `generated/postfix/transport`

- Header comment: as specified in the "Header comments (exact text)" section.
- Line format: `<domain> <transport>`, single space separator; transport value
  is `relay:[main]:25`.
- Ordering: by domain, byte-wise ascending.

### `generated/postfix/virtual_mailboxes`

- Header comment: as specified in the "Header comments (exact text)" section.
- Line format: `<internal> <original>`, single space separator.
- Internal name: from mailbox `<mailbox>@<domain>` → `<mailbox>^<domain>@<L>`;
  catch-all `_catchall@<domain>` → `_catchall^<domain>@<L>`. Both the local part
  and the domain are lowercased (uppercase is rejected at validation and
  lowercased at render time).
- Ordering: by internal address, byte-wise ascending.

### `generated/postfix/recipient_bcc`

- Header comment: as specified in the "Header comments (exact text)" section.
- Line format: `<original> <internal>`, single space separator.
- Exact-address entries: `<mailbox>@<domain> <mailbox>^<domain>@<L>`.
- Catch-all entries: `@<domain> _catchall^<domain>@<L>`.
- Ordering: exact-address entries first (sorted by domain, then local part),
  then catch-all entries (sorted by domain).

### `generated/postfix/relay_recipients`

- Header comment: as specified in the "Header comments (exact text)" section.
- Line format: bare address per line (listed-recipient policy entries).
- Ordering: sorted by address, byte-wise ascending.

### `generated/postfix/sender_login`

- Header comment: as specified in the "Header comments (exact text)" section.
- Line format: `<sender> <login>`, single space separator.
- Ordering: sorted by sender, byte-wise ascending.

### `generated/dovecot/users`

- Header comment: as specified in the "Header comments (exact text)" section.
- Line format: passwd-file fields `user:password:uid:gid:(gecos):home:(shell):extra_fields`.
- One line per name: login `<mailbox>@<domain>` with SHA-512 crypt password;
  delivery `<mailbox>^<domain>@<L>` with empty password.
- Ordering: per mailbox, grouped by mailbox domain then local part (byte-wise);
  within a mailbox, login line precedes delivery line.

## Empty-file case

- All generated tables may be empty (first start of the finished system; the
  admin renders the initial empty config on first run). An empty generated file
  contains no header comment and no data lines: it is a zero-byte file. Postfix
  accepts empty tables and Dovecot accepts an empty passwd-file (see ticket
  E1-10 "How to test").

## File permissions and ownership

- Prototype: files under `prototype/config/` are mounted read-only into `mta`
  and `imap`.
- Finished system: files under `/data/config/generated/`, owned by the admin
  service user, mode 600 for secrets (password hashes), group-readable otherwise.

## Disabled domains

- Decision: a disabled domain is **omitted** from the generated maps (no relay,
  transport, virtual-mailbox, BCC or sender-login entries are rendered for it).
  Deactivating a domain therefore removes the corresponding generated entries on
  the next apply; re-enabling adds them again. The prototype fixtures contain no
  disabled domain, so this decision is design-time only and was validated through
  the empty-file case rather than through a live disabled-domain test.

## Validation rules for user-supplied values

- Reject: whitespace/space in local part or domain, `^` in local part or domain
  (reserved separator), control characters, uppercase (must be lowercased).
- Reasoning: spaces would break the single-space field separation of the
  two-field tables (or inject extra fields); `^` is the reserved internal-name
  separator and would make encoded names ambiguous; control characters would
  corrupt the plain-text files and log output; uppercase would break the
  byte-wise deterministic ordering and the case handling of the mail systems.

## Apply sequence (distilled from ticket E1-09)

Distilled from the E1-09 reload behavior and technical.md section 4.4:

| Kind of change | Files changed | Reload (container) | Verification |
|---|---|---|---|
| Mailbox added / changed / removed | `generated/postfix/{recipient_bcc,virtual_mailboxes,sender_login}`, `generated/dovecot/users` | `postfix reload` (mta); `doveadm reload` (imap) | Postfix lookups for changed addresses; `doveadm user` for both names; `doveadm auth test` for changed passwords |
| Domain added / removed | `generated/postfix/{relay_domains,transport}`, `generated/postfix/{relay_recipients,sender_login}` | `postfix reload` (mta) | Postfix lookups (`postmap -q`) |
| Recipient policy switched | `generated/postfix/{relay_recipients,relay_domains}` | `postfix reload` (mta) | Postfix lookups / `postconf -n` |
| Queue lifetime changed | Postfix main settings | `postfix reload` (mta) | `postconf` |
| Submission / auth / rate-limit changes | `master.cf`, Postfix main settings | restart of `mta` for `master.cf`; `postfix reload` for main settings | `postfix check`, lookups, auth tests |
| Dovecot mailbox added / password changed / removed | `generated/dovecot/users` | `doveadm reload` (imap) | `doveadm user`; `doveadm auth test` |
| Bulk edit | all affected generated files above | per-kind reloads | per-kind verifications, once for the whole set |

## Outputs

The `reference/` folder, `FORMAT.md`, and the apply sequence table (ticket E1-10 outputs).
