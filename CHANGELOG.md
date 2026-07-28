# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-07-28

Cold start now survives. The watchdog could keep an existing session alive but
could never bootstrap one.

### Fixed

- Relaunch is detached from the caller's cgroup via `systemd-run --user --scope`
  when running under systemd. A `Type=oneshot` unit with the default
  `KillMode=control-group` reaped a tmux server born in its cgroup, so a cold
  relaunch died seconds later and the watchdog looped indefinitely while every
  run reported success ([#4](https://github.com/Wombat164/claude-flight/issues/4)).
- `KillMode=process` in the shipped unit, as a backstop for the plain-tmux
  fallback path.
- `FLIGHT_RESUME_FILE` is honoured by the watchdog, not just the launcher. The
  two were previously out of sync.
- The launcher's `PATH` hardening is folded back in, so a timer-driven relaunch
  cannot fail with `rc=127` when `claude` lives in `~/.local/bin`.

### Added

- Relaunches count toward the circuit breaker. At the cap the watchdog stops
  relaunching, logs `relaunch_flap` and escalates once with a long cooldown
  (`FLIGHT_ESCALATION_COOLDOWN_SECS`, default 6h) instead of dripping one
  notification per cooldown indefinitely. A relaunch that dies immediately logs
  `relaunch_died`.
- Host-reboot detection via `boot_id`, which resets both breaker budgets.
- Inner crash-loop detection: repeated launcher exit banners mean the wrapper is
  respawning a dying process, which neither relaunch nor kill+resume can fix.
  Auth-aware, so an expired credential is reported as "run `/login`".
  Corroborated against process age (`FLIGHT_CRASHLOOP_YOUNG_SECS`, default 90s),
  because the banner is ordinary pane text.
- Resume-pin self-heal from the `session.alive` hook sentinel when no pin exists.
  Never overwrites an operator-set pin, never writes under `--status`. The
  relaunch alert now states whether the conversation resumes or starts blank.
- Optional per-call cooldown argument on `alert()`.

### Docs

- The systemd cold-start gotcha and the new tunables are documented in the
  README and `flight-doctor.conf.example`.
- Docs site (Quartz) at <https://wombat164.github.io/claude-flight/>.

### Testing

- Unit 140 (was 123), integration 24 (was 13). New coverage: the
  `launch_detached` matrix, `maybe_repin`, per-call alert cooldowns, cold
  relaunch via scope, launch-died, the relaunch breaker, crash loop, and reboot
  detection.
- Tested against Claude Code 2.1.220.

## [0.1.0] - 2026-06-24

Initial public release.

### Added

- `flight-claude.sh`: tmux respawn wrapper for `claude --remote-control`, with a
  resume-pin so restarts continue the same conversation.
- `flight-doctor.sh`: the watchdog. Socket-truth Remote Control drop detection,
  outage-versus-idle discrimination, auth/credential/billing holds, wedged tool
  call recovery, stalled spinner recovery, routine permission-gate approval with
  a catastrophic denylist hold, and a restart circuit breaker.
- Structured event log with rotation, rate-limited heartbeat, read-only
  `--status`, and a `--selftest` drift canary.
- Optional ntfy alerting with generic bodies and a config-extensible denylist.
- Optional hook layer: lifecycle sentinels consumed sentinel-first with a
  pane-scrape fallback.
- Unit and integration suites; CI across ubuntu, debian, fedora, alpine and
  macOS.

[Unreleased]: https://github.com/Wombat164/claude-flight/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Wombat164/claude-flight/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Wombat164/claude-flight/releases/tag/v0.1.0
