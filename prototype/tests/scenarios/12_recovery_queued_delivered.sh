#!/bin/sh
# Scenario 12 (ticket E1-07): recovery: queued original delivered when `main` returns.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
$COMPOSE stop main >/dev/null 2>&1
sleep 3
send_msg sender@sender.test alice@client.test "E1-11 recovery" "hello recovery"
$COMPOSE start main >/dev/null 2>&1
if wait_for_sink 1 45; then
    pass "12 (E1-07): queued original delivered after main returned"
else
    fail "12 (E1-07): queued original not delivered after main returned"
fi

reset_state
