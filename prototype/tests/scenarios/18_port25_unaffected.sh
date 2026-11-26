#!/bin/sh
# Scenario 18 (ticket E1-08): port 25 keeps E1-04 behaviour: no auth, no sender check, no rate limit.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
send_msg alice@client.test friend@outside.test "E1-11 port25" "hello port25"

if wait_for_sink 1 30; then
    pass "18 (E1-08): port 25 unauthenticated relay to relay domain works (no auth/sender check)"
else
    fail "18 (E1-08): port 25 unauthenticated relay failed"
fi
reset_state
