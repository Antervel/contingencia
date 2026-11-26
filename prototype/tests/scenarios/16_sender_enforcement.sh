#!/bin/sh
# Scenario 16 (ticket E1-08): sender enforcement: authenticated user may not send as another.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
if python3 "$SCRIPT_DIR/smtp_send.py" --server 127.0.0.1:5587 --from bob@client.test --to alice@client.test \
    --subject "E1-11 sender mismatch" --body "hello sender mismatch" --auth-user alice@client.test --auth-pass alice-pass >/dev/null 2>&1; then
    fail "16 (E1-08): sender mismatch accepted"
else
    pass "16 (E1-08): sender mismatch rejected"
fi
reset_state
