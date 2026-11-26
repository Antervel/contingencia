#!/bin/sh
# Scenario 08 (ticket E1-06): catch-all precedence (H4): exact BCC entries take
# precedence over the domain catch-all; unknown addresses go to the catch-all.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state

send_msg sender@sender.test alice@client.test "E1-11 catch exact" "hello exact"
if imap_wait_ready alice@client.test alice-pass 1 30; then
    pass "08 (E1-06): known address -> own mailbox (catch-all not used)"
else
    fail "08 (E1-06): known address -> own mailbox (catch-all not used)"
fi
if imap_wait_ready _catchall@client.test catchall-pass 0 15; then
    pass "08 (E1-06): catch-all mailbox empty for known address"
else
    fail "08 (E1-06): catch-all mailbox not empty for known address"
fi

send_msg sender@sender.test nobody@client.test "E1-11 catch all" "hello catch all"
if imap_wait_ready _catchall@client.test catchall-pass 1 30; then
    pass "08 (E1-06): unknown address -> catch-all mailbox"
else
    fail "08 (E1-06): unknown address -> catch-all mailbox"
fi

reset_state
