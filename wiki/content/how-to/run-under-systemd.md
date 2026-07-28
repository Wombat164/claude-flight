---
title: Run it under systemd
---

The watchdog is meant to run from a systemd user timer. There is one trap in
that deployment, and it only bites from cold.

## The trap

`flight-doctor.service` is `Type=oneshot`. systemd's default is
`KillMode=control-group`, which kills everything left in the unit's cgroup when
the run finishes.

If a tmux server is **already running**, a relaunch just asks that server for a
new session and nothing is wrong. If **no server exists** -- after a reboot --
`tmux new-session` forks a *new server*, and that server is born inside the
service cgroup. The ~12s oneshot run ends, systemd reaps the cgroup, and the
server dies with it.

The result is a watchdog that can keep a session alive but can never bootstrap
one. It relaunches every 60s forever, and **every run reports success**, because
the session genuinely is alive for the few seconds the unit is running.

## The fix (shipped)

Since v0.2.0 the watchdog relaunches through `systemd-run --user --scope` when
it detects it is running under systemd (`INVOCATION_ID` is set), which puts the
tmux server in its own scope instead of the caller's cgroup. The shipped unit
also sets `KillMode=process` as a backstop for the plain-tmux fallback path.

Nothing to do beyond using the shipped `systemd/flight-doctor.service`. If you
wrote your own unit, add:

```ini
[Service]
KillMode=process
```

`FLIGHT_SCOPE_LAUNCH=auto|1|0` forces the choice. Leave it at `auto` unless you
launch the watchdog some way that is neither systemd nor an interactive shell.

## Verifying it on your host

Destroy the server and let the timer do the work:

```bash
tmux kill-server
sleep 90
cat /proc/$(pgrep tmux | head -1)/cgroup
```

You want a **transient scope**:

```text
0::/user.slice/user-1000.slice/user@1000.service/app.slice/run-<id>.scope
```

Not `.../flight-doctor.service` (the bug) and not `.../session-<n>.scope` (that
means a human started it from a login shell, which also survives, but is not the
watchdog doing its job).

`pgrep -x tmux` matches nothing, by the way -- the server's `comm` is
`tmux: server`.

## Recognising the failure in the wild

- `flight DOWN -> launching` in the journal on a ~60s cadence, indefinitely
- every run also logging `ALIVE`
- a new `claude.ai/code/session_...` URL each cycle
- small orphan transcripts piling up in the Claude projects directory
- one notification per alert cooldown, for days

Since v0.2.0 this escalates instead of dripping: relaunches count toward the
circuit breaker, and at the cap the watchdog stops relaunching, logs
`relaunch_flap`, and sends one urgent alert with a long cooldown
(`FLIGHT_ESCALATION_COOLDOWN_SECS`, default 6h).

## Related

- [Troubleshooting](troubleshoot) for the other failure signatures
- [Configuration](../reference/configuration)
