#!/bin/sh
# Scenario 06 (ticket E1-05): visible headers of the copy: subject/body arrive intact.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
send_msg sender@sender.test alice@client.test "E1-11 headers subject" "hello headers body"

if imap_wait_ready alice@client.test alice-pass 1 30; then
    pass "06 (E1-05): copy present in alice INBOX"
else
    fail "06 (E1-05): copy missing in alice INBOX"
fi

out=$(python3 "$SCRIPT_DIR/imap_check.py" --user alice@client.test --password alice-pass --action read)
if echo "$out" | grep -q "SUBJECT:Subject: E1-11 headers subject"; then
    pass "06 (E1-05): copy headers visible (subject intact)"
else
    fail "06 (E1-05): copy headers not visible (subject mismatch)"
fi

if echo "$out" | grep -q "hello headers body"; then
    pass "06 (E1-05): copy body intact"
else
    fail "06 (E1-05): copy body not intact"
fi
