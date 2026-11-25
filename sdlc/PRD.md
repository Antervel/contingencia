# PRD: Contingency Mail Appliance (standalone)

**Status:** Draft v1
**Working name:** `contingency`
**Customer:** One client (single-tenant, purpose-built appliance)
**Supersedes:** the mailcow-based variant (`contingency-PRD.md`)

---

## 1. Summary

When the client's main mail server (`main`) is down, its users cannot read incoming mail. `contingency` is a **small set of containers, deployed together**, acting as a backup mail server that:

1. Accepts mail for the client's domains while `main` is down, and queues the original messages so they are delivered to `main` once it is back.
2. Stores a **readable copy** of each message in a local mailbox, which users read through webmail.
3. Lets users send mail from webmail, using their normal address, while `main` is down.
4. Is managed through a small admin web interface where an administrator adds domains, mailboxes and an optional catch-all.

It is made of five containers started by one Compose file: the mail server (`mta`), the mailbox server (`imap`), the DKIM signer (`dkim`), the webmail (`webmail`, an existing Roundcube image) and the admin interface (`admin`). The images we build come from this project's repository. The environment is internal and sealed, and the admin interface is trusted to control the other containers.

## 2. Goals

- Users can read mail that arrived during a `main` outage, using their normal address and a password given by the administrator.
- No mail is lost: every message is also queued for `main` and delivered when it returns.
- The administrator manages everything from one web interface, with no command-line work after install.
- The whole server is defined by files in a repository, so any deployment can be rebuilt identically.
- Configuration is stored in plain, human-readable text files that can be inspected, backed up and edited by hand in an emergency.

## 3. Non-goals (v1)

- Spam filtering and virus scanning (explicitly excluded by the client).
- Inbound DMARC/SPF validation and DMARC reporting. DMARC for outbound mail is only a DNS record, managed by a human.
- Multi-client or multi-tenant operation.
- Configuring `main`, or managing DNS records (done by a human).
- Synchronizing reads, deletions or sent mail back to `main`.
- SMTP or IMAP access for mail clients. Access is by webmail only.
- Quotas and server-side mail filters.
- Multiple administrator accounts.
- Renaming a domain (delete and recreate instead).

## 4. Users and roles

| Role | Description |
|---|---|
| **Administrator** | One account. Configures the appliance and manages domains, mailboxes and the catch-all. |
| **Mailbox user** | Logs in to webmail as `a@something.com`, reads mail and sends mail. |
| **Installer (human)** | Deploys the container, provides the mail TLS certificate, runs the SSL terminator for webmail, sets DNS records, configures `main` to accept mail from the appliance. Outside the product, but the product depends on it. |

## 5. Concept and mail flow

### 5.1 Addressing

- Client domains (e.g. `something.com`) are accepted by the appliance only to receive mail and relay it to `main`.
- The appliance has exactly **one internal mailbox domain**, called `L` (a name that can never be routed on the internet). It is never exposed to users.
- A user's address `a@something.com` has an internal form `a^something.com@L`. The separator is provisional, isolated in one place, and must be decodable unambiguously.
- Both `a@something.com` (the login) and `a^something.com@L` (the delivery address) lead to the **same mailbox**.

### 5.2 Incoming message

1. A sender delivers a message for `a@something.com` to the appliance.
2. The appliance queues the **original** message for delivery to `main`, and keeps retrying until `main` accepts it or the queue lifetime expires.
3. The appliance also creates a **copy** addressed to `a^something.com@L`.
4. The copy is delivered into the mailbox of `a@something.com`.
5. The user logs in to webmail as `a@something.com` and reads it.

### 5.3 Outgoing message

1. The user composes a message in webmail, with `a@something.com` as sender.
2. The appliance accepts it only from a user authorized to use that sender address.
3. The message is signed with the DKIM key of `something.com` and sent to its recipients.
4. Mail is **only signed on this path**. Messages relayed to `main` are passed on untouched.

### 5.4 Catch-all (optional, per domain)

When enabled for a domain, mail for addresses without their own mailbox is copied into a dedicated catch-all mailbox for that domain. Addresses that have their own mailbox are **not** also copied there.

## 6. Functional requirements

### 6.1 First run and settings

