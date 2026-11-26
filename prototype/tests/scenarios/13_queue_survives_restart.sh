#!/bin/sh
# Scenario 13 (ticket E1-07): queue survives an `mta` restart; delivery after recovery.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
$COMPOSE stop main >/dev/null 2>&1
sleep 3
send_msg sender@sender.test alice@client.test "E1-11 restart queue" "hello restart queue"

c=$(queue_pending_count)
if [ "$c" -gt 0 ]; then
    pass "13 (E1-07): original queued while main down"
else
    fail "13 (E1-07): original not queued while main down"
fi

$COMPOSE stop mta >/dev/null 2>&1
$COMPOSE start mta >/dev/null 2>&1
sleep 12
c2=$(queue_pending_count)
if [ "$c2" -gt 0 ]; then
    pass "13 (E1-07): queue survived mta restart"
else
    fail "13 (E1-07): queue lost on mta restart"
fi

$COMPOSE start main >/dev/null 2>&1
$COMPOSE exec -T mta postqueue -f >/dev/null 2>&1
if wait_for_sink 1 90; then
    pass "13 (E1-07): delivered after mta restart + main up"
else
    fail "13 (E1-07): delivered after mta restart + main up"
fi

reset_state
