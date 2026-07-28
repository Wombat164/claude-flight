---
title: Exit codes and events
---

## `--status` exit codes

`--status` is read-only: it reports and never acts. The exit code is the
machine-readable answer, useful for monitoring.

| Code | Meaning |
|---|---|
| `0` | ALIVE |
| `1` | DOWN -- no tmux session |
| `2` | WEDGED, STALLED spinner, or RC DROPPED -- a run of `flight-doctor` can recover it |
| `3` | NEEDS LOGIN -- auth, credential or billing failure |
| `4` | Anthropic UNREACHABLE -- outage; RC is down but restarting will not help |
| `5` | CLAUDE CRASH-LOOPING -- the wrapper is respawning a dying process |

Codes `3`, `4` and `5` all mean *a human is required*: no amount of restarting
fixes an expired credential, a provider outage, or a process that dies on start.

In active mode (no `--status`) the script exits `0` for handled conditions,
including breaker holds, so the systemd unit stays clean.

## Event log keys

One line per event in `$FLIGHT_LOG`, with a severity and a stable key.

**Lifecycle**

| Key | When |
|---|---|
| `relaunch` | tmux session was missing; launched |
| `launch_scope` | fell back to a plain tmux launch because the scope launch failed |
| `relaunch_died` | the relaunched session was already gone again |
| `relaunch_flap` | relaunch breaker tripped; no longer relaunching |
| `reboot` | host `boot_id` changed; breaker budgets reset |
| `trust` | accepted the trust-folder prompt |
| `heartbeat` | periodic proof-of-life on an otherwise quiet run |
| `log_rotate` | event log rotated |

**Recovery**

| Key | When |
|---|---|
| `rc_drop` | zero outbound `:443` connections while idle; websocket dropped |
| `kill_resume` | restarting the session (lossless, via the resume-pin) |
| `wedge` | wedged tool call detected |
| `stall_escape` | stalled spinner; sent Escape |
| `stall_clear` | the spinner cleared |
| `flap` | restart breaker tripped |

**Holds -- deliberately not acting**

| Key | When |
|---|---|
| `mutation_hold` | a gate matched the catastrophic denylist; held for a human |
| `auth_hold` | auth, credential or billing failure |
| `auth_skip` | auth check skipped |
| `outage_hold` | the API is unreachable; a restart would not help |
| `crashloop` | the wrapper is respawning a dying process |

**Gates and pin**

| Key | When |
|---|---|
| `gate_approve` | approved a routine permission gate |
| `gate_expand` | expanded a collapsed gate before deciding |
| `resume_missing` | no resume-pin; a restart would start blank |
| `resume_repin` | adopted a live session id from the hook sentinel |
| `alert` | a notification was sent |

## Hook sentinels

When the hook layer is enabled, `$STATE_DIR/hooks/` holds `session.alive`,
`gate.pending`, `apifail` and `progress`. The watchdog reads them
sentinel-first, falling back to scraping the pane. Sentinels are checked for
freshness so a hook that stopped firing does not silently pin a stale state.
