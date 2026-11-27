#!/bin/sh
# Shared stack helpers for the scenario suite (tickets E1-11, E1-13).
#
# The compose file under test is selected with COMPOSE_FILE. The default is the
# local prototype stack (compose.yaml); the CI test gate sets
# COMPOSE_FILE=compose.release.yaml so the suite drives exactly the release
# stack it started from the freshly built images.
#
# All compose commands used by the suite go through $COMPOSE, so the stack the
# suite inspects is always the stack it started.

STACK_LIB_DIR="${TESTS_LIB_DIR:-$(cd "$(dirname "$0")" && pwd)}"
STACK_REPO_ROOT=$(cd "$STACK_LIB_DIR/../../.." && pwd)

COMPOSE_FILE="${COMPOSE_FILE:-compose.yaml}"
case "$COMPOSE_FILE" in
    /*) ;;
    *) COMPOSE_FILE="$STACK_REPO_ROOT/$COMPOSE_FILE" ;;
esac
COMPOSE="docker compose -f $COMPOSE_FILE"

ensure_services() {
    # Bring every service back to the running state. Scenarios stop `main` or
    # `mta` on purpose, and a failed assertion exits before the scenario can
    # restore them; without this, one failure cascades into every later
    # scenario that needs the stopped service.
    $COMPOSE start >/dev/null 2>&1 || true

    # Wait until the sink API answers: the next scenario may send mail at once.
    i=0
    while [ "$i" -lt 30 ]; do
        if sh "$STACK_LIB_DIR/sink.sh" count >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
}
