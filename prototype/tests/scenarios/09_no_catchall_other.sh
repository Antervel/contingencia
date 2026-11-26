#!/bin/sh
# Scenario 09 (ticket E1-06): other.test has no catch-all: unknown address there is
# relayed to the sink (as an outside-world recipient) but never copied to a mailbox.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
send_msg sender@sender.test nobody@other.test "E1-11 no catchall" "hello no catchall"

if wait_for_sink 1 30; then
    pass "09 (E1-06): relayed to sink (no catch-all copy expected)"
else
    fail "09 (E1-06): not relayed to sink"
fi

if imap_wait_ready carol@other.test carol-pass 0 15; then
    pass "09 (E1-06): no mailbox copy for unknown address in other.test"
else
    fail "09 (E1-06): mailbox copy for unknown address in other.test"
fi

reset_state
