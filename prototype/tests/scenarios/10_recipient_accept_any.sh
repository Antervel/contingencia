#!/bin/sh
# Scenario 10 (ticket E1-06): recipient policy accept-any (default): unauthenticated
# client may relay to any relay domain, including relay domains without own mailboxes.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
send_msg sender@sender.test friend@outside.test "E1-11 accept any" "hello accept any"

if wait_for_sink 1 30; then
    pass "10 (E1-06): accept-any: relayed to relay domain without mailbox"
else
    fail "10 (E1-06): accept-any: not relayed"
fi

reset_state