- **FR-1** On first start the administrator creates the single admin account.
- **FR-2** The administrator sets, in the web interface: the appliance's public hostname, the address of `main`, the name of `L`, and the queue lifetime for undelivered mail.
- **FR-3** The administrator chooses whether the appliance accepts mail for **any** address in a client domain, or **only** for listed mailboxes and catch-all domains. The default is to accept any address, so that no mail is lost if `main` has addresses not listed here.

### 6.2 Domains

- **FR-4** Add a domain. The appliance generates a DKIM key for it and shows the DNS record to publish (DKIM, and a suggested SPF and DMARC record for the human to review).
- **FR-5** Modify a domain: enable or disable it, turn its catch-all on or off.
- **FR-6** Delete a domain, which removes its mailboxes, their stored mail and its DKIM key, after an explicit confirmation warning that stored mail will be destroyed.
- **FR-7** List domains, showing mailbox count and catch-all status.

### 6.3 Mailboxes

- **FR-8** For each domain, the administrator manages mailboxes, each with an address and a password.
- **FR-9** Add, change the password of, and delete individual mailboxes.
- **FR-10** Bulk edit: the administrator pastes or uploads a list (address and password per line). The interface shows a **preview** of what will be created, changed and deleted, and applies it on confirmation. A blank password keeps the current one.
- **FR-11** Deleting a mailbox removes its stored mail, after confirmation.
- **FR-12** Applying changes is **repeatable**: re-applying the same list produces the same result, with no duplicates and no errors.
- **FR-13** Changes take effect on the running appliance within seconds. The admin interface reloads or restarts only the components that need it, and does not take the whole appliance down.
- **FR-13a** After each change, the admin interface **verifies that it worked** by checking the affected components (for example, that a new mailbox resolves and its password authenticates). If verification fails, the change is rolled back automatically and the administrator sees the error.

### 6.4 Catch-all

- **FR-14** Enabling a domain's catch-all creates a catch-all mailbox for it, whose password the administrator sets. Disabling it removes the mailbox after confirmation.

### 6.5 Webmail

- **FR-15** Users log in to webmail with `a@something.com` and their password.
- **FR-16** Users can read, search, reply, compose and send. Sent mail uses the user's own address as sender.
- **FR-17** A user cannot send as an address that is not theirs.
- **FR-18** Webmail is served over plain HTTP on port 80. HTTPS is provided by an external SSL terminator in front of the appliance, and webmail must behave correctly behind it (secure cookies, correct links).

### 6.6 Status (read-only)

- **FR-19** The administrator can see: whether each component is running, the number of messages waiting for delivery to `main` and the age of the oldest one, and the last errors from each component's logs. The administrator can also flush the delivery queue manually, for example when `main` comes back.

### 6.7 Admin access and security

- **FR-20** The admin interface requires login. It must not be exposed to the public internet; it is reached locally, by VPN or by tunnel.
- **FR-21** Mailbox passwords are never stored in readable form.
- **FR-22** Repeated failed logins (admin or webmail) are slowed down or blocked.
- **FR-23** Outgoing mail is rate-limited per sender, to limit damage from a compromised mailbox.

## 7. Data and configuration

- All configuration and state live in **plain text files** on a persistent volume: settings, the domain list, the mailbox list (with password hashes), and DKIM keys.
- The appliance's server configuration (mail server maps, mailbox server user file, DKIM tables) is **generated** from those files. The files are the source of truth, and generated output can be deleted and rebuilt at any time.
- Stored mail, the delivery queue, webmail data and logs live on persistent volumes, separate from configuration.
- A backup of the configuration volume plus the mail volume is enough to restore the appliance on a new host.

## 8. Installation and operation

