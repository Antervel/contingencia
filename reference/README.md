# Reference configuration files (golden files) — Epic 1, ticket E1-10

This folder is the **contract** for the Rust `admin` service (Epic 4) and the
input of its snapshot tests. It contains the example source state, the generated
configuration files rendered from that state, and the format specification that
tells the Rust author exactly how to produce the generated files.

## Layout

```
reference/
├── README.md                      this file
├── state/
│   ├── settings.example.toml      example appliance settings (technical.md section 4.3)
│   └── mail.example.toml          example domains and mailboxes (EPIC.md section 3)
├── generated/
│   ├── postfix/
│   │   ├── relay_domains
│   │   ├── transport
│   │   ├── virtual_mailboxes
│   │   ├── recipient_bcc
│   │   ├── relay_recipients
│   │   └── sender_login
│   └── dovecot/
│       └── users
└── FORMAT.md                      format rules and apply sequence
```

## How the files are used

1. The Rust admin service renders the files under `state/` into the files under
   `generated/` (the state is the source of truth; `generated/` is rebuildable).
2. Before applying, the service pre-checks the staged files inside the real
   containers (technical.md section 4.4, apply pipeline step 4).
3. On apply it moves the staged files into place atomically, reloads
   (`postfix reload` in `mta`, `doveadm reload` in `imap`), and verifies.
4. Snapshot tests in Epic 4 compare the rendered output byte-for-byte with the
   files in `generated/`.

## Generated files map

| Generated file | Consumed by | Generated from |
|---|---|---|
| `generated/postfix/relay_domains` | Postfix (`relay_domains = texthash:/config/postfix/relay_domains`) | `state/mail.toml` domains |
| `generated/postfix/transport` | Postfix (`transport_maps = texthash:/config/postfix/transport`) | relay domain + fake `main` |
| `generated/postfix/virtual_mailboxes` | Postfix (`virtual_mailbox_maps = texthash:/config/postfix/virtual_mailboxes`) | mailbox fixtures |
| `generated/postfix/recipient_bcc` | Postfix (`recipient_bcc_maps = texthash:/config/postfix/recipient_bcc`) | mailbox fixtures |
| `generated/postfix/relay_recipients` | Postfix (`relay_recipient_maps = texthash:/config/postfix/relay_recipients`) | mailbox fixtures |
| `generated/postfix/sender_login` | Postfix (`sender_login_maps = texthash:/config/postfix/sender_login`) | mailbox fixtures |
| `generated/dovecot/users` | Dovecot (passwd-file) | mailbox fixtures (SHA-512 crypt) |

## Snapshot tests

Epic 4 snapshot tests compare the Rust renderer's output against the files in
`generated/` character for character. Header comments, line ordering and line
endings are part of the contract (see `FORMAT.md`).
