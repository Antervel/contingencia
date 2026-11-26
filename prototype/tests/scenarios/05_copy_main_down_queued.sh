#!/bin/sh
# Scenario 05 (ticket E1-05): copy to mailbox, main down: original queued, delivered on recovery.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
$COMPOSE stop main >/dev/null 2>&1
sleep 3
send_msg sender@sender.test alice@client.test "E1-11 copy down" "hello copy down"

if wait_for_sink 0 30; then
    pass "05 (E1-05): no sink delivery while main down (original queued)"
else
    fail "05 (E1-05): delivered to sink while main down"
fi

c=$(queue_pending_count)
if [ "$c" -gt 0 ]; then
    pass "05 (E1-05): original queued while main down"
else
    fail "05 (E1-05): original not queued while main down"
fi

$COMPOSE start main >/dev/null 2>&1
if wait_for_sink 1 45; then
    pass "05 (E1-05): queued original delivered after main returned"
else
    fail "05 (E1-05): queued original not delivered after main returned"
fi

c=$(queue_pending_count)
if [ "$c" = "0" ]; then
    pass "05 (E1-05): queue drained after recovery"
else
    fail "05 (E1-05): queue not drained after recovery"
fi
