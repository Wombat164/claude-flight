#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# OPT-IN live test with a REAL but HANDICAPPED claude. Unlike the fake-pane live
# test, this drives an ACTUAL `claude --remote-control` TUI and asserts the
# watchdog detects + ACCEPTS its real trust prompt -- the exact handshake that a
# mocked/fake pane cannot exercise (and that a "=NAME" target once silently broke).
#
# Handicapped + harmless: runs in a throwaway temp dir (claude can only see that
# dir), under a unique RC name + tmux session, and is killed immediately after.
#
# Requires claude installed + AUTHENTICATED, so it is NOT a CI test (CI has no
# credentials and must not). Opt in explicitly:
#   FLIGHT_LIVE_CLAUDE=1 bin/flight-doctor.live-claude.test.sh
set -uo pipefail
[ "${FLIGHT_LIVE_CLAUDE:-0}" = 1 ] || { echo "SKIP: set FLIGHT_LIVE_CLAUDE=1 to run (spins a real claude session)"; exit 0; }
command -v tmux   >/dev/null 2>&1 || { echo "SKIP: tmux not installed";   exit 0; }
command -v claude >/dev/null 2>&1 || { echo "SKIP: claude not installed"; exit 0; }
HERE="$(cd "$(dirname "$0")" && pwd)"
WD="$(mktemp -d)"; TS="flight-livec-$$"; RC="flight-livec-$$"
pass=0; fail=0
ok(){ echo "  ok   $1"; pass=$((pass+1)); }
no(){ echo "  FAIL $1"; fail=$((fail+1)); }
cleanup(){
  tmux kill-session -t "$TS" 2>/dev/null
  for p in $(pgrep -f "claude --remote-control $RC" 2>/dev/null); do
    [ "$(ps -o comm= -p "$p" 2>/dev/null)" = claude ] && kill "$p" 2>/dev/null
  done
  rm -rf "$WD"
}
trap cleanup EXIT

echo "== real handicapped claude in throwaway $WD (RC=$RC) =="
# Launch a real claude --remote-control confined to the throwaway dir. Inference
# tokens break RC (like the launcher), so clear them. It will stop at the trust
# prompt for the fresh, untrusted folder.
tmux new-session -d -x 120 -y 40 -s "$TS" \
  "cd '$WD' && unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY && exec claude --remote-control '$RC'"

# busy-wait (bounded) for the real trust prompt to render
seen=""
for _ in $(seq 1 600); do
  tmux capture-pane -t "$TS" -p 2>/dev/null | grep -qi 'trust this folder' && { seen=1; break; }
done
[ -n "$seen" ] && ok "real claude rendered its trust prompt" || { no "no trust prompt within timeout"; echo "LIVE-CLAUDE: $pass passed, $fail failed"; exit 1; }

# Run the watchdog against the throwaway session -> it must SEE + ACCEPT the trust
# prompt (early in the if-ladder), not blow past it. FLIGHT_CONF=/dev/null keeps
# the real config (ntfy topic, real session name) out of it.
FLIGHT_CONF=/dev/null FLIGHT_SESSION="$TS" FLIGHT_RC_LABEL="$RC" FLIGHT_NTFY_URL="" \
  bash "$HERE/flight-doctor.sh" >/dev/null 2>&1 || true

# after accept, claude proceeds and the trust prompt is gone
cleared=""
for _ in $(seq 1 300); do
  tmux capture-pane -t "$TS" -p 2>/dev/null | grep -qi 'trust this folder' || { cleared=1; break; }
done
[ -n "$cleared" ] && ok "watchdog accepted the real trust prompt (cleared)" \
                  || no "watchdog did NOT clear the real trust prompt"

echo "==================================================="
echo "LIVE-CLAUDE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
