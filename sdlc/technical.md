# Technical Design: Contingency Mail Appliance

Companion to `contingency-appliance-PRD.md`. Version names are left to implementation time. Items marked **(verify)** are things I believe are right but that must be tested first.

The appliance is a small set of containers deployed together with one Docker Compose file, in a sealed internal environment. The admin service is trusted with the Docker socket.

---

## 1. Containers

| Container | Image | Runs | Exposed |
|---|---|---|---|
| `mta` | Ours: Debian + **Postfix** | Port 25 reception and backup-MX relay, copy (BCC) rules, authenticated submission (587) for webmail | 25 to the internet; 587 internal only |
| `imap` | Ours: Debian + **Dovecot** | Maildir storage, LMTP delivery, IMAP for webmail, login checks and SASL for Postfix | Internal only |
| `dkim` | Ours: Debian + **dkimpy-milter** (Debian package) | Signs outgoing webmail mail only, one key per domain | Internal only |
| `webmail` | **Official Roundcube image** (Apache variant, SQLite) | Webmail, plain HTTP on port 80 | 80 to the external SSL terminator only |
| `admin` | Ours: Rust, small base image | Admin web interface, config generation, control of the other containers | Internal interface only, port 8080 |

Everything we build comes from Debian's packages (Postfix, Dovecot, dkimpy-milter) plus our config files. The only compiled code is the Rust admin service. Each container runs **one service in the foreground**, so no process supervisor is needed: Docker restart policies and health checks keep things running, and logs of each service are that container's output.

No spam filter, no antivirus, no OpenDMARC. DMARC is only a DNS record for outbound mail.

## 2. Network and ports

All containers share one private Compose network. Only these ports are published:

| Port | Published to | Purpose |
|---|---|---|
| 25 | Internet (container `mta`) | Mail reception |
| 80 | The SSL terminator only (container `webmail`) | Webmail, plain HTTP |
| 8080 | An internal interface only (container `admin`) | Admin interface |

Internal-only traffic on the private network:

| From → To | Protocol |
|---|---|
| `mta` → `imap` | LMTP delivery of mail and copies; SASL authentication for submission |
| `mta` → `dkim` | Milter protocol (signing, submission service only) |
| `webmail` → `imap` | IMAP |
| `webmail` → `mta` | Submission on port 587, with the user's credentials |

None of these ports are published to the host.

**Web TLS is not handled here.** The external SSL terminator forwards plain HTTP to `webmail` and sets `X-Forwarded-Proto`. Roundcube must treat the session as HTTPS (secure cookies, correct links), which means trusting the terminator's address as a proxy **(verify the exact Roundcube setting)**. Port 80 must be reachable only from the terminator, because logins cross that hop in clear text.

**Mail TLS is still needed.** The terminator does not cover SMTP, so `mta` needs a certificate and key for STARTTLS on port 25. The installer mounts them read-only into `mta`; no other container needs them.

## 3. Mail design

### 3.1 Receiving and copying (`mta`)

- **Relay domains.** The client's domains are Postfix `relay_domains`. A generated transport map routes each of them to `main` directly (`[main-host]:25`), without an MX lookup, so mail can never loop back to the appliance.
- **Queue lifetime.** `maximal_queue_lifetime` is set from the settings file, with a default of **100 days**. `bounce_queue_lifetime` is set to the same value, so a message that cannot be delivered for 100 days bounces only after that. The queue volume must be sized for a long outage.
- **Recipient policy.** "Accept any address" leaves relay recipients open. "Listed only" adds a generated `relay_recipient_maps` file.
- **Copy rule.** `recipient_bcc_maps` is a generated map: `a@something.com` → `a^something.com@L`. For a catch-all domain, an entry `@something.com` → `_catchall^something.com@L`. Postfix tries the full address before the `@domain` form, so known addresses do not also land in the catch-all **(verify)**. Copies are made for relayed mail as well as local mail **(verify)**.
- **Internal domain `L`.** Its name is chosen **at install time** (see 4.3) and is fixed afterwards. It is a Postfix `virtual_mailbox_domains` entry delivered over LMTP to `imap`. The generated `virtual_mailbox_maps` lists every `a^something.com@L`. `L` uses a never-routed name such as one ending in `.invalid` **(verify Postfix accepts it)**.
- **Table format.** Generated tables use Postfix's `texthash:` type, which reads the plain text file directly, so no `postmap` step is needed. A change then needs at most a `postfix reload` **(verify)**.

