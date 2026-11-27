#!/bin/sh
# Scenario 01 (ticket E1-04): relay with `main` up delivers the original to the sink.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
send_msg sender@sender.test alice@client.test "E1-11 relay up" "hello relay up"

if wait_for_sink 1 30; then
    pass "01 (E1-04): original relayed to main sink with main up"
else
    fail "01 (E1-04): original not relayed to main sink with main up"
fi

if wait_for_queue_empty 30; then
    pass "01 (E1-04): queue empty after successful relay"
else
    fail "01 (E1-04): queue not empty after successful relay"
fi
