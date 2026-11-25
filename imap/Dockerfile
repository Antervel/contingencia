# imap container: Dovecot (Epic 1, ticket E1-03).
#
# Debian base pinned by tag to the release decided in docs/FINDINGS.md
# (Debian 13 "Trixie").
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        dovecot \
        dovecot-imapd \
        dovecot-lmtpd \
    && rm -rf /var/lib/apt/lists/*

# Hand-written prototype configuration, mounted read-only at /config by compose.
COPY prototype/config/dovecot/ /config/dovecot

EXPOSE 143

CMD ["dovecot", "-c", "/config/dovecot/dovecot.conf"]
