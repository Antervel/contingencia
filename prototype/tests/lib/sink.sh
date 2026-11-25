#!/bin/sh
# Fake SMTP sink (Mailpit) test helper — prototype helper for Epic 1 (ticket E1-02).
# Reused by the automated scenario script of ticket E1-11.
#
# Operations:
#   sink.sh count        print how many messages the sink currently holds
#   sink.sh clear        delete all messages the sink holds
#   sink.sh raw <N>      print the raw source of message number N (1 = newest)
#
# The Mailpit REST API is expected on $MP_API (default http://127.0.0.1:8025).

MP_API="${MP_API:-http://127.0.0.1:8025}"

sink_count() {
    curl -sf "$MP_API/api/v1/messages" \
        | tr -d '\n' \
        | grep -o '"messages_count":[0-9]*' \
        | head -n 1 \
        | cut -d: -f2
}

sink_clear() {
    # An empty delete body deletes all messages.
    curl -sf -X DELETE "$MP_API/api/v1/messages" > /dev/null
}

sink_raw() {
    n="${1:-1}"
    # Messages are listed newest first; number them from 1.
    id="$(curl -sf "$MP_API/api/v1/messages?limit=500" \
        | grep -o '"ID":"[^"]*"' \
        | sed -n "${n}p" \
        | cut -d'"' -f4)"
    curl -sf "$MP_API/api/v1/message/${id}/raw"
}

case "${1:-}" in
    count)
        echo "$(sink_count)"
        ;;
    clear)
        sink_clear
        ;;
    raw)
        shift
        sink_raw "$@"
        ;;
    *)
        echo "usage: $0 {count|clear|raw <N>}" >&2
        exit 2
        ;;
esac
