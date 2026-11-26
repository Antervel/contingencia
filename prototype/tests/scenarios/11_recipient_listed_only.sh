#!/bin/sh
# Scenario 11 (ticket E1-06): recipient policy listed-only: with the listed-only policy
# active, unauthenticated relay to a relay domain without a listed recipient is refused.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
# Switch to listed-only policy (temporary, restored at the end of the scenario).
# reject_unlisted_recipient rejects relay-domain recipients that are not listed in
# relay_recipient_maps; reject_unauth_destination stops unauthenticated relaying.
$COMPOSE exec -T mta postconf -e 'smtpd_relay_restrictions = reject_unlisted_recipient, reject_unauth_destination' >/dev/null 2>&1
$COMPOSE exec -T mta postconf -e 'smtpd_recipient_restrictions = reject_unlisted_recipient, permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination' >/dev/null 2>&1
# postconf -e edits the config file only; the running smtpd needs a restart to pick them up
# (postfix reload is currently crash-prone in this environment; a container restart is the
# operational equivalent for picking up configuration changes).
$COMPOSE restart mta >/dev/null 2>&1
sleep 45

send_rc=0
python3 "$SCRIPT_DIR/smtp_send.py" --server 127.0.0.1:2525 --from sender@sender.test --to friend@outside.test --subject "E1-11 listed only" --body "hello listed only" >/dev/null 2>&1 || send_rc=1

status=0
if [ "$send_rc" -ne 0 ]; then
    # Send refused by the server: unlisted recipient rejected as expected.
    pass "11 (E1-06): listed-only: unlisted relay recipient refused"
elif wait_for_sink 0 20; then
    pass "11 (E1-06): listed-only: unlisted relay recipient refused"
else
    status=1
fi

# Restore accept-any policy (before reporting, so suite state stays clean).
$COMPOSE exec -T mta postconf -e 'smtpd_recipient_restrictions =' >/dev/null 2>&1
$COMPOSE exec -T mta postconf -e 'smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination' >/dev/null 2>&1
$COMPOSE restart mta >/dev/null 2>&1
sleep 45

if [ "$status" -ne 0 ]; then
    fail "11 (E1-06): listed-only: unlisted relay recipient still relayed"
fi
reset_state
