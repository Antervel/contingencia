# imap container: Dovecot (Epic 1, ticket E1-03).
#
# Debian base pinned by tag to the release decided in docs/FINDINGS.md
# (Debian 13 "Trixie").
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        dovecot-core \
        dovecot-imapd \
        dovecot-lmtpd \
    && rm -rf /var/lib/apt/lists/*

# Hand-written prototype configuration, mounted read-only at /config by compose.
COPY prototype/config/dovecot/ /config/dovecot

# Mailbox base directory for the passwd-file users (uid 5000, gid 5001; see
# reference/generated/dovecot/users and reference/FORMAT.md).
RUN mkdir -p /var/mail/vhosts && chown -R 5000:5001 /var/mail/vhosts

EXPOSE 143

CMD ["dovecot", "-F", "-c", "/config/dovecot/dovecot.conf"]
