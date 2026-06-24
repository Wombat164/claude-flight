#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Integration tests for flight-doctor.sh -- drives the WHOLE if-ladder (not just
# helpers) against canned pane fixtures, with stub tmux/pgrep/ps/ss/curl/kill/
# claude/sleep/flock on PATH, and asserts the DECISION (send-keys / kill / hold).
# Closes the gap the unit suite can't reach. Run with NO args.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC="$HERE/flight-doctor.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# ---- stubs (read scenario from env, record actions to $ACTIONS) --------------
S="$TMP/stubs"; mkdir -p "$S"
cat > "$S/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 0 ;;
  # Mimic real tmux: an "=NAME" exact-match prefix is INVALID as a PANE target
  # (capture-pane / send-keys) and resolves to nothing -> empty / failure. This
  # guards the lesson: re-introducing `-t "=$SESSION"` on pane ops silently blinds
  # the watchdog, and the pane-scrape scenarios below would then fail.
  capture-pane)
    case "$*" in *"-t ="*) exit 0 ;; esac
    if [ -n "${FIX_PANE_EXPANDED:-}" ] && grep -q ' C-o' "$ACTIONS" 2>/dev/null; then cat "$FIX_PANE_EXPANDED"; else cat "$FIX_PANE"; fi ;;
  send-keys)
    case "$*" in *"-t ="*) exit 1 ;; esac
    shift; echo "send-keys $*" >> "$ACTIONS" ;;
  new-session|kill-session) echo "$1 $*" >> "$ACTIONS" ;;
esac
exit 0
EOF
cat > "$S/pgrep" <<'EOF'
#!/usr/bin/env bash
printf '%s ' "$@" | grep -q 'claude --remote-control' && { [ "${FIX_PID:-4242}" = none ] || echo "${FIX_PID:-4242}"; }
exit 0
EOF
cat > "$S/ps" <<'EOF'
#!/usr/bin/env bash
a="$*"
case "$a" in
  *comm=*) echo "${FIX_COMM:-claude}" ;;
  *args=*) echo "claude --remote-control flight --settings x" ;;   # for flightpid's label anchor
  *%cpu=*) echo "${FIX_CPU:-0.0}" ;;
  *--ppid*) [ -n "${FIX_KIDS:-}" ] && echo "$FIX_KIDS" ;;
esac
exit 0
EOF
cat > "$S/ss" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${FIX_SS:-}"
exit 0
EOF
cat > "$S/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *api.anthropic.com*) printf '%s' "${FIX_CURL:-200}" ;;
  *) echo "curl $*" >> "$ACTIONS" ;;
esac
exit 0
EOF
cat > "$S/claude" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) printf '{"loggedIn": %s}\n' "${FIX_AUTH:-true}"; [ "${FIX_AUTH:-true}" = true ] && exit 0 || exit 1 ;;
  *--version*) echo "2.1.190 (Claude Code)" ;;
