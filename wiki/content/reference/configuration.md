---
title: Configuration
---

Every site-specific value comes from an environment variable or the config file.
The script's own defaults are generic, so it is publishable as-is.

Config is sourced from the first readable of `$FLIGHT_CONF`,
`~/.config/flight-doctor.conf`, `/etc/flight-doctor.conf`. Set
`FLIGHT_CONF=/dev/null` to skip. See `flight-doctor.conf.example`.

## Identity and paths

| Variable | Default | Meaning |
|---|---|---|
| `FLIGHT_SESSION` | `flight` | tmux session name |
| `FLIGHT_RC_LABEL` | `<session>-<host>-<user>` | Remote Control name shown in the Claude session list |
| `FLIGHT_HOST` | `hostname -s` | host component of the RC label |
| `FLIGHT_LAUNCHER` | `~/.local/bin/flight-claude.sh` | the respawn wrapper |
| `FLIGHT_SETTINGS` | `~/.config/flight-hooks.json` | passed as `--settings` when readable; presence enables the hook layer |
| `FLIGHT_STATE_DIR` | `~/.local/state/flight` | counters, sentinels, lock |
| `FLIGHT_LOG` | `$STATE_DIR/flight-doctor.log` | structured event log |
| `FLIGHT_RESUME_FILE` | `~/.local/state/flight-resume` | resume-pin; shared contract with the launcher |

The tmux name and the RC label are deliberately separate: the tmux name stays
short for `tmux attach`, while the RC label carries host and user so several
deployments are distinguishable in the UI.

## Timing and thresholds

| Variable | Default | Meaning |
|---|---|---|
| `FLIGHT_STALL_SECS` | `180` | spinner age before it counts as stalled |
| `FLIGHT_FLAP_MAX` | `3` | restarts (and relaunches) allowed in the window |
| `FLIGHT_FLAP_WINDOW` | `1800` | the window, in seconds |
| `FLIGHT_CRASHLOOP_YOUNG_SECS` | `90` | how young the inner process must be for pane exit-banners to count as a live crash loop |
| `FLIGHT_GATE_TTL` | | freshness TTL for the `gate.pending` sentinel |
| `FLIGHT_APIFAIL_TTL` | | freshness TTL for the `apifail` sentinel |
| `FLIGHT_HEARTBEAT_SECS` | | how often a quiet run still logs a heartbeat |

## Launch behaviour

| Variable | Default | Meaning |
|---|---|---|
| `FLIGHT_SCOPE_LAUNCH` | `auto` | `auto\|1\|0`. Relaunch via `systemd-run --user --scope` so the tmux server escapes the service cgroup. `auto` detects systemd via `INVOCATION_ID`. See [Run it under systemd](../how-to/run-under-systemd) |

## Alerting

| Variable | Default | Meaning |
|---|---|---|
| `FLIGHT_ALERT` | | master switch |
| `FLIGHT_NTFY_URL` | none | ntfy topic URL. **A bearer capability** -- anyone who learns it reads your alerts and can post fakes |
| `FLIGHT_ALERT_COOLDOWN_SECS` | | default per-key cooldown |
| `FLIGHT_ESCALATION_COOLDOWN_SECS` | `21600` | cooldown for breaker escalations. Long by design: once a breaker holds, every subsequent run hits it |
| `FLIGHT_ALERT_CLICK` | none | one-tap deep link on critical alerts. Point it at an **auth-gated out-of-band** terminal, never the session URL |

Alerts are off by default. Bodies are generic on purpose.

## Safety

| Variable | Default | Meaning |
|---|---|---|
| `FLIGHT_MUTATION_EXTRA` | none | extra EREs OR'd into the catastrophic denylist |
| `FLIGHT_DENYLIST_FILE` | none | file of EREs, one per line, also OR'd in |

Built-in denylist entries are **defaults, not a complete list**. Yours will
differ. See [Safety model](../explanation/safety-model).

## Log rotation

| Variable | Default | Meaning |
|---|---|---|
| `FLIGHT_LOG_MAX_BYTES` | `262144` | rotation threshold |
| `FLIGHT_LOG_KEEP_LINES` | `2000` | lines retained after a rotation |

## Testing

`FLIGHT_DOCTOR_LIB=1` sources the script in library mode without executing the
recovery ladder, which is how the unit suite exercises individual helpers.
