#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Persistent claude session for remote access while travelling.
# Runs `claude --remote-control` inside a tmux session so it survives detach and
# laptop sleep; reach it from claude.ai / your phone via the printed Remote
# Control URL, or by attaching to the tmux session over SSH. Respawns claude on
# exit so a crash mid-flight self-heals. Ctrl-C during the 3s grace drops to a
# login shell instead of respawning.
#
# Launch it under tmux, e.g.:
#   tmux new-session -d -s flight ~/.local/bin/flight-claude.sh
cd "$HOME" || exit 1
# Inference-only OAuth/API tokens silently CANNOT establish a Remote Control
# session -- their presence makes `claude --remote-control` fail in a way that
# looks exactly like a dropped channel, burning restart cycles forever. Clear
# them so RC uses the interactive (claude.ai) credential.
unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
# Source the same site config the watchdog reads, so a FLIGHT_RC_LABEL / FLIGHT_HOST
# override applies to BOTH the launcher and flight-doctor (they must agree on the
# remote-control name). Set FLIGHT_CONF=/dev/null to skip.
for _c in "${FLIGHT_CONF:-}" "$HOME/.config/flight-doctor.conf" "/etc/flight-doctor.conf"; do
  # shellcheck source=/dev/null
  [ -n "$_c" ] && [ -r "$_c" ] && { . "$_c"; break; }
done
SESSION="${FLIGHT_SESSION:-${RC_NAME:-flight}}"
FLIGHT_HOST="${FLIGHT_HOST:-$(hostname -s 2>/dev/null || hostname)}"
# The `claude --remote-control` name shown in the Claude Code web/desktop session
# list (host/user-aware). MUST match flight-doctor's RC_LABEL. Override the whole
# label with FLIGHT_RC_LABEL, or just the host component with FLIGHT_HOST.
RC_LABEL="${FLIGHT_RC_LABEL:-${SESSION}-${FLIGHT_HOST}-$(id -un)}"
# Optional: pin a session UUID to resume so respawns/heals continue the SAME
# conversation instead of starting blank. Clear the file for a fresh session.
RESUME_FILE="${FLIGHT_RESUME_FILE:-$HOME/.local/state/flight-resume}"
echo "[flight-claude] persistent claude session (Remote Control: ${RC_LABEL}). Ctrl-B d to detach (keeps it alive)."
# Optional hook layer: when FLIGHT_SETTINGS points at a readable settings file
# (see hooks/flight-hooks.json.example), pass it through so Claude Code emits
# lifecycle sentinels for flight-doctor. Off unless set.
FLIGHT_SETTINGS="${FLIGHT_SETTINGS:-$HOME/.config/flight-hooks.json}"
SETTINGS_ARGS=()
[ -r "$FLIGHT_SETTINGS" ] && SETTINGS_ARGS=(--settings "$FLIGHT_SETTINGS")
while true; do
  SID=""
  [ -f "$RESUME_FILE" ] && SID="$(head -n1 "$RESUME_FILE" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$SID" ]; then
    echo "[flight-claude] resuming session ${SID}"
    claude --remote-control "$RC_LABEL" "${SETTINGS_ARGS[@]}" --resume "$SID"
  else
    claude --remote-control "$RC_LABEL" "${SETTINGS_ARGS[@]}"
  fi
  rc=$?
  echo
  echo "[flight-claude] claude exited rc=${rc} -- respawning in 3s (Ctrl-C now for a shell)"
  if ! sleep 3; then
    echo "[flight-claude] dropping to a login shell; run 'exec $0' to resume the loop"
    exec bash -l
  fi
done
