#!/bin/sh
# Shared helper library for the prototype scenario tests (ticket E1-11).
# Extends prototype/tests/lib/sink.sh (ticket E1-02) with mail/IMAP/queue helpers.

LIB_DIR="${TESTS_LIB_DIR:-$(cd "$(dirname "$0")" && pwd)}"
SCRIPT_DIR="$LIB_DIR"
REPO_ROOT=$(cd "$LIB_DIR/../../.." && pwd)

# Provides $COMPOSE (from COMPOSE_FILE, default compose.yaml) and ensure_services().
TESTS_LIB_DIR="$LIB_DIR"
. "$LIB_DIR/stack.sh"

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

ensure_mta() {
    # Make sure the Postfix daemon is answering. A previous scenario may have
    # stopped the container; start it and poll until master(8) reports running.
    $COMPOSE start mta >/dev/null 2>&1 || true
    i=0
    while [ "$i" -lt 30 ]; do
        if $COMPOSE exec -T mta postfix status >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    # Last resort: restart the container and give master time to come up.
    $COMPOSE restart mta >/dev/null 2>&1 || true
    sleep 10
    $COMPOSE exec -T mta postfix status >/dev/null 2>&1
}

reset_state() {
    # Start from a known-good stack before running checks. This also repairs
    # state leaked by a scenario that failed after stopping a service.
    ensure_services
    ensure_mta
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
    #
    # Use the JSON output: Postfix queue IDs are not fixed-width (10 characters
    # locally, 11 on the CI runner). Parsing the fixed-width `mailq` layout with
    # a regex missed every message on CI and made the queue checks fail there.
    $COMPOSE exec -T mta postqueue -j 2>/dev/null | grep -c '"queue_id"' || true
}

wait_for_queue_at_least() {
    # wait_for_queue_at_least <min_count> <timeout_seconds> ; exits 0 on success.
    # A message is accepted by smtpd before qmgr records it in the queue, so poll
    # instead of sampling once.
    i=0
    while [ "$i" -lt "$2" ]; do
        c=$(queue_pending_count)
        if [ "${c:-0}" -ge "$1" ]; then
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
}

wait_for_queue_empty() {
    # wait_for_queue_empty <timeout_seconds> ; exits 0 when the queue drains.
    # qmgr removes a delivered message a moment after the sink acknowledges it,
    # so a single read right after delivery is racy.
    i=0
    while [ "$i" -lt "$1" ]; do
        c=$(queue_pending_count)
        if [ "${c:-0}" -eq 0 ]; then
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
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
