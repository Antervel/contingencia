# mta container: Postfix (Epic 1, ticket E1-04).
#
# Debian base pinned by tag to the release decided in docs/FINDINGS.md
# (Debian 13 "Trixie").
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends postfix && rm -rf /var/lib/apt/lists/*

COPY prototype/config/postfix/main.cf /etc/postfix/main.cf
COPY prototype/config/postfix/master.cf /etc/postfix/master.cf

# Container-ready Postfix startup (technical.md E1-04: Postfix runs in the
# foreground as the container's main process; Postfix 3.3+ start-fg keeps
# master(8) in the foreground). Postfix logs to stdout via maillog_file
# (Postfix 3.4+ postlog unix-dgram service, already present in master.cf).
RUN postconf -e "maillog_file = /dev/stdout"

EXPOSE 25

CMD ["/usr/sbin/postfix", "start-fg"]
