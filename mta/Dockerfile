# mta container: Postfix (Epic 1, ticket E1-04).
#
# Debian base pinned by tag to the release decided in docs/FINDINGS.md
# (Debian 13 "Trixie").
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends postfix && rm -rf /var/lib/apt/lists/*

COPY prototype/config/postfix/main.cf /etc/postfix/main.cf
COPY prototype/config/postfix/master.cf /etc/postfix/master.cf

EXPOSE 25

CMD ["/usr/lib/postfix/sbin/master"]
