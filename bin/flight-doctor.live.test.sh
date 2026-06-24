#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# LIVE smoke test -- exercises flight-doctor's tmux helpers against a REAL tmux
# session (fake pane content, NO real claude). Catches tmux-target-semantics bugs
# that the mocked unit/integration suites cannot -- notably the "=NAME" exact-match
# form silently returning an EMPTY pane for capture-pane (which once blinded the
# watchdog so it could not see/accept the trust prompt). Skips cleanly when tmux
# is absent. Runs in CI (install tmux) and locally:
#   bin/flight-doctor.live.test.sh
set -uo pipefail
command -v tmux >/dev/null 2>&1 || { echo "SKIP: tmux not installed"; exit 0; }
HERE="$(cd "$(dirname "$0")" && pwd)"
TS="flight-livetest-$$"
MARK="LIVE-PANE-MARKER-$$"
pass=0; fail=0
ok(){ echo "  ok   $1"; pass=$((pass+1)); }
no(){ echo "  FAIL $1"; fail=$((fail+1)); }
cleanup(){ tmux kill-session -t "$TS" 2>/dev/null; }
trap cleanup EXIT

# Throwaway tmux session: pane prints a fake trust prompt + marker, then `cat`
# keeps it alive (and echoes anything we send-keys into it).
tmux new-session -d -x 120 -y 40 -s "$TS" \
  "printf '%s\n' '$MARK' 'Quick safety check: Is this a project you trust?' '1. Yes, I trust this folder' '2. No, exit'; exec cat" \
  || { echo "FAIL: could not start tmux test session"; exit 1; }
# busy-wait (no sleep) for the pane to render the printf output
for _ in $(seq 1 200); do [ -n "$(tmux capture-pane -t "$TS" -p 2>/dev/null | tr -d '[:space:]')" ] && break; done

# Load the real helpers in library mode, pointed at the live test session.
FLIGHT_CONF=/dev/null FLIGHT_SESSION="$TS" FLIGHT_DOCTOR_LIB=1 . "$HERE/flight-doctor.sh" >/dev/null 2>&1

echo "== live tmux helpers (real session, fake pane) =="
[ "$SESSION" = "$TS" ] && ok "SESSION resolves to the live test session" || no "SESSION=$SESSION != $TS"
tmux has-session -t "$SESSION" 2>/dev/null && ok "has-session finds the live session" || no "has-session MISS"

# THE regression guard: the code's own capture helper must return real content.
# With a "=NAME" pane target this comes back EMPTY -- the exact bug we shipped once.
out="$(pane_j)"
[ -n "$out" ] && ok "pane_j() returns live pane content (not empty)" \
              || no "pane_j() EMPTY -> tmux pane-target bug (e.g. '=$SESSION')"
printf '%s' "$out" | grep -q "$MARK"             && ok "pane content captured verbatim"        || no "marker not captured"
printf '%s' "$out" | grep -qi 'trust this folder' && ok "trust prompt is visible to detectors" || no "trust prompt not visible"

# send-keys round-trip with the SAME target form the code uses (cat echoes it back).
PING="PING-$$-$RANDOM"
tmux send-keys -t "$SESSION" "$PING" Enter 2>/dev/null
for _ in $(seq 1 200); do tmux capture-pane -t "$SESSION" -p 2>/dev/null | grep -q "$PING" && break; done
tmux capture-pane -t "$SESSION" -p 2>/dev/null | grep -q "$PING" \
  && ok "send-keys reaches the live pane" || no "send-keys did not land (target form rejected?)"

echo "==================================================="
echo "LIVE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
