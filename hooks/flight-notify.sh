#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# claude-flight hook receiver. Wired into Claude Code via --settings (see
# hooks/flight-hooks.json.example). Claude Code invokes this on each lifecycle
# event with the event name as $1 and the event JSON on stdin; it writes an
# ATOMIC sentinel file into the state dir so flight-doctor can read structured
# truth instead of scraping the (undocumented, drift-prone) TUI.
#
# Validated firing under `claude --remote-control` on Claude Code 2.1.187
# (2026-06-24): SessionStart / UserPromptSubmit / Stop / StopFailure /
# Notification all fire. NOTE: StopFailure carries `error` + `last_assistant_message`
# (NOT `error_type`); Notification carries `notification_type`
# (permission_prompt vs idle_prompt). Hooks do not fire until the workspace-trust
# prompt is accepted.
set -u
EV="${1:-unknown}"
DIR="${FLIGHT_STATE_DIR:-$HOME/.local/state/flight}/hooks"
mkdir -p "$DIR" 2>/dev/null || exit 0
payload="$(cat)"
ts="$(date -u +%FT%TZ)"

jqget(){ command -v jq >/dev/null 2>&1 && jq -r "$1 // empty" <<<"$payload" 2>/dev/null; }
sid="$(jqget '.session_id')"
# atomic write (tmp + mv) so flight-doctor never reads a half-written sentinel
put(){ local f="$DIR/$1"; shift; printf '%s %s\n' "$ts" "$*" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" 2>/dev/null || true; }
clr(){ rm -f "$DIR/$1" 2>/dev/null || true; }

case "$EV" in
  Notification)
    case "$(jqget '.notification_type')" in
      permission_prompt) put gate.pending "sid=$sid msg=$(jqget '.message')" ;;
      idle_prompt)       put idle.pending  "sid=$sid" ;;
      *)                 put notify.other  "sid=$sid type=$(jqget '.notification_type')" ;;
    esac ;;
  Stop)             put progress "sid=$sid stop";   clr gate.pending; clr idle.pending ;;
  UserPromptSubmit) put progress "sid=$sid prompt"; clr gate.pending; clr idle.pending ;;
  StopFailure)      put apifail  "sid=$sid error=$(jqget '.error') msg=$(jqget '.last_assistant_message')" ;;
  SessionStart)     put session.alive "sid=$sid"; clr apifail ;;
  SessionEnd)       clr session.alive ;;
  *)                put "event.$EV" "sid=$sid" ;;
esac
exit 0
