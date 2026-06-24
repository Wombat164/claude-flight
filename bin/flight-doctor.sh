#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# flight-doctor -- one-shot "fix my flight session". Run with NO args.
# Does, in order: ensure alive -> accept trust prompt -> heal harmless gates ->
# report a waiting MUTATION gate -> recover a WEDGED "Waiting..." tool call
# (kill+resume) -> bust a STALLED spinner (Escape, then kill+resume if needed)
# -> detect a silently-DROPPED Remote Control channel (process alive but the
# websocket died on idle) via the socket table and kill+resume it
# -> print status + app URL. All recovery is lossless (resume-pin).
#
# Usage:
#   flight-doctor                 # diagnose + auto-fix everything safe, then report
#   flight-doctor --status        # read-only: report state, change nothing
#   flight-doctor --selftest      # read-only drift canary: health + TUI-drift checks
# Configuration -- all site-specific values come from env vars or an optional
# config file (see flight-doctor.conf.example); the defaults below are generic
# so this script is publishable as-is. Tunables (env or config file):
#   FLIGHT_SESSION (default flight)          tmux session name (local target)
#   FLIGHT_RC_LABEL / FLIGHT_HOST            remote-control name in the Claude Code
#                                            web/desktop UI (default <session>-<host>-<user>)
#   FLIGHT_LAUNCHER                          respawn launcher
#   FLIGHT_NTFY_URL                          ntfy topic for alerts (empty = off)
#   FLIGHT_CONF                              config path override (/dev/null = none)
#   FLIGHT_STALL_SECS      (default 180)     spinner age before it counts stalled
#   FLIGHT_LOG / _MAX_BYTES / _KEEP_LINES    event log path + rotation bounds
#   FLIGHT_HEARTBEAT_SECS  (default 3600)    min gap between "all healthy" lines
#   FLIGHT_ALERT_COOLDOWN_SECS (default 1800) per-key alert rate limit
#   FLIGHT_FLAP_MAX / _WINDOW  (3 / 1800)    restart-loop circuit breaker
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# Source an optional site config before applying defaults (first readable wins).
# Set FLIGHT_CONF=/dev/null to skip it (the test harness does this).
for _c in "${FLIGHT_CONF:-}" "$HOME/.config/flight-doctor.conf" "/etc/flight-doctor.conf"; do
  # shellcheck source=/dev/null
  [ -n "$_c" ] && [ -r "$_c" ] && { . "$_c"; break; }
