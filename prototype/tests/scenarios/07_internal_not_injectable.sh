#!/bin/sh
# Scenario 07 (ticket E1-05): internal mailbox domain is not injectable from outside:
# a message addressed to the internal delivery name must not be delivered as a personal copy.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
send_msg sender@sender.test alice@copies.invalid "E1-11 internal inject" "hello internal"

if imap_wait_ready alice@client.test alice-pass 0 15; then
    pass "07 (E1-05): internal address not delivered into personal mailbox"
else
    fail "07 (E1-05): internal address delivered into personal mailbox"
fi

if wait_for_sink 0 20; then
    pass "07 (E1-05): internal address not relayed either"
else
    fail "07 (E1-05): internal address relayed"
fi

reset_state
