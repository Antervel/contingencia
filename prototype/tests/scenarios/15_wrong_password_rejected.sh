#!/bin/sh
# Scenario 15 (ticket E1-08): wrong password is rejected at SASL auth on submission.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
if python3 "$SCRIPT_DIR/smtp_send.py" --server 127.0.0.1:587 --from alice@client.test --to alice@client.test \
    --subject "E1-11 bad pass" --body "hello bad pass" --auth-user alice@client.test --auth-pass wrong-pass >/dev/null 2>&1; then
    fail "15 (E1-08): wrong password accepted"
else
    pass "15 (E1-08): wrong password rejected"
fi
reset_state