done
SESSION="${FLIGHT_SESSION:-${RC_NAME:-flight}}"   # tmux session name (local target); RC_NAME honored for back-compat
# tmux target GOTCHA (learned the hard way): use the PLAIN session name for pane
# ops (capture-pane / send-keys / display-message). The exact-match form "=NAME"
# is valid for `has-session` but resolves to NOTHING as a pane target, so
# capture-pane silently returns an empty pane -> the watchdog goes BLIND (can't
# see or accept the trust prompt / gates, so the session sticks unprimed and never
# registers as an available RC session). Never prefix a pane target with "=".
FLIGHT_HOST="${FLIGHT_HOST:-$(hostname -s 2>/dev/null || hostname)}"
# The `claude --remote-control` name shown in the Claude Code web/desktop session
# list -- host/user-aware so deployments on different boxes are distinguishable.
# Defaults to <session>-<host>-<user>; override the whole label with
# FLIGHT_RC_LABEL, or just the host component with FLIGHT_HOST.
RC_LABEL="${FLIGHT_RC_LABEL:-${SESSION}-${FLIGHT_HOST}-$(id -un)}"
FLIGHT_ID="$RC_LABEL"   # alerts/status identity == the RC name (host+user aware)
LAUNCHER="${FLIGHT_LAUNCHER:-$HOME/.local/bin/flight-claude.sh}"
STALL_SECS="${FLIGHT_STALL_SECS:-180}"
STATE_DIR="${FLIGHT_STATE_DIR:-$HOME/.local/state/flight}"
HOOK_DIR="$STATE_DIR/hooks"   # where the hook receiver (flight-notify.sh) writes sentinels
LOG="${FLIGHT_LOG:-$STATE_DIR/flight-doctor.log}"
HB_FILE="$STATE_DIR/doctor.heartbeat"
LOG_MAX_BYTES="${FLIGHT_LOG_MAX_BYTES:-262144}"
LOG_KEEP_LINES="${FLIGHT_LOG_KEEP_LINES:-2000}"
HEARTBEAT_SECS="${FLIGHT_HEARTBEAT_SECS:-3600}"
# ntfy alerting for CRITICAL events only. Empty by default -> alerts disabled
# until a topic is set via FLIGHT_NTFY_URL (env or config file).
ALERT_URL="${FLIGHT_NTFY_URL:-${NTFY_URL:-}}"
ALERT_COOLDOWN_SECS="${FLIGHT_ALERT_COOLDOWN_SECS:-1800}"
FLAP_MAX="${FLIGHT_FLAP_MAX:-3}"          # max kill+resumes within the window...
FLAP_WINDOW="${FLIGHT_FLAP_WINDOW:-1800}" # ...before the circuit breaker trips
# Claude Code CLI version this was last validated against. Detection keys off the
# CLI's behavior + (undocumented) TUI strings, so a release can change them --
# bump this after re-validating on upgrade. The MODEL is irrelevant: the watchdog
# operates below the model layer and never inspects which model the session runs.
# shellcheck disable=SC2034  # consumed by the planned --selftest drift canary
TESTED_CC_VERSION="2.1.190"
# --- portability shims: Linux/GNU is the primary target; these keep macOS working
# WITHOUT changing the Linux path (the GNU/ss/flock branch is identical to before,
# so Linux behaviour cannot regress). ---
case "$(uname -s 2>/dev/null)" in Darwin) IS_MAC=1 ;; *) IS_MAC=0 ;; esac
# file mtime as epoch seconds: GNU `stat -c %Y`, BSD (macOS) `stat -f %m` fallback.
_mtime(){ stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
# CATASTROPHIC-ONLY hold-list (user policy: routine yes, catastrophic no).
# Everything NOT matching here is auto-approved (builds, render, podman run,
# sudo rm of /tmp, kubectl get/delete pod, file writes, etc). Only the
# irreversible/system-or-cluster-destroying ops below are held for a human.
# Built in classes so it stays readable; matched against a WRAP-JOINED pane
# (pane_j) so a long command cannot evade a token by splitting across rows.
# General rm -rf under /home/* is still auto-approved EXCEPT the load-bearing
# dirs below (repos / .ssh / .claude / .config / .local). Writes to any
# protected paths are additionally subject to whatever write-guard hooks you add.
# Regex-escape the running user's $HOME so the load-bearing-home rule works
# wherever home actually lives (Linux /home, macOS /Users, or a non-standard
# path), not just /home. Generic /home/<any> and /Users/<any> are kept as
# fallbacks to also guard OTHER users' homes.
HOME_RE="$(printf '%s' "$HOME" | sed 's/[^a-zA-Z0-9_/-]/\\&/g')"
MUTATION_RE=''
MUTATION_RE+='rm([[:space:]]+-[^[:space:]]+)*[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*|--recursive)([[:space:]]+-[^[:space:]]+)*[[:space:]]+(/([[:space:])*]|$)|/(etc|var|usr|bin|sbin|lib|lib64|boot|root|opt|srv|dev|proc|sys|run)([/[:space:])*]|$))'  # recursive rm of a system root (flag-order/EOL tolerant; quotes stripped at match)
MUTATION_RE+="|rm([[:space:]]+-[^[:space:]]+)*[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*|--recursive)([[:space:]]+-[^[:space:]]+)*[[:space:]]+(${HOME_RE}|~|/home/[^/ ]+|/Users/[^/ ]+)/(repos|\\.ssh|\\.claude|\\.config|\\.local)"  # recursive rm of load-bearing home dirs (real HOME + /home,/Users fallbacks)
MUTATION_RE+="|rm([[:space:]]+-[^[:space:]]+)*[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*|--recursive)([[:space:]]+-[^[:space:]]+)*[[:space:]]+(~|\\\$HOME|\\\$\\{HOME\\}|${HOME_RE})/?([[:space:])*]|\$)"  # rm -rf of the WHOLE home (~, \$HOME, \${HOME}, or real HOME) -- Auto Mode hard-deny
MUTATION_RE+='|k3s[ -](uninstall|killall)|kubeadm[[:space:]]+reset|cilium[[:space:]]+uninstall'                            # cluster teardown
MUTATION_RE+='|kubectl[[:space:]]+delete[[:space:]]+(namespace|ns|node|pv|pvc|persistentvolume)|helm[[:space:]]+(uninstall|delete)'  # k8s object destruction
MUTATION_RE+='|\breboot\b|\bshutdown\b|\bpoweroff\b|\bhalt\b'                                                              # host power
MUTATION_RE+='|\bmkfs|\bwipefs|\bsgdisk|\bparted\b|\bfdisk\b|\bshred\b|\bdd[[:space:]]+(if=|[^|]*of=/dev/)'                 # disk / filesystem
MUTATION_RE+='|ufw[[:space:]]+(reset|disable)|iptables[[:space:]]+-F|nft[[:space:]]+flush|ip[[:space:]]+link[[:space:]]+set[^|]*down'  # network lockout
MUTATION_RE+='|(hcloud|aws|gcloud|doctl|az|hetzner)[^|]*(delete|destroy|terminate|rebuild)'                                # cloud infra destruction
MUTATION_RE+='|(podman|docker)[[:space:]]+(system|volume)[[:space:]]+prune'                                                # mass container/volume prune
MUTATION_RE+='|chmod[[:space:]]+-[a-zA-Z]*R[^|]*[[:space:]]/|chown[[:space:]]+-[a-zA-Z]*R[^|]*[[:space:]]/'                 # recursive perms from root
MUTATION_RE+='|git[[:space:]]+reset[[:space:]]+--hard|git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f|\bgit[[:space:]]+push|\bbw[[:space:]]+delete'  # data-loss git / secrets
MUTATION_RE+='|git[[:space:]]+checkout[[:space:]]+(--[[:space:]]+)?\.|git[[:space:]]+restore[[:space:]]+\.|git[[:space:]]+stash[[:space:]]+(drop|clear)|git[[:space:]]+commit[[:space:]]+[^|]*--amend'  # more data-loss git (Auto Mode block list)
MUTATION_RE+='|(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh'                                                    # pipe-to-shell remote exec
MUTATION_RE+='|(tofu|terraform)[[:space:]]+destroy|ansible[^|]*(destroy|reset|wipe)'                                       # IaC destroy
MUTATION_RE+='|apt[a-z-]*[[:space:]]+purge|snap[[:space:]]+remove'                                                         # package purge
# Extend the catastrophic denylist WITHOUT editing this script -- the built-ins
# above are curated defaults; yours will differ. Both sources are OR'd in:
#   FLIGHT_MUTATION_EXTRA  -- a single ERE of |-separated alternatives (env/config)
#   FLIGHT_DENYLIST_FILE   -- a file (default ~/.config/flight-denylist), one ERE
#                             per line; blank lines and # comments ignored.
[ -n "${FLIGHT_MUTATION_EXTRA:-}" ] && MUTATION_RE+="|${FLIGHT_MUTATION_EXTRA}"
_dl="${FLIGHT_DENYLIST_FILE:-$HOME/.config/flight-denylist}"
if [ -r "$_dl" ]; then
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in ''|'#'*|[[:space:]]*'#'*) continue;; esac
    _line="${_line#"${_line%%[![:space:]]*}"}"   # strip leading whitespace
    MUTATION_RE+="|$_line"
  done < "$_dl"
