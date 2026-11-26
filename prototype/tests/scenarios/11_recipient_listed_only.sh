#!/bin/sh
# Scenario 11 (ticket E1-06): recipient policy listed-only: with the listed-only policy
# active, unauthenticated relay to a relay domain without a listed recipient is refused.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
# Switch to listed-only policy (temporary, restored at the end of the scenario).
$COMPOSE exec -T mta postconf -e 'smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination' >/dev/null 2>&1
sleep 3

send_msg sender@sender.test friend@outside.test "E1-11 listed only" "hello listed only"

if wait_for_sink 0 20; then
    pass "11 (E1-06): listed-only: unlisted relay recipient refused"
else
    fail "11 (E1-06): listed-only: unlisted relay recipient still relayed"
fi

# Restore accept-any policy.
$COMPOSE exec -T mta postconf -e 'smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination' >/dev/null 2>&1

reset_state
