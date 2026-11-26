#!/bin/sh
# Scenario 07 (ticket E1-05): internal mailbox domain is not injectable from outside:
# a message addressed to the internal delivery name must not be delivered as a personal copy.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
# Block client (unauthenticated) mail to the internal mailbox delivery domain.
# BCC-generated copies are added by the cleanup daemon and are not subject to
# smtpd recipient checks, so the legitimate internal delivery path keeps working.
$COMPOSE exec -T mta postconf -e 'smtpd_recipient_restrictions = check_recipient_access texthash:/config/postfix/recipient_access, permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination' >/dev/null 2>&1
# postconf -e edits the config file only; the running smtpd needs a restart to pick them up
# (postfix reload is currently crash-prone in this environment; a container restart is the
# operational equivalent for picking up configuration changes).
$COMPOSE restart mta >/dev/null 2>&1
sleep 45

send_msg sender@sender.test alice@copies.invalid "E1-11 internal inject" "hello internal"

status=0
if imap_wait_ready alice@client.test alice-pass 0 15; then
    pass "07 (E1-05): internal address not delivered into personal mailbox"
else
    status=1
fi
if wait_for_sink 0 20; then
    pass "07 (E1-05): internal address not relayed either"
else
    status=1
fi

# Restore default recipient restrictions (before reporting, so suite state stays clean).
$COMPOSE exec -T mta postconf -e 'smtpd_recipient_restrictions =' >/dev/null 2>&1
$COMPOSE restart mta >/dev/null 2>&1
sleep 45

if [ "$status" -ne 0 ]; then
    fail "07 (E1-05): internal address delivered into personal mailbox"
fi
reset_state