fi
# spinner time annotation, e.g.  "...… (9m 15s · ↓ 15.9k tokens)"
SPIN_RE='…[[:space:]]*\(([0-9]+m[[:space:]]*)?[0-9]+s'
# ANY approval gate (Bash "Do you want to proceed?", Edit/Write "create X?",
# "make this edit?", etc) shows the highlighted "1. Yes" menu cursor. Match that
# rather than the per-tool question text, so all gate types are handled.
GATE_RE='(❯|>)[[:space:]]*1\.[[:space:]]+Yes'
# Two-signal corroboration for AUTO-APPROVE (claude-yolo lesson): a real,
# approve-able gate has the cursor AND a "2. No" option or a permission/tool
# keyword. Requiring a second signal stops a stray "1. Yes" in tool output or a
# document from triggering a false approval. (The catastrophic HOLD path stays
# broad -- it fires on the gate sentinel OR GATE_RE, since holding is always safe.)
GATE_NO_RE='(❯|>|[[:space:]])[[:space:]]*2\.[[:space:]]+No'
GATE_KW_RE='want to proceed|wants to (run|execute|create|edit|make)|permission|allow once|Do you want|make this edit'
# Claude Code collapses long content behind "(ctrl+o to expand)". NEVER auto-approve
# while a gate's content is collapsed -- the denylist would be blind to a command
# hidden in the collapsed region. Expand (Ctrl+O) and re-read before deciding.
COLLAPSE_RE='ctrl\+o to expand'
# Login / auth / billing failures that a RESTART CANNOT FIX -- hold for a human
# instead of kill+resume thrash. Kept tight to Claude Code's own UI strings so a
# session legitimately working on auth-related code does not trip it.
AUTH_RE='Please run /login|/login to (continue|authenticate)|Invalid API key[^|]*/login|OAuth token (has )?expired|Credit balance is too low|authentication (token|credentials)[^.]*expired'
RO="${1:-}"
HEALED=0

say(){ printf '%s\n' "$*"; }
pane(){ tmux capture-pane -t "$SESSION" -p 2>/dev/null; }
# Pane capture with wrapped lines JOINED (-J). A command wider than the pane
# otherwise splits across rows and a dangerous token can straddle the wrap,
# evading MUTATION_RE/AUTH_RE. Use this -- NOT pane() -- for any SECURITY match.
# (Kept separate from pane() so the stall "frozen frame" diff is unaffected.)
pane_j(){ tmux capture-pane -t "$SESSION" -p -J 2>/dev/null; }
# Wrap-joined pane with quotes stripped -- for the catastrophic match, so a
# quoted target (rm -rf "/etc") cannot evade the denylist.
pane_cmd(){ pane_j | tr -d "\"'"; }
# Resolve the flight claude pid. Anchored to the FULL invocation AND filtered by
# comm=claude, so a stray process whose cmdline merely contains the pattern (an
# editor, a grep, this very script) can never be selected and killed.
# Resolve OUR claude pid by the remote-control label, then confirm comm==claude.
# The comm filter is load-bearing: NEVER kill by `pkill -f "<label>"` -- that
# pattern also matches the watchdog's (or any shell's) OWN command line containing
# the label, so a pattern-kill can take out the killer itself. Always kill by the
# pid this returns (lesson learned: a self-matching pkill killed the operator's shell).
flightpid(){
  local pid args
  for pid in $(pgrep -f "claude --remote-control $RC_LABEL" 2>/dev/null); do
    # comm is "claude" on Linux, "node" / a full path on macOS -- accept either, reject shells.
    case "$(basename "$(ps -o comm= -p "$pid" 2>/dev/null)" 2>/dev/null)" in claude|node) : ;; *) continue ;; esac
    # pgrep -f is a SUBSTRING match, so RC_LABEL=flight also matches a
    # flight-web01-deploy cmdline. Anchor to a COMPLETE token: the label must be
    # followed by a space (the next arg) or be the exact end of the command line.
    args="$(ps -o args= -p "$pid" 2>/dev/null)"
    case "$args" in
      *"--remote-control $RC_LABEL "*|*"--remote-control $RC_LABEL") echo "$pid"; return ;;
    esac
  done
}
# spinner elapsed in seconds, or nothing if no spinner is running
spinner_elapsed(){
  local t mins secs
  t="$(pane | grep -oE "$SPIN_RE" | head -1)" || true
  [ -z "$t" ] && return 0
  mins="$(grep -oE '[0-9]+m' <<<"$t" | head -1 | tr -d 'm')"; mins="${mins:-0}"
  secs="$(grep -oE '[0-9]+s' <<<"$t" | head -1 | tr -d 's')"; secs="${secs:-0}"
  echo $((mins*60+secs))
}
# pane with the animated spinner line + bottom hint stripped -> the real content
content_sig(){ pane | grep -vE "$SPIN_RE|esc to interrupt"; }
kids_of(){ ps --ppid "$1" -o pid= 2>/dev/null | grep -c .; }

