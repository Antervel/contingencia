#!/bin/sh
# Scenario 02 (ticket E1-04): queue with `main` down holds the original; delivered on recovery.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
$COMPOSE stop main >/dev/null 2>&1
sleep 3
send_msg sender@sender.test alice@client.test "E1-11 queue down" "hello queue down"

if wait_for_sink 0 30; then
    pass "02 (E1-04): nothing delivered to sink while main is down"
else
    fail "02 (E1-04): delivered to sink while main was down"
fi

if wait_for_queue_at_least 1 30; then
    pass "02 (E1-04): original queued while main down"
else
    fail "02 (E1-04): original not queued while main down"
fi

$COMPOSE start main >/dev/null 2>&1
$COMPOSE exec -T mta postqueue -f >/dev/null 2>&1
if wait_for_sink 1 90; then
    pass "02 (E1-04): queued original delivered after main returned"
else
    fail "02 (E1-04): queued original not delivered after main returned"
fi

if wait_for_queue_empty 60; then
    pass "02 (E1-04): queue drained after recovery"
else
    fail "02 (E1-04): queue not drained after recovery"
fi