### 3.2 Mailboxes (`imap`)

One generated passwd-file serves as both user database and password database. Each mailbox has **two lines** that share one home directory:

- the login `a@something.com`, with the password hash;
- the delivery name `a^something.com@L`, with no password (login disabled).

So the same Maildir answers to both names. No SQL and no Dovecot-side tricks are needed. Mailbox homes sit under a single `vmail` user, in a path based on domain and local part. Password hashes use SHA-512 crypt, which Dovecot reads natively. Dovecot serves LMTP, IMAP and the SASL authentication socket for Postfix over TCP on the private network **(verify the listener settings)**.

### 3.3 Sending (`mta` and `webmail`)

- Roundcube connects to `mta` on port 587 with the user's own credentials.
- Postfix authenticates through Dovecot (SASL, over the private network).
- `smtpd_sender_login_maps` (generated) lets `a@something.com` use only that sender. `reject_sender_login_mismatch` enforces it.
- The DKIM milter is attached to the **submission service only** (in `master.cf`), not to port 25. Relayed mail to `main` is never signed.
- **Rate limit: 1 message per second** on submission. Webmail submits every user's mail from the same container address, so Postfix's per-client limit (anvil) would apply to all users **combined**, not per user. That is the v1 behavior: a sustained rate above one message per second from webmail is slowed down, which is enough to stop a compromised mailbox from sending bulk spam. A true per-sender limit would need a separate policy service, and is left for later. The limit applies to submission only, never to mail received on port 25 **(verify the exact anvil settings, which count messages per time window)**.

### 3.4 DKIM (`dkim`)

