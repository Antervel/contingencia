#!/bin/sh
# Scenario 19 (ticket E1-09): reload table verification commands: lookups against the
# running Postfix after `postfix reload`.
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

$COMPOSE exec -T mta postfix reload >/dev/null 2>&1

out=$($COMPOSE exec -T mta postmap -q alice@client.test texthash:/config/postfix/recipient_bcc 2>/dev/null)
if [ "$out" = "alice@copies.invalid" ]; then
    pass "19 (E1-09): recipient_bcc lookup after reload returns internal address"
else
    fail "19 (E1-09): recipient_bcc lookup after reload unexpected: $out"
fi

out=$($COMPOSE exec -T mta postmap -q client.test texthash:/config/postfix/transport 2>/dev/null)
if [ "${out:-}" = "relay:[main]:1025" ]; then
    pass "19 (E1-09): transport lookup after reload returns sink route"
else
    fail "19 (E1-09): transport lookup after reload unexpected: ${out:-none}"
fi
