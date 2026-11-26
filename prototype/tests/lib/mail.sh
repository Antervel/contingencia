#!/bin/sh
# Shared helper library for the prototype scenario tests (ticket E1-11).
# Extends prototype/tests/lib/sink.sh (ticket E1-02) with mail/IMAP/queue helpers.

LIB_DIR="${TESTS_LIB_DIR:-$(cd "$(dirname "$0")" && pwd)}"
SCRIPT_DIR="$LIB_DIR"
REPO_ROOT=$(cd "$LIB_DIR/../../.." && pwd)
COMPOSE="docker compose -f $REPO_ROOT/compose.yaml"

PASS=0
FAIL=0
FAILED_SCENARIOS=""

pass() {
    echo "PASS: $1"
}

fail() {
    echo "FAIL: $1"
    FAILED_SCENARIOS="$FAILED_SCENARIOS $1"
    FAIL=$((FAIL + 1))
    exit 1
}

reset_state() {
    # Empty sink (Mailpit).
    sh "$SCRIPT_DIR/sink.sh" clear >/dev/null 2>&1
    # Purge the Postfix queue.
    $COMPOSE exec -T mta postsuper -d ALL >/dev/null 2>&1 || true
    # Empty the fixture mailboxes.
    for u in alice@client.test bob@client.test _catchall@client.test carol@other.test; do
        $COMPOSE exec -T imap doveadm expunge -u "$u" mailbox INBOX all >/dev/null 2>&1 || true
    done
}

send_msg() {
    # send_msg <from> <to> <subject> <body>
    python3 "$SCRIPT_DIR/smtp_send.py" --server 127.0.0.1:2525 --from "$1" --to "$2" --subject "$3" --body "$4"
}

imap_count() {
    # imap_count <user> <password> ; prints the INBOX message count
    python3 "$SCRIPT_DIR/imap_check.py" --user "$1" --password "$2" --action count
}

imap_wait_ready() {
    # imap_wait_ready <user> <password> <expected_count> <timeout_seconds> ; exits 0 on success
    python3 "$SCRIPT_DIR/imap_check.py" --user "$1" --password "$2" --action wait --expected "$3" --timeout "$4" >/dev/null 2>&1
}

queue_pending_count() {
    # Prints number of queued messages.
    $COMPOSE exec -T mta mailq 2>/dev/null | grep -cE '^[A-F0-9]{10}[[:space:]]' || true
}

wait_for_sink() {
    # wait_for_sink <expected_count> <timeout_seconds> ; exits 0 on success
    i=0
    while [ "$i" -lt "$2" ]; do
        n=$(sh "$SCRIPT_DIR/sink.sh" count 2>/dev/null | grep -o '[0-9]*' | head -n1)
        if [ "${n:-0}" = "$1" ]; then
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
}
