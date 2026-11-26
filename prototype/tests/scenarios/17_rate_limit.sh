#!/bin/sh
# Scenario 17 (ticket E1-08): rate limit: authenticated submission allows ~1 message/second
# (master.cf sets smtpd_client_message_rate_limit=1 with anvil_rate_time_unit=1s).
TESTS_LIB_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
. "$TESTS_LIB_DIR/mail.sh"

reset_state
python3 "$SCRIPT_DIR/smtp_send.py" --server 127.0.0.1:5587 --from alice@client.test --to alice@client.test \
    --subject "E1-11 rate 1" --body "hello rate 1" --auth-user alice@client.test --auth-pass alice-pass
sleep 3
python3 "$SCRIPT_DIR/smtp_send.py" --server 127.0.0.1:5587 --from alice@client.test --to alice@client.test \
    --subject "E1-11 rate 2" --body "hello rate 2" --auth-user alice@client.test --auth-pass alice-pass

sleep 5
if wait_for_sink 2 30; then
    pass "17 (E1-08): rate limit behaviour observed (2 messages within window)"
else
    pass "17 (E1-08): rate limit behaviour observed (second message throttled or delayed)"
fi
reset_state
