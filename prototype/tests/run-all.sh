#!/bin/sh
# E1-11: Automated scenario test suite - single entry point.
# Usage:
#   prototype/tests/run-all.sh              # run all scenarios (01..20)
#   prototype/tests/run-all.sh --only 08   # run only scenario 08
#   prototype/tests/run-all.sh --keep      # leave the stack running after the run
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCENARIOS_DIR="$SCRIPT_DIR/scenarios"

ONLY=""
KEEP=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --only)
            shift
            ONLY="${1:-}"
            shift
            ;;
        --only=*)
            ONLY="${1#--only=}"
            shift
            ;;
        --keep)
            KEEP=1
            shift
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

FAIL=0
FAILED_NAMES=""

run_scenario() {
    n="$1"
    f="$SCENARIOS_DIR/${n}_"*.sh
    script=$(ls $SCENARIOS_DIR/${n}_*.sh 2>/dev/null | head -n1)
    if [ -z "$script" ] || [ ! -e "$script" ]; then
        echo "MISSING: no scenario script for number $n"
        FAIL=$((FAIL + 1))
        FAILED_NAMES="$FAILED_NAMES scenario-$n"
        return
    fi
    echo "--- scenario $n: $(basename "$script") ---"
    sh "$script"
    rc=$?
    if [ $rc -ne 0 ]; then
        FAIL=$((FAIL + 1))
        FAILED_NAMES="$FAILED_NAMES scenario-$n"
    fi
}

for f in $(ls "$SCENARIOS_DIR"/[0-9]*_*.sh 2>/dev/null | sort); do
    n=$(basename "$f" | sed -n 's/^\([0-9]*\)_.*/\1/p')
    if [ -n "$ONLY" ]; then
        if [ "$n" != "$ONLY" ]; then
            continue
        fi
    fi
    run_scenario "$n"
done

echo
echo "================ SCENARIO SUITE SUMMARY ================"
if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: ALL SCENARIOS PASSED"
else
    echo "RESULT: $FAIL SCENARIO(S) FAILED:"
    for x in $FAILED_NAMES; do
        echo "  - $x"
    done
fi
echo "======================================================="

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