- **Tool:** dkimpy-milter from Debian's package. No Python virtual environment is needed, and security updates arrive with the base image.
- **Keys:** one RSA key per domain, generated by running the key generator inside the `dkim` container (via the Docker API). The admin service captures the output and stores the keys as plain files under its config volume, one folder per domain. The selector name is a fixed setting.
- **Tables:** a generated signing table (which sender domain uses which key) and key table **(verify dkimpy-milter's exact config format and whether it supports tables; if not, the admin service writes a single multi-domain config, or one instance per domain)**.
- **Reload:** dkimpy-milter reads its config at startup, so after a key or table change the admin service restarts the `dkim` container.
- **DNS output:** the admin interface prints the public key as the TXT record to publish.

## 4. The admin service (Rust)

### 4.1 Responsibilities

- Serve the admin web interface.
- Own all configuration state in plain text files.
- Generate every server config file from that state.
- Control the other containers through the Docker API: run commands inside them, restart them, read their logs and health.
- Verify that each change worked, and roll it back if it did not.
- Report component and queue status.

It reaches containers through the Docker socket, mounted into this container only. This makes the container effectively root on the host. In this sealed environment that is accepted. Containers are found by their Compose service name, so the Compose project name is fixed.

### 4.2 Crates

| Need | Crate |
|---|---|
| Async runtime | `tokio` |
| HTTP server and routing | `axum`, with `tower` and `tower-http` (static files, request limits, tracing) |
| Page templates | `askama` (compile-time server-rendered HTML) |
| Interactivity | Server-rendered forms, with a little `htmx` loaded as one static file; no JS build step |
| Docker control | `bollard` (exec in containers, restart, logs, inspect/health) |
| Config files | `serde` and `toml` |
| Sessions and cookies | `tower-sessions` with an in-memory store, or `axum-extra` signed cookies |
| Admin password hash | `argon2` |
| Mailbox password hash | `sha-crypt` (SHA-512 crypt, for Dovecot) |
| Randomness | `rand` |
| Address and domain validation | `email_address` plus a small domain-name check of our own |
| Atomic file writes | `tempfile` |
| Errors | `thiserror` for library code, `anyhow` in `main` and handlers |
| Logging | `tracing` and `tracing-subscriber` (to stdout) |
| Tests | `tokio::test`, `tempfile`, `insta` for snapshot tests of generated config |

CSRF protection: SameSite=Strict cookies plus a per-session token in every form.

### 4.3 State files (plain text, TOML)

Located under `/data/config/`, mode 600 for secrets, owned by the admin service user.

```
/data/config/settings.toml      appliance settings and admin password hash
/data/config/mail.toml          domains, mailboxes (with password hashes), catch-all flags
/data/config/dkim/<domain>/     private key (.pem) and public record (.txt) per domain
/data/config/generated/         files rendered for the other containers (rebuildable)
```

`settings.toml` holds: public hostname, `main` address, name of `L`, queue lifetime (default 100 days), accept-any-recipient flag, DKIM selector, submission rate limit (default 1 message per second).

The name of `L` is set **at install time**, by an environment variable in the Compose file read by `admin` on first start and written into `settings.toml`. After that the interface shows it read-only, because every stored mailbox name contains it. Changing it later means a manual migration, not a setting. The address separator is `^`, fixed in the code.

`mail.toml` holds a list of domains. Each domain has an enabled flag, a catch-all flag, and a list of mailboxes (local part and password hash).

These files are the source of truth. The `generated/` folder can be deleted and rebuilt at any time. Hand-editing the TOML files and pressing "re-apply" (or restarting `admin`) regenerates everything.

### 4.4 Apply pipeline

Every change in the interface (and every bulk edit) runs the same pipeline:

1. Take a global lock, so only one apply runs at a time.
2. Load state, apply the requested change in memory, and validate it (names, duplicates, reserved names).
3. Render all generated files into a staging folder:
   - `mta`: relay domains, transport map, recipient maps, copy map, virtual mailbox map, sender-login map
   - `imap`: passwd-file
   - `dkim`: signing and key tables
4. **Pre-check in the real containers:** run lookups against the staged files inside `mta` (for example, query the copy map for a known address) to confirm they parse.
5. Snapshot the live generated files as "previous", then move the staged files into place and write the new state file atomically.
6. **Reload:** `postfix reload` in `mta`, `doveadm reload` in `imap`, restart of `dkim` (only if keys or tables changed).
7. **Verify the change worked**, by running commands inside the containers:
   - `postfix check` in `mta`
   - a lookup in the copy map and the virtual mailbox map for every address that changed
   - `doveadm user` for both names of every changed mailbox
   - for every new or changed password, `doveadm auth test` against `imap`
   - `dkim` reports healthy after its restart
8. If any verification fails: restore the "previous" files, reload again, and show the error. If all pass, release the lock and report success.

The pipeline is idempotent, which gives FR-12 for free.

### 4.5 Bulk edit

The pasted list is parsed into a desired state for a domain. The service diffs it against current state and returns the preview (create, change password, delete). Confirming runs the apply pipeline once for the whole set.

### 4.6 Status page

- Container state and health, from the Docker API.
- Queue size and age of the oldest message, from Postfix's JSON queue listing run inside `mta`.
- The last N log lines of each container, from the Docker logs API.
- A "flush queue" action (`postqueue -f` in `mta`), useful when `main` returns.

### 4.7 Mail data deletion

Deleting a mailbox or domain removes its Maildir directories by running a command inside `imap` (which owns the mail volume), after the state has been applied successfully.

## 5. Webmail configuration (`webmail`)

- Official Roundcube image, SQLite on a persistent volume.
- Settings come from the image's environment variables plus one small mounted config file for things the variables don't cover **(verify which)**:
  - IMAP host `imap`, SMTP host `mta` port 587
  - SMTP username and password are the login credentials (`%u` and `%p`)
  - login with the full address, no domain suffixing
  - trusted proxy address of the SSL terminator, so forwarded-protocol headers are honored
- Plugins are kept to a minimum.

## 6. Repository layout and volumes

```
/
├── compose.yaml               services, networks, volumes, health checks
├── admin/                     Rust admin service (Cargo project), Dockerfile
│   └── templates/             HTML templates
├── mta/                       Dockerfile, static parts of main.cf and master.cf
├── imap/                      Dockerfile, static dovecot config
├── dkim/                      Dockerfile, static dkimpy-milter config
├── webmail/                   Roundcube config override
├── .github/workflows/         CI/CD: build, test and publish images (section 12)
├── docs/                      install guide, DNS guide
└── tests/                     integration tests (section 8)
```

**Volumes**

| Volume | Read-write | Read-only |
|---|---|---|
| `config` | `admin` | `mta`, `imap`, `dkim` |
| `mail` | `imap` | none |
| `queue` | `mta` | none |
| `tls` | none | `mta` |
| `webmail-db` | `webmail` | none |

Containers that read the config volume share a group ID, so the generated files can be group-readable, with secrets (password hashes, DKIM keys) limited to the services that need them.

**Startup order:** `admin` first, because it renders the initial config from state (an empty one on first run). `imap`, `dkim` and `mta` wait for it to be healthy. `webmail` waits for `imap` and `mta`.

**Health checks:** each container checks its own service locally (Postfix answers on 25, Dovecot on IMAP, the milter socket accepts connections, Roundcube answers on 80, the admin interface answers on 8080).

## 7. Security notes

- Public surface is Postfix on 25. Webmail on port 80 is plain HTTP and must be reachable only from the SSL terminator.
- Only `mta` and `webmail` publish a port to the outside, and `admin` publishes to an internal interface only. Every other port stays on the private network.
- The admin service holds the Docker socket and is trusted accordingly. It must therefore be reachable only from the internal environment, and its login protects everything else.
- Config files and DKIM private keys are readable only by the services that need them.
- Password hashes only. Plain passwords exist in memory just long enough to hash them, and long enough to run the `doveadm auth test` check.
- Login brute-force: a counter in the admin service for admin logins; for webmail, Roundcube's own limits plus Dovecot's auth delay.
- Postfix restrictions: reject unauthenticated relay, require sender-login match on submission, rate limits on submission.

## 8. Testing

- **Unit tests:** state parsing, validation, address encoding and decoding, rendering of every generated file (snapshot tests).
- **Integration test (Compose):** the full appliance plus a fake `main` server. A test script uses a command-line SMTP client to:
  1. Send mail to the appliance with `main` down. Check it appears in the user's mailbox over IMAP, and sits in the queue.
  2. Start `main`. Check the original arrives there.
  3. Submit a message through the webmail path and check its DKIM signature.
  4. Check a user cannot send as someone else.
  5. Check catch-all and non-catch-all precedence.
  6. Repeat an apply and check nothing changes.
  7. Make an apply fail on purpose and check it rolls back.
- **Manual pre-build checks:** the **(verify)** items above, done by hand on a plain Compose prototype first. In particular: copy rule on relayed mail, the `.invalid` domain, `texthash` tables, and the dkimpy-milter configuration format.

## 9. Build order

1. Hand-built Compose prototype with `mta` and `imap` only, with hand-written config files, to prove mail flow (copy rule, two-name users, catch-all).
2. Add `dkim` on the submission path, and prove signing.
3. Add `webmail`, and prove login and sending.
4. Rust service: state files and the render step, with snapshot tests, producing exactly the hand-written files from step 1.
5. Rust service: the Docker control layer, apply pipeline, verification and rollback.
6. Rust service: web interface (domains, mailboxes, bulk edit, settings, status).
7. Health checks, startup order, install documentation.
8. Integration test suite, then a trial on a staging host with a real `main`.

## 10. Decisions

| Topic | Decision |
|---|---|
| Queue lifetime | 100 days (default, editable in settings) |
| Address separator | `^`, fixed in the code. Fallback to be considered only if the manual check shows a component rejects it |
| Name of `L` | Chosen at install time, read-only afterwards |
| Submission rate limit | 1 message per second, applied to webmail submissions as a whole |
| Queue lifetime warning | None. No warning in the interface when `main` has been down for most of the queue lifetime |
| Per-sender rate limit | Later. Not in v1 |
| Admin interface TLS | None. The admin interface is plain HTTP, used internally only, and is not fronted by the SSL terminator |

## 11. Open decisions

None at this point. The remaining uncertainty is in the **(verify)** items, which the hand-built prototype (section 9, step 1) is meant to settle. The CI/CD assumptions listed in section 12.7 still need confirmation.

## 12. Build and publish (CI/CD)

### 12.1 Requirement

PRD requirement IR-8: the images we build are built and published automatically by GitHub's CI/CD on every push to `main`, only if the checks pass, and each image can be traced to its commit.

### 12.2 What is built

| Image | Built by us | Notes |
|---|---|---|
| `mta` | Yes | Debian + Postfix |
| `imap` | Yes | Debian + Dovecot |
| `dkim` | Yes (from Epic 2) | Debian + dkimpy-milter |
| `admin` | Yes (from Epic 4) | Rust, multi-stage build |
| `webmail` | **No** | The upstream Roundcube image, only pulled. Its tag (ideally its digest) is pinned in the Compose file so upgrades are deliberate |

Each epic that introduces an image adds that image to the pipeline. The pipeline itself is created in ticket E1-13, with `mta` and `imap`.

### 12.3 Workflow (GitHub Actions)

One workflow file under `.github/workflows/`, with these triggers:

| Trigger | Behavior |
|---|---|
| Push to `main` | Build, test and, if the tests pass, **publish** |
| Pull request | Build and test only. **Never publish** |
| Manual run | Same as a push to `main`, for re-running after a failure |

Jobs, in order:

1. **Build**, one job per image (a matrix, so a new image is one more line). The same image that is tested is the one that is published: it is passed to the next jobs as a build artifact, or pushed under a temporary tag and re-tagged, and is **not rebuilt** between testing and publishing.
2. **Test.** Starts the Compose stack from the freshly built images on the runner and runs the checks: configuration validation inside each container, container health checks, and the scenario suite (`prototype/tests/run-all.sh`) once it exists.
3. **Publish**, which runs only for pushes to `main` and only if build and test passed. It pushes the images and sets their tags.

Superseded runs of the same pull request are cancelled. Runs on `main` are never cancelled halfway through a publish.

### 12.4 Registry and tags

- **Registry:** GitHub's own container registry, one image per component, named after the repository. (Assumption, see 12.7.)
- **Tags on every publish:**
  - the **full commit hash**, which is immutable and what installs should pin;
  - `latest`, a moving tag that always points to the newest `main` build. It is for convenience only, and installs should not rely on it.
- **Labels on every image** (standard image metadata): source repository, commit hash, and build time, so anyone can trace a running container to its commit.
- **Base images** (the Debian release) are pinned by tag, and the Debian release is the one recorded in `docs/FINDINGS.md`.

### 12.5 How the Compose files use the images

- `compose.yaml` keeps building images locally (`build:`), for development and the prototype.
- A second file, `compose.release.yaml`, uses `image:` references to the registry, with the tag set by one variable. A production install sets that variable to a **specific commit hash**, so the same install is reproducible and upgrading means changing one value and pulling.
- `webmail` is pinned in both files.

### 12.6 Security of the pipeline

- The workflow gets the **minimum permissions** it needs: read access to the repository, and write access to packages only in the publish job.
- No secrets are baked into any image. Configuration reaches containers only through volumes and environment variables at run time.
- Third-party actions used by the workflow are pinned to a specific commit, not to a moving tag.
- Images do not contain build tools, source code, or the Docker socket. The Docker socket reaches only the `admin` container, at run time, through Compose.
- Postfix and Dovecot need to start as root to bind ports and drop privileges. This is normal for those services. Everything else should run as a non-root user where practical.

### 12.7 Assumptions to confirm

| Topic | Assumed for now | Needs a decision? |
|---|---|---|
| Registry | GitHub's container registry | Yes, if the client's environment cannot use it |
| Image visibility | Private to the repository's organization | Yes |
| Architectures | One (the architecture of the client's servers, normally `amd64`) | Yes, if the client uses ARM |
| Vulnerability scanning | **Not** in v1 | Optional, can be added as a job later |
| Delivery into the sealed environment | The environment can pull from the registry | **Yes.** If it cannot, a documented offline route is needed (exporting images as archives and loading them) |
| Tests gate publishing | Yes, always | No |