esac
exit 0
EOF
for c in sleep flock; do printf '#!/usr/bin/env bash\nexit 0\n' > "$S/$c"; done
chmod +x "$S"/*
# `kill` is a bash BUILTIN, so a PATH stub never intercepts it; override via an
# exported function (inherited by the `bash "$DOC"` child, where it shadows the builtin).
kill(){ echo "kill $*" >> "$ACTIONS"; }; export -f kill

# ---- scenario runner ---------------------------------------------------------
run(){ # run NAME ; uses FIX_* from caller env; sets OUT + ACTIONS file
  ACTIONS="$TMP/actions.$1"; : > "$ACTIONS"; export ACTIONS
  local st="$TMP/state.$1"; rm -rf "$st"
  OUT="$(FLIGHT_CONF=/dev/null FLIGHT_STATE_DIR="$st" FLIGHT_SETTINGS=/nonexistent \
        FLIGHT_RC_LABEL=flight FLIGHT_SESSION=flight \
        PATH="$S:$PATH" bash "$DOC" 2>&1)"
}
acted(){ grep -q "$1" "$ACTIONS" 2>/dev/null; }   # an action was recorded

# fixtures
P_IDLE="$TMP/p_idle";   printf '%s\n' "  > some output" "  ❯ " "  accept edits on" > "$P_IDLE"
P_ROUT="$TMP/p_rout";   printf '%s\n' " Bash command" "   ls /tmp" " Do you want to proceed?" " ❯ 1. Yes" "   2. No" > "$P_ROUT"
P_MUT="$TMP/p_mut";     printf '%s\n' " Bash command" "   rm -rf /" " Do you want to proceed?" " ❯ 1. Yes" "   2. No" > "$P_MUT"
P_AUTH="$TMP/p_auth";   printf '%s\n' "  Invalid API key . Please run /login" "  ❯ " > "$P_AUTH"
SS2='ESTAB 0 0 1.2.3.4:55 5.6.7.8:443 users:(("claude",pid=4242,fd=1))
ESTAB 0 0 1.2.3.4:56 5.6.7.8:443 users:(("claude",pid=4242,fd=2))'

echo "== integration: the decision if-ladder against fixtures =="

FIX_PANE="$P_IDLE" FIX_SS="$SS2" FIX_CURL=200 FIX_AUTH=true run healthy
if ! acted 'kill ' && ! acted '1 Enter'; then ok "healthy idle -> no kill / no approve"; else no "healthy idle -> unexpected action"; fi
grep -q 'flight: ALIVE' <<<"$OUT" && ok "healthy -> reports ALIVE" || no "healthy -> ALIVE missing"

FIX_PANE="$P_ROUT" FIX_SS="$SS2" FIX_CURL=200 FIX_AUTH=true run routine
acted '1 Enter' && ok "routine gate -> approved (1 Enter)" || no "routine gate -> not approved"

FIX_PANE="$P_MUT" FIX_SS="$SS2" FIX_CURL=200 FIX_AUTH=true run mutation
acted '1 Enter' && no "mutation gate -> MUST NOT approve" || ok "mutation gate -> not approved"
grep -qiE 'ACTION NEEDED|MUTATION' <<<"$OUT" && ok "mutation gate -> held for human" || no "mutation gate -> not held"

FIX_PANE="$P_AUTH" FIX_SS="$SS2" FIX_CURL=200 FIX_AUTH=false run authfail
acted 'kill ' && no "auth fail -> MUST NOT kill" || ok "auth fail -> not restarted"
grep -qiE 'NEEDS LOGIN|re-authentication' <<<"$OUT" && ok "auth fail -> held for login" || no "auth fail -> not held"

FIX_PANE="$P_IDLE" FIX_SS="" FIX_CURL=200 FIX_AUTH=true run rcdrop
acted 'kill ' && ok "RC drop (0 conns, API up) -> kill+resume" || no "RC drop -> did not restart"

FIX_PANE="$P_IDLE" FIX_SS="" FIX_CURL=000 FIX_AUTH=true run outage
acted 'kill ' && no "outage (0 conns, API down) -> MUST NOT restart" || ok "outage -> restart refused"

# collapsed gate (command hidden behind "ctrl+o to expand"): must Ctrl+O + re-read
P_COL="$TMP/p_col";     printf '%s\n' " Bash command" " ... +5 lines (ctrl+o to expand)" " Do you want to proceed?" " ❯ 1. Yes" "   2. No" > "$P_COL"
P_COL_OK="$TMP/p_col_ok"; printf '%s\n' " Bash command" "   ls /tmp" " Do you want to proceed?" " ❯ 1. Yes" "   2. No" > "$P_COL_OK"
P_COL_BAD="$TMP/p_col_bad"; printf '%s\n' " Bash command" "   rm -rf /etc" " Do you want to proceed?" " ❯ 1. Yes" "   2. No" > "$P_COL_BAD"

FIX_PANE="$P_COL" FIX_PANE_EXPANDED="$P_COL_OK" FIX_SS="$SS2" FIX_CURL=200 FIX_AUTH=true run colok
acted ' C-o' && ok "collapsed gate -> Ctrl+O sent (expand before deciding)" || no "collapsed gate -> not expanded"
acted '1 Enter' && ok "collapsed+benign -> approved after expand" || no "collapsed+benign -> not approved"

FIX_PANE="$P_COL" FIX_PANE_EXPANDED="$P_COL_BAD" FIX_SS="$SS2" FIX_CURL=200 FIX_AUTH=true run colbad
acted ' C-o' && ok "collapsed gate -> Ctrl+O sent (bad)" || no "collapsed bad -> not expanded"
acted '1 Enter' && no "collapsed-hidden rm -rf -> MUST NOT approve" || ok "collapsed-hidden rm -rf -> HELD (denylist saw it after expand)"

echo
echo "==================================================="
printf 'INTEGRATION: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