# Is the Anthropic API reachable at all? Any HTTP status (even 401/405) proves
# reachability; only a timeout / connection failure (code 000) means an outage
# or lost egress. Lets the healers avoid futile kill+resume thrash when the
# fault is upstream rather than in the session. No curl -> assume reachable.
# ---- hook sentinels (optional, sentinel-first detection) --------------------
# The hook receiver (hooks/flight-notify.sh, wired via FLIGHT_SETTINGS) writes
# atomic sentinel files from Claude Code's lifecycle events -- STRUCTURED truth,
# immune to TUI restyling and pane-content injection. Consumers degrade
# gracefully: with the hook layer off the files are absent and flight-doctor
# falls back to pane-scraping, so this is purely ADDITIVE.
sentinel_fresh(){ # sentinel_fresh NAME MAXAGE_SECS  -> true if file exists & newer
  local f="$HOOK_DIR/$1"; [ -f "$f" ] || return 1
  local now mt; now="$(date +%s)"; mt="$(_mtime "$f")"
  [ $(( now - ${mt:-0} )) -le "$2" ]
}
# Classify a fresh StopFailure sentinel: auth | outage | "" (none/stale). The
# receiver records `error` + `last_assistant_message`; auth/billing failures need
# a human (hold), server/overload errors are an outage (hold, do not restart).
apifail_kind(){
  sentinel_fresh apifail "${FLIGHT_APIFAIL_TTL:-120}" || { echo ""; return; }
  if grep -qiE 'auth|login|credential|api[_ -]?key|oauth|forbidden|401|403|credit|billing|balance' "$HOOK_DIR/apifail" 2>/dev/null
  then echo auth; else echo outage; fi
}
# A permission gate is waiting -- by the Notification(permission_prompt) hook
# sentinel (deterministic) OR the pane GATE_RE glyph (fallback). Sentinel-first
# makes gate detection robust to a TUI restyle of the menu cursor.
gate_pending(){ sentinel_fresh gate.pending "${FLIGHT_GATE_TTL:-120}"; }
# A CONFIRMED, approve-able gate: the cursor AND a second signal (a No option or a
# permission/tool keyword), OR the deterministic hook sentinel. Used for the
# auto-APPROVE decision so a bare "1. Yes" in content can't trigger one.
gate_confirmed(){ # gate_confirmed "$pane"
  gate_pending && return 0
  grep -qE "$GATE_RE" <<<"$1" && { grep -qE "$GATE_NO_RE" <<<"$1" || grep -qiE "$GATE_KW_RE" <<<"$1"; }
}
# The spinner's token-count annotation as a plain integer ("... 15.9k tokens" ->
# 15900). A climbing count means the turn is PROGRESSING even when the visible
# content is frozen (a long in-process API generation) -- used to avoid busting a
# healthy long turn as if it were stalled.
spinner_tokens(){
  local t; t="$(pane | grep -oiE '[0-9]+(\.[0-9]+)?[[:space:]]*[km]?[[:space:]]*tokens' | head -1)" || true
  [ -z "$t" ] && { echo 0; return; }
  local nu num unit
  nu="$(grep -oiE '[0-9]+(\.[0-9]+)?[km]?' <<<"$t" | head -1)"   # number + its OWN suffix (not the k in "tokens")
  num="$(grep -oE '[0-9]+(\.[0-9]+)?' <<<"$nu" | head -1)"
  unit="$(grep -oiE '[km]$' <<<"$nu")"
  awk -v n="${num:-0}" -v u="$unit" 'BEGIN{m=1; if(tolower(u)=="k")m=1000; if(tolower(u)=="m")m=1000000; printf "%d", n*m}'
}
anthropic_up(){
  [ "$(apifail_kind)" = outage ] && return 1   # authoritative StopFailure sentinel: API is failing
  command -v curl >/dev/null 2>&1 || return 0
  local code
  code="$(curl -sS -o /dev/null -m 8 -w '%{http_code}' https://api.anthropic.com/v1/messages 2>/dev/null)" || true
  [ -n "$code" ] && [ "$code" != "000" ]
}
# Authoritative auth check: `claude auth status --json` -> exit 0 + loggedIn:true.
# Used to CORROBORATE the AUTH_RE pane match so injected terminal content that
# merely contains "/login" cannot trigger a false auth-hold (a watchdog DoS). No
# claude binary -> assume ok (don't block); timeout guarded for portability.
auth_ok(){
  command -v claude >/dev/null 2>&1 || return 0
  local to=(); command -v timeout >/dev/null 2>&1 && to=(timeout 15)
  local out rc
  out="$("${to[@]}" claude auth status --json 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] && grep -q '"loggedIn"[[:space:]]*:[[:space:]]*true' <<<"$out"
}
# Count of live outbound TLS (:443) connections the flight process holds. A
# healthy Remote Control session keeps a persistent websocket to Anthropic; when
# the channel silently drops after long idle (process still alive) this falls to
# 0. More reliable than grepping the "/rc active" footer, which is hidden during
# generation/gates. Non-sudo ss sees our own (same-user) sockets.
rc_conns(){
  local P="${1:-$(flightpid)}"
  [ -z "$P" ] && { echo 0; return; }
  if [ "$IS_MAC" = 1 ]; then
    # macOS has no `ss`; lsof lists ESTABLISHED TCP conns for the pid -> count dest :443.
    lsof -nP -p "$P" -iTCP -sTCP:ESTABLISHED 2>/dev/null \
      | grep -E '\->.*:443([^0-9]|\)|$)' | grep -vc '127\.0\.0\.1'
  else
    ss -tnHp state established 2>/dev/null | grep -F "pid=$P," \
      | grep -E ':443([^0-9]|$)' | grep -vc '127\.0\.0\.1'
  fi
}
# Lossless restart: re-exec claude via the resume-pin (same conversation, fresh
# RC channel + URL). Guarded by an outage probe so we never thrash when Anthropic
# itself is down. Sets HEALED so later sections skip a just-restarted process.
kill_resume(){ # kill_resume [reason]
  local reason="${1:-unspecified}"
  if ! anthropic_up; then
    logev ERROR outage_hold "restart skipped (reason=$reason): Anthropic API unreachable"
    alert outage high "flight: Anthropic unreachable" "Anthropic API is unreachable from this host; flight auto-restart is paused until it recovers."
    say ">>> Anthropic API UNREACHABLE (outage or lost egress) -> NOT restarting"
    say ">>> (kill+resume would just thrash). Will recheck next ~60s cycle."
    return 1
  fi
  # Circuit breaker: if we have already restarted FLAP_MAX times within
  # FLAP_WINDOW, the channel is flapping (or claude is crash-looping). Stop
  # thrashing -- escalate to a human instead of restarting forever.
  local ff="$STATE_DIR/restarts" now cutoff n
  now="$(date +%s)"; cutoff=$(( now - FLAP_WINDOW ))
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  [ -f "$ff" ] && { awk -v c="$cutoff" '$1>=c' "$ff" > "$ff.tmp" 2>/dev/null && mv "$ff.tmp" "$ff"; }
  n=0; [ -f "$ff" ] && n="$(wc -l < "$ff" 2>/dev/null)"; n="${n//[^0-9]/}"; n="${n:-0}"
  if [ "$n" -ge "$FLAP_MAX" ]; then
    logev ERROR flap "restart suppressed: $n restarts within ${FLAP_WINDOW}s (flapping)"
    alert flap high "flight: restart loop" "flight restarted $n times in $((FLAP_WINDOW/60))min (flapping). Auto-restart paused; needs a human."
    say ">>> FLAPPING: $n restarts in ${FLAP_WINDOW}s -> auto-restart paused, escalating."
    return 1
  fi
  echo "$now" >> "$ff" 2>/dev/null || true
  local P; P="$(flightpid)"
  logev WARN kill_resume "restarting (reason=$reason, oldpid=${P:-none})"
  [ -n "$P" ] && kill -TERM "$P"
  sleep 12
  # Only answer the trust-folder prompt that --resume shows. Do NOT blind-press a
  # gate: a resumed frame can re-render a (possibly catastrophic) permission menu,
  # and pressing 1 would auto-approve it WITHOUT consulting the denylist. Anything
  # else is left for the next cycle's settle/hold logic (which runs MUTATION_RE).
  if grep -q "trust this folder" <<<"$(pane)"; then
    tmux send-keys -t "$SESSION" '1' Enter
  fi
  sleep 8; HEALED=1
  logev INFO kill_resume "restart complete (newpid=$(flightpid))"
}

