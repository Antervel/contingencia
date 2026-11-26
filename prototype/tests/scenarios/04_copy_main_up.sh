#!/bin/sh
# Scenario 04 (ticket E1-05): copy to mailbox with main up: original to sink, BCC copy to INBOX.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
send_msg sender@sender.test alice@client.test "E1-11 copy up" "hello copy up"

if wait_for_sink 1 30; then
    pass "04 (E1-05): original delivered to sink with main up"
else
    fail "04 (E1-05): original not delivered to sink with main up"
fi

if imap_wait_ready alice@client.test alice-pass 1 30; then
    pass "04 (E1-05): BCC copy delivered to alice INBOX with main up"
else
    fail "04 (E1-05): BCC copy not delivered to alice INBOX with main up"
fi

c=$(queue_pending_count)
if [ "$c" = "0" ]; then
    pass "04 (E1-05): queue empty after copy scenario"
else
    fail "04 (E1-05): queue not empty after copy scenario"
fi