- **IR-1** Delivered as five containers defined in one deployment file (Docker Compose): four images we build or reuse for the mail components (`mta`, `imap`, `dkim`, and an existing Roundcube image for `webmail`) and one for the admin interface. One command brings the whole appliance up.
- **IR-2** Installer supplies: a hostname, a TLS certificate and key for the mail server's SMTP encryption (web HTTPS is handled by the external terminator), the address of `main`, and an initial admin password (or sets it at first run).
- **IR-3** Exposed ports: mail reception (25) to the internet, and plain HTTP for webmail (80) to the SSL terminator only. All other services (admin interface, mailbox access, mail submission) are reachable only inside the container or from the local host.
- **IR-4** Each component logs to its own container's standard output, and each runs a single service.
- **IR-5** Each container reports its own health, and the stack starts in a defined order (admin interface first, then the mail components, then webmail).
- **IR-6** Upgrades replace one or more images. Configuration and mail volumes are kept, and a single component (for example webmail) can be upgraded without rebuilding the others.
- **IR-7** The admin container has access to the Docker socket, so it can run commands in, restart and read logs of the other containers. No other container has it.

## 9. Assumptions

- A human configures `main` to accept mail from the appliance, and publishes all DNS records (MX with the appliance at lower priority than `main`, SPF including the appliance, DKIM, DMARC, reverse DNS).
- The appliance's public IP has a good reputation and a matching reverse DNS name.
- An SSL terminator already exists, forwards the `X-Forwarded-Proto` header, and reaches the appliance over a trusted network path, since logins cross it as plain HTTP.
- The environment is internal and sealed, built for this one client. The admin interface may therefore hold the Docker socket, which gives it full control of the host's containers, and its login is the main protection for that.
- The number of users and mail volume are modest, and the appliance is used during outages only.
- Receiving spam during an outage is acceptable. `main` still filters the queued originals.
- Duplicate copies (a message delivered both to `main` and to the appliance) are acceptable.

## 10. Risks and items to validate

1. **Copy rule on relayed mail.** Confirm the copy to `a^something.com@L` is made for messages that are only being relayed, not delivered locally.
2. **Internal domain name.** Confirm the chosen name for `L` and the `^` separator are accepted at every step. Fallback: a different name or separator.
3. **Catch-all precedence.** Confirm an address with its own copy rule is not also copied to the catch-all.
4. **Backscatter.** If the appliance accepts any address and `main` later rejects some, bounces may go to forged senders. Accepted in v1. The setting in FR-3 lets the administrator choose otherwise.
5. **DKIM only on sending.** Confirm relayed messages to `main` are never signed, and webmail-submitted messages always are.
6. **Webmail login by full address.** Confirm webmail, the mailbox server and the mail server all accept the full address as login name.
7. **Abuse.** Without filtering, a compromised mailbox can send spam. Rate limits (FR-23) reduce but do not remove the risk.
8. **Queue lifetime.** If `main` is down longer than the queue lifetime, queued mail bounces to senders. The default is **100 days**, editable in the interface, and must be documented and visible there. A long outage needs enough disk for the queue.

## 11. Acceptance criteria

- **AC-1** With `main` unreachable, a message to `a@something.com` is accepted and appears in `a@something.com`'s webmail within a minute.
- **AC-2** When `main` comes back, the same message reaches `main` with no human action.
- **AC-3** A user logs in with `a@something.com` and the given password and sees only their own mail.
- **AC-4** A user sends a message from webmail as `a@something.com`. The recipient receives it with a valid DKIM signature for `something.com`.
- **AC-5** A user cannot send as another user's address.
- **AC-6** The administrator adds a domain and a list of mailboxes in the admin interface, and mail flows for them with no other manual step.
- **AC-7** Changing a mailbox password makes the old password stop working and the new one work.
- **AC-8** Deleting a mailbox and a domain removes them, their stored mail and their DKIM key.
- **AC-9** With the catch-all enabled, mail for an unknown address in the domain lands in the catch-all mailbox only, and mail for a known address lands only in its own mailbox.
- **AC-10** Re-applying the same change twice leaves the appliance unchanged.
- **AC-11** Restarting any single container, or the whole appliance, loses no configuration, stored mail or queued mail.
- **AC-11a** A change that fails verification is rolled back, and the appliance keeps working with its previous configuration.
- **AC-12** On a fresh host, the documented install steps alone produce a working appliance.

## 12. Out of scope for later versions

- Syncing read state, deletions and sent mail back to `main`.
- SMTP and IMAP access for mail clients.
- Multiple administrators and an audit log.
- Automatic import of mailboxes from `main`.
- Spam and virus filtering.
- Inbound DMARC reports and aggregate reporting.
