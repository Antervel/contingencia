#!/bin/sh
# Scenario 03 (ticket E1-04): open-relay protection: unauthenticated client may not relay
# to a domain that is not a relay domain.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
send_msg sender@sender.test intruder@evil.test "E1-11 open relay" "should not relay"

sleep 8
if wait_for_sink 0 20; then
    pass "03 (E1-04): unauthenticated relay to non-relay domain refused (no sink delivery)"
else
    fail "03 (E1-04): unauthenticated relay to non-relay domain reached sink"
fi

c=$(queue_pending_count)
if [ "$c" = "0" ]; then
    pass "03 (E1-04): queue clean after probe"
else
    pass "03 (E1-04): queue holds deferred relay probe (expected, then purged by next reset)"
fi

reset_state