# ---- event log + lifecycle --------------------------------------------------
# One line per noteworthy event, e.g.:
#   2026-06-24T07:40:11Z WARN  rc_drop        0 conns; kill+resume
# Routine healthy runs do NOT spam the log: a heartbeat is written at most once
# per FLIGHT_HEARTBEAT_SECS. journald keeps the raw per-run stdout; THIS file is
# the durable, rotated event trail. All writers no-op under --status (read-only).
ts(){ date -u +%FT%TZ; }
logev(){ # logev LEVEL EVENT [msg...]
  [ "${RO:-}" = "--status" ] && return 0
  local lvl="$1" ev="$2"; shift 2 || true
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  printf '%s %-5s %-14s %s\n' "$(ts)" "$lvl" "$ev" "$*" >> "$LOG" 2>/dev/null || true
}
# Size-based retention -- disk may be tight. Past LOG_MAX_BYTES, keep only
# the last LOG_KEEP_LINES lines (atomic via tmp + mv).
log_rotate(){
  [ "${RO:-}" = "--status" ] && return 0
  [ -f "$LOG" ] || return 0
  local bytes; bytes="$(wc -c <"$LOG" 2>/dev/null || echo 0)"
  if [ "${bytes:-0}" -gt "$LOG_MAX_BYTES" ]; then
    tail -n "$LOG_KEEP_LINES" "$LOG" > "$LOG.tmp" 2>/dev/null \
      && mv "$LOG.tmp" "$LOG" \
      && logev INFO log_rotate "trimmed to last $LOG_KEEP_LINES lines (was ${bytes}B)"
  fi
}
# Rate-limited "still healthy" heartbeat: at most once per HEARTBEAT_SECS, so a
# quiet day leaves a trail without 1440 identical lines.
maybe_heartbeat(){ # maybe_heartbeat "rc=active pid=123"
  [ "${RO:-}" = "--status" ] && return 0
  local now last; now="$(date +%s)"; last="$(cat "$HB_FILE" 2>/dev/null || echo 0)"
  if [ $(( now - ${last:-0} )) -ge "$HEARTBEAT_SECS" ]; then
    logev INFO heartbeat "$*"; echo "$now" > "$HB_FILE" 2>/dev/null || true
  fi
}
# Critical-only phone alert via ntfy. Rate-limited per KEY (cooldown file) so a
# sustained outage or a long-unanswered gate does not spam every 60s. Bodies are
# kept GENERIC -- no session URL / tokens / pane dumps, because the ntfy topic is
# shared and unauthenticated. No-op under --status, without curl, or FLIGHT_ALERT=0.
alert(){ # alert KEY PRIORITY TITLE BODY
  [ "${RO:-}" = "--status" ] && return 0
  [ "${FLIGHT_ALERT:-1}" = 0 ] && return 0
  [ -z "$ALERT_URL" ] && return 0   # no topic configured -> alerts disabled
  command -v curl >/dev/null 2>&1 || return 0
  local key="$1" prio="$2" title="$3" body="$4"
  local cf="$STATE_DIR/alert.$key" now last
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  now="$(date +%s)"; last="$(cat "$cf" 2>/dev/null || echo 0)"
  [ $(( now - ${last:-0} )) -lt "$ALERT_COOLDOWN_SECS" ] && return 0
  # optional one-tap deep-link: FLIGHT_ALERT_CLICK becomes the ntfy Click action.
  # Point it at an AUTH-GATED, OUT-OF-BAND terminal (Teleport / ttyd / Cockpit /
  # SSH-web) -- NOT the claude.ai session URL, for two reasons: (1) alerts often
  # fire BECAUSE Remote Control is the broken thing, so a link to a dead RC session
  # is useless, whereas the out-of-band path still reaches the tmux session;
  # (2) the session URL is a bearer credential and the ntfy topic is shared/unauthed.
  local click=(); [ -n "${FLIGHT_ALERT_CLICK:-}" ] && click=(-H "Click: $FLIGHT_ALERT_CLICK")
  if curl -sf --max-time 10 -H "Title: [$FLIGHT_ID] $title" -H "Priority: $prio" \
       -H "Tags: airplane" "${click[@]}" -d "$body" "$ALERT_URL" >/dev/null 2>&1; then
    echo "$now" > "$cf" 2>/dev/null || true; logev INFO alert "ntfy sent key=$key prio=$prio"
  else
    logev WARN alert "ntfy POST failed key=$key"
  fi
}

