#!/usr/bin/env bash
# Headless checks, no headset needed:
#   1. unit tests: rules, hit detection
#   2. a bot-vs-bot match in Single Player mode
#   3. a LAN match: host and client on this PC, found by UDP discovery, both driven by bots
# Usage: GODOT=/path/to/Godot_console.exe tests/run.sh
# (--xr-mode off matters: with OpenXR enabled and no headset, Godot can hang at startup.)
set -uo pipefail
cd "$(dirname "$0")/.."
G="${GODOT:-godot}"
RUN=("$G" --headless --xr-mode off)
FAST=(--bot-vs-bot --quit-on-end --rounds=2 --round-seconds=30 --rest-seconds=2 --timescale=4)
LOG="$(mktemp -d)"
fail=0

timeout 60 "${RUN[@]}" --import >/dev/null 2>&1

echo "== rules and hit detection"
for t in rules hits; do
  timeout 60 "${RUN[@]}" -s "res://tests/test_$t.gd" 2>&1 | grep -E "PASS|FAIL" || fail=1
done

echo "== bot vs bot"
timeout 120 "${RUN[@]}" -- --mode=bot "${FAST[@]}" > "$LOG/bot.log" 2>&1
grep MATCH_OVER "$LOG/bot.log" || fail=1

echo "== LAN host + client"
timeout 150 "${RUN[@]}" -- --mode=host "${FAST[@]}" > "$LOG/host.log" 2>&1 &
sleep 2
timeout 150 "${RUN[@]}" -- --mode=join "${FAST[@]}" > "$LOG/join.log" 2>&1
wait
h="$(grep MATCH_OVER "$LOG/host.log")"; j="$(grep MATCH_OVER "$LOG/join.log")"
echo "host:   $h"; echo "client: $j"
[[ -n "$h" && "$h" == "$j" ]] || { echo "FAIL: host and client disagree"; fail=1; }

if grep -lE "SCRIPT ERROR|^ERROR" "$LOG"/*.log; then echo "FAIL: errors above (logs in $LOG)"; fail=1; fi
[[ $fail == 0 ]] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED (logs in $LOG)"
exit $fail
