#!/bin/sh
# Scenario 20 (ticket E1-10): empty configuration: all generated tables zero bytes, Postfix
# starts and runs cleanly (empty tables accepted); user file may be empty too.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

# Empty the generated tables on the host (config volume is mounted read-only in the container).
for f in relay_domains transport virtual_mailboxes recipient_bcc relay_recipients sender_login; do
    : > "$REPO_ROOT/prototype/config/postfix/$f"
done

check1=0
$COMPOSE exec -T mta postfix check >/dev/null 2>&1 && check1=1

$COMPOSE restart mta >/dev/null 2>&1
sleep 12
check2=0
$COMPOSE exec -T mta postfix status >/dev/null 2>&1 && check2=1

# Restore the golden files.
cp "$REPO_ROOT/reference/generated/postfix/relay_domains" "$REPO_ROOT/prototype/config/postfix/relay_domains"
cp "$REPO_ROOT/reference/generated/postfix/transport" "$REPO_ROOT/prototype/config/postfix/transport"
cp "$REPO_ROOT/reference/generated/postfix/virtual_mailboxes" "$REPO_ROOT/prototype/config/postfix/virtual_mailboxes"
cp "$REPO_ROOT/reference/generated/postfix/recipient_bcc" "$REPO_ROOT/prototype/config/postfix/recipient_bcc"
cp "$REPO_ROOT/reference/generated/postfix/relay_recipients" "$REPO_ROOT/prototype/config/postfix/relay_recipients"
cp "$REPO_ROOT/reference/generated/postfix/sender_login" "$REPO_ROOT/prototype/config/postfix/sender_login"
cp "$REPO_ROOT/reference/generated/dovecot/users" "$REPO_ROOT/prototype/config/dovecot/users"
$COMPOSE exec -T mta postfix reload >/dev/null 2>&1

if [ "$check1" = "1" ]; then
    pass "20 (E1-10): postfix check passes with empty tables"
else
    fail "20 (E1-10): postfix check failed with empty tables"
fi
if [ "$check2" = "1" ]; then
    pass "20 (E1-10): postfix starts cleanly with empty tables"
else
    fail "20 (E1-10): postfix did not start cleanly with empty tables"
fi

reset_state