# Drift canary + health check (read-only): `flight-doctor --selftest`. Detects the
# silent-breakage modes a watchdog can't otherwise notice -- a Claude Code upgrade
# that moved the TUI strings (version drift + a regex self-test against known
# fixtures), hooks that stopped firing (stale session.alive), a lost auth, a
# missing resume-pin, runaway state-dir growth. Exit 0 HEALTHY / 1 WARNING / 2 CRITICAL.
selftest(){
  local warn=0 crit=0
  chk(){ case "$1" in WARN) warn=1;; FAIL) crit=1;; esac; printf '  [%-4s] %s\n' "$1" "$2"; }
  say "flight-doctor --selftest [$FLIGHT_ID] (tested against Claude Code $TESTED_CC_VERSION):"
  tmux has-session -t "$SESSION" 2>/dev/null && chk OK "tmux session '$SESSION' present" || chk FAIL "tmux session '$SESSION' MISSING"
  np="$(tmux list-panes -t "$SESSION" 2>/dev/null | wc -l)"
  [ "${np:-1}" -le 1 ] && chk OK "single pane (targeted unambiguously)" \
    || chk WARN "$np panes in '$SESSION' -> ops hit the ACTIVE pane; keep claude's pane active/unsplit"
  local P; P="$(flightpid)"
  [ -n "$P" ] && chk OK "claude pid $P (comm-filtered)" || chk WARN "no 'claude --remote-control $RC_LABEL' pid"
  [ -s "$HOME/.local/state/flight-resume" ] && chk OK "resume-pin present" || chk WARN "resume-pin missing/empty (restarts not lossless)"
  local v; v="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -z "$v" ]; then chk WARN "claude --version unreadable"
  elif [ "$v" = "$TESTED_CC_VERSION" ]; then chk OK "Claude Code $v == tested"
  else chk WARN "Claude Code $v != tested $TESTED_CC_VERSION -> re-validate TUI detection"; fi
  local rf=0
  grep -qE  "$GATE_RE"     <<<"  > 1. Yes"          || { rf=1; chk FAIL "GATE_RE stopped matching a known gate"; }
  grep -qiE "$MUTATION_RE" <<<"rm -rf /"            || { rf=1; chk FAIL "MUTATION_RE stopped holding 'rm -rf /'"; }
  grep -qiE "$AUTH_RE"     <<<"Please run /login"   || { rf=1; chk FAIL "AUTH_RE stopped matching '/login'"; }
  [ "$rf" = 0 ] && chk OK "detector regexes match known fixtures"
  if auth_ok; then chk OK "claude auth status: logged in"; else chk WARN "claude auth status: NOT logged in"; fi
  if [ -r "${FLIGHT_SETTINGS:-$HOME/.config/flight-hooks.json}" ]; then
    [ -f "$HOOK_DIR/session.alive" ] && chk OK "hook layer active (session.alive present)" \
      || chk WARN "hooks configured but no session.alive sentinel -> hooks not firing (DRIFT)"
  else chk OK "hook layer not configured (pane-scrape mode)"; fi
  local kb; kb="$(du -sk "$STATE_DIR" 2>/dev/null | cut -f1)"; kb="${kb:-0}"
  [ "$kb" -gt 5120 ] && chk WARN "state dir ${kb}KB > 5MB" || chk OK "state dir ${kb}KB"
  if [ "$crit" = 1 ]; then say "RESULT: CRITICAL"; return 2
  elif [ "$warn" = 1 ]; then say "RESULT: WARNING"; return 1
  else say "RESULT: HEALTHY"; return 0; fi
}

