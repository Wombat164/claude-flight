---
title: Troubleshoot a session
---

Start with the read-only view. It never changes anything:

```bash
flight-doctor --status ; echo "exit=$?"
```

The exit code tells you which branch matched -- see
[Exit codes](../reference/exit-codes).

Then the event log, which records what the watchdog actually did:

```bash
tail -n 40 ~/.local/state/flight/flight-doctor.log
export XDG_RUNTIME_DIR=/run/user/$(id -u)
journalctl --user -u flight-doctor.service -n 30 --no-pager
```

## It relaunches forever and every run says ALIVE

The cgroup trap. See [Run it under systemd](run-under-systemd).

## It never starts at all after a reboot

`loginctl enable-linger "$USER"` was never run, so the user manager does not
start until you log in. Check `loginctl show-user "$USER" -p Linger`.

## `rc=127` in the wrapper's exit banner

The `claude` binary is not on `PATH` for a systemd-launched process. The native
installer puts it in `~/.local/bin`, which a user unit does not inherit.
`flight-claude.sh` hardens this itself; if you wrote your own launcher, export
`PATH` before invoking `claude`.

## It restarts over and over (kill+resume, not relaunch)

The flap circuit breaker should stop this after `FLIGHT_FLAP_MAX` restarts
within `FLIGHT_FLAP_WINDOW`, logging `flap`. If restarts keep happening, the
underlying channel is genuinely unstable -- check whether `anthropic_up` can
reach the API at all, and look for `outage_hold` in the log.

## It refuses to restart and says the API is unreachable

Working as intended. An outage is not something a restart fixes, so the watchdog
holds (`outage_hold`) rather than thrashing. It resumes normal behaviour when
the probe succeeds again.

## It says re-login is needed

`auth_hold`, or `crashloop` with an auth-aware message. A restart cannot fix an
expired credential. Attach and run `/login`:

```bash
tmux attach -t flight
```

Note the failure mode this covers: a `claude` that dies at launch never runs a
turn, so the hook path never fires. That is why the crash-loop detector checks
`claude auth status` directly instead of waiting for a sentinel.

## It reports a crash loop but nothing is wrong

The detector looks for the wrapper's exit banner in the pane, which is ordinary
text. Reading the launcher source *inside* the session used to trigger it. Since
v0.2.0 it corroborates against process age: a real loop means the inner process
is gone or freshly started. Tune with `FLIGHT_CRASHLOOP_YOUNG_SECS` (default
90s). If your host's `ps` has no `etimes`, the check fails open.

## A gate is stuck and it will not approve it

By design, if the command matches the catastrophic denylist. Look for
`mutation_hold` in the log, read the pending command, and decide yourself:

```bash
tmux attach -t flight
```

## Restarts start blank conversations

The resume-pin is missing. Since v0.2.0 the watchdog self-heals it from the
`session.alive` hook sentinel, but only when the hook layer is enabled and only
when no pin exists (it never overwrites yours). Set it by hand:

```bash
echo "<session-uuid>" > ~/.local/state/flight-resume
```

## Nothing above matches

`flight-doctor --selftest` checks for drift between the script's assumptions and
the installed Claude Code: version mismatch, detector regexes that no longer
match known fixtures, a hook layer that stopped firing. A TUI change upstream
can blind a detector without breaking anything visibly.
