#!/bin/sh
# Scenario 14 (ticket E1-08): authenticated submission on 587 works, sender login ok, delivery ok.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
python3 "$SCRIPT_DIR/smtp_send.py" --server 127.0.0.1:5587 --from alice@client.test --to alice@client.test \
    --subject "E1-11 auth sub" --body "hello auth sub" --auth-user alice@client.test --auth-pass alice-pass

if wait_for_sink 1 90; then
    pass "14 (E1-08): authenticated submission delivered"
else
    fail "14 (E1-08): authenticated submission did not deliver"
fi
reset_state