# Library mode: let the test harness source the helpers/vars above without
# running the doctor.  FLIGHT_DOCTOR_LIB=1 source flight-doctor.sh
[ "${FLIGHT_DOCTOR_LIB:-0}" = 1 ] && return 0 2>/dev/null

# Drift canary dispatch (read-only; before the flock so it never blocks a heal).
if [ "$RO" = "--selftest" ]; then selftest; exit $?; fi

# Single-instance guard (active mode only): a manual run while the 60s timer's
# run is mid-sleep would double-act -- two kill+resumes, or a race on the log
# rotation. Take a non-blocking lock; if another doctor holds it, exit quietly.
# --status is read-only and safe to run concurrently, so it skips the lock.
if [ "$RO" != "--status" ]; then
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$STATE_DIR/doctor.lock"
    flock -n 9 || { say "another flight-doctor is running -> skipping this run"; exit 0; }
  else
    # macOS / no flock: atomic mkdir lock with stale-lock reclaim (a crashed run
    # leaves the dir; reclaim it after 5 min so the watchdog never wedges itself).
    _ld="$STATE_DIR/doctor.lock.d"
    if ! mkdir "$_ld" 2>/dev/null; then
      if [ "$(( $(date +%s) - $(_mtime "$_ld") ))" -gt 300 ]; then
        rmdir "$_ld" 2>/dev/null; mkdir "$_ld" 2>/dev/null || { say "lock contended -> skipping"; exit 0; }
      else say "another flight-doctor is running -> skipping this run"; exit 0; fi
    fi
    trap 'rmdir "$STATE_DIR/doctor.lock.d" 2>/dev/null' EXIT
  fi
fi

log_rotate

# 1. Ensure the session exists.
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  if [ "$RO" = "--status" ]; then say "flight: DOWN (no tmux session)"; exit 1; fi
  say "flight DOWN -> launching..."
  logev WARN relaunch "tmux session was down; launched via $LAUNCHER"
  alert relaunch default "flight: session relaunched" "flight tmux session was down and has been auto-relaunched (conversation resumed via resume-pin)."
  tmux new-session -d -s "$SESSION" "$LAUNCHER"; sleep 6
fi

# 2/3. Settle prompts: accept trust, heal harmless gates. (skip in --status)
if [ "$RO" != "--status" ]; then
  for _ in 1 2 3; do
    p="$(pane)"
    if grep -q "trust this folder" <<<"$p"; then
      logev INFO trust "accepted trust-folder prompt"
      say "trust prompt -> accepting"; tmux send-keys -t "$SESSION" '1' Enter; sleep 5; continue
    fi
    if gate_confirmed "$p"; then
      # expand collapsed content first so the denylist sees the FULL command, then
      # re-evaluate against the expanded pane (pane_cmd re-captures live).
      if grep -qiE "$COLLAPSE_RE" <<<"$p"; then
        logev INFO gate_expand "collapsed content at gate -> Ctrl+O before deciding"
        tmux send-keys -t "$SESSION" C-o; sleep 1
      fi
      if grep -qiE "$MUTATION_RE" <<<"$(pane_cmd)"; then break; fi
      logev INFO gate_approve "routine permission gate approved (two-signal confirmed)"
      say "routine gate (bash/edit/write) -> approving (this time)"; tmux send-keys -t "$SESSION" '1' Enter; sleep 3; continue
    fi
    break
  done
fi

p="$(pane)"

# 4. Mutation gate waiting -> report, never auto-approve. (wrap-joined match;
#    gate detected by the hook sentinel OR the pane glyph -> robust to TUI drift)
if { grep -qE "$GATE_RE" <<<"$p" || gate_pending; } && grep -qiE "$MUTATION_RE" <<<"$(pane_cmd)"; then
  logev WARN mutation_hold "catastrophic-looking permission gate held for human"
  alert mutation high "flight: mutation gate needs you" "A catastrophic-looking permission gate is waiting in flight. Approve or deny from claude.ai, or attach to the tmux session."
  say ""
  say ">>> ACTION NEEDED: a permission gate is waiting (looks like an infra MUTATION)."
  say ">>> Approve from the app, or here: tmux send-keys -t $SESSION '1' Enter"
  say "----- pane -----"; pane | tail -18
  exit 0
fi

# 4b. Login / auth / billing failure -> a restart cannot fix an expired
#     credential, and kill+resume would hit the same wall (or clobber the
#     /login prompt). Hold for a human; never auto-restart.
#     CORROBORATION: the login/credential class is confirmed against the
#     authoritative `claude auth status` so that injected pane content merely
#     containing "/login" cannot DoS the watchdog with a false hold. Billing
#     ("credit balance") is not visible to auth status, so that class trusts the
#     string (rarer injection target).
pj="$(pane_j)"
ak="$(apifail_kind)"
if [ "$ak" = auth ] || grep -qiE "$AUTH_RE" <<<"$pj"; then
  # apifail=auth (StopFailure sentinel) is authoritative on its own; a bare pane
  # string is corroborated against `claude auth status` (anti-injection).
  if [ "$ak" != auth ] && auth_ok && ! grep -qiE 'Credit balance is too low' <<<"$pj"; then
    [ "$RO" != "--status" ] && logev INFO auth_skip "AUTH_RE matched but claude auth status=logged-in (likely injected content) -> not holding"
  else
  if [ "$RO" = "--status" ]; then say "flight: NEEDS LOGIN (auth/credential/billing failure)"; exit 3; fi
  logev WARN auth_hold "login/credential/billing failure; held for human (restart cannot fix)"
  alert auth high "flight: re-login needed" "flight hit a login/credential/billing failure. A restart cannot fix it -- attach and run /login in the flight session."
  say ""
  say ">>> ACTION NEEDED: flight needs re-authentication (login/credential/billing)."
  say ">>> A restart will NOT fix this. Attach and run /login:  tmux attach -t $SESSION"
  say "----- pane -----"; pane | tail -18
  exit 0
  fi
fi

# 5. Wedged TUI: "Waiting..." (no spinner clock) + no child + flat CPU + frozen frame.
if grep -q "Waiting" <<<"$p" && [ -z "$(spinner_elapsed)" ] && [ -n "$(flightpid)" ]; then
  P="$(flightpid)"; kids="$(kids_of "$P")"
  # integer-truncate %cpu (locale may use a comma decimal) for a portable compare
  c1="$(ps -o %cpu= -p "$P" 2>/dev/null | tr -d ' ')"; c1="${c1%%[.,]*}"; c1="${c1:-0}"
  f1="$(pane)"; sleep 3; f2="$(pane)"
  c2="$(ps -o %cpu= -p "$P" 2>/dev/null | tr -d ' ')"; c2="${c2%%[.,]*}"; c2="${c2:-0}"
  if [ "$kids" -eq 0 ] && [ "$f1" = "$f2" ] && [ "$c1" -lt 10 ] && [ "$c2" -lt 10 ]; then
    if [ "$RO" = "--status" ]; then say "flight: WEDGED (run flight-doctor to recover)"; exit 2; fi
    logev WARN wedge "Waiting TUI frozen (no child, CPU $c1/$c2)"
    say "WEDGED 'Waiting' TUI (no child, CPU $c1/$c2, frozen) -> kill+resume (lossless)..."
    kill_resume wedge
  else
    say "BUSY (Waiting, children=$kids, CPU $c1/$c2) -> leaving it alone."; exit 0
  fi
fi

# 6. STALLED spinner buster: spinner older than threshold + no child + content frozen.
el="$(spinner_elapsed)"
if [ -n "$el" ] && [ "$el" -ge "$STALL_SECS" ]; then
  P="$(flightpid)"; kids="$(kids_of "$P")"
  # token-delta: a climbing token count means a long in-process turn is still
  # PROGRESSING even when the visible content is frozen -- never bust that.
  s1="$(content_sig)"; tk1="$(spinner_tokens)"; sleep 5; s2="$(content_sig)"; tk2="$(spinner_tokens)"
  if [ "$kids" -eq 0 ] && [ "$s1" = "$s2" ] && [ "${tk2:-0}" -le "${tk1:-0}" ]; then
    if [ "$RO" = "--status" ]; then say "flight: STALLED spinner (${el}s) (run flight-doctor)"; exit 2; fi
    logev INFO stall_escape "spinner stalled ${el}s (tokens $tk1->$tk2) -> Escape"
    say "STALLED spinner (${el}s, no child, content+tokens frozen) -> sending Escape..."
    tmux send-keys -t "$SESSION" Escape; sleep 5
    el2="$(spinner_elapsed)"
    if [ -n "$el2" ] && [ "$el2" -ge "$STALL_SECS" ] && [ "$(content_sig)" = "$s2" ]; then
      say "Escape did not clear it -> kill+resume (lossless)..."
      kill_resume stall
    else
      logev INFO stall_clear "Escape cleared the stalled spinner"
      say "cleared by Escape."
    fi
  else
    say "spinner at ${el}s but PROGRESSING (children=$kids, content/tokens moving $tk1->$tk2) -> leaving it."; exit 0
  fi
fi

# 8. Remote Control channel silently dropped: process alive + idle (no spinner,
#    no gate) but ZERO outbound TLS conns to Anthropic -> the websocket died on
#    idle. Debounced; kill_resume's probe tells an idle drop apart from an outage
#    (and refuses to restart during one).
p="$(pane)"
if [ "$HEALED" = 0 ] && ! grep -qE "$GATE_RE" <<<"$p" && [ -z "$(spinner_elapsed)" ]; then
  P="$(flightpid)"
  if [ -n "$P" ] && [ "$(rc_conns "$P")" -eq 0 ]; then
    sleep 4
    if [ "$(rc_conns "$P")" -eq 0 ]; then
      if [ "$RO" = "--status" ]; then
        if anthropic_up; then say "flight: RC DROPPED (alive, no channel; run flight-doctor)"; exit 2
        else say "flight: Anthropic UNREACHABLE (outage); RC down"; exit 4; fi
      fi
      logev WARN rc_drop "0 outbound :443 conns while idle; RC websocket dropped"
      say "RC channel DOWN (0 conns to Anthropic, process alive, idle) -> kill+resume..."
      kill_resume rc_drop
    fi
  fi
fi

# 9. Status report (remote-control state from socket truth, not a pane grep).
p="$(pane)"
url="$(grep -oE 'https://claude.ai/code/session_[A-Za-z0-9]+' <<<"$p" | tail -1)"
if [ "$HEALED" = 1 ]; then rc="re-established"
elif [ "$(rc_conns "$(flightpid)")" -gt 0 ]; then rc="active"
elif anthropic_up; then rc="DOWN (idle drop -- rerun to heal)"
else rc="DOWN (Anthropic unreachable -- outage)"; fi
maybe_heartbeat "rc=$rc pid=$(flightpid)"
say ""
say "flight: ALIVE | remote-control: $rc | pid: $(flightpid)"
[ -n "$url" ] && say "app URL: $url"
say "----- pane (tail) -----"; pane | tail -12
exit 0   # reaching here == a completed run; don't leak the display pipe's exit status to systemd
