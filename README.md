<p align="center">
  <img src="assets/logo.svg" width="92" alt="claude-flight logo">
</p>

<h1 align="center">claude-flight</h1>

<p align="center">
  Keep a remote-controllable <b>Claude Code</b> session alive and self-heal it --
  an unattended watchdog that approves routine permission gates and <b>holds
  catastrophic ones</b>.<br>
  A power tool with a real footgun: read <a href="SECURITY.md">SECURITY.md</a> first.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license: MIT">
  <img src="https://img.shields.io/badge/status-reference%20release-blue" alt="status: reference release">
  <img src="https://img.shields.io/badge/tested-Claude%20Code%202.1.187-informational" alt="tested against Claude Code 2.1.187">
</p>

> [!WARNING]
> **Read before you install.** flight-doctor **auto-approves shell commands an
> LLM proposes**, holding back only what matches a *denylist you must complete
> for your own environment*. A denylist is never complete. Do not point this at a
> host, account, or data you cannot afford to lose. Read [SECURITY.md](SECURITY.md)
> first. Auto-approval is a convenience for unattended operation, **not** a
> security boundary.

**FLIGHT** -- *Failsafe Liveness & Idle Guardian for Headless Terminals* -- is a
persistent, remote-controllable **Claude Code** session you leave running on an
always-on box and reach from your phone or laptop while travelling.
**`flight-doctor`** is its self-healing watchdog.

You run `claude --remote-control` inside `tmux` on a server. That session can
silently degrade in ways the built-in auto-reconnect does not cover: the Remote
Control websocket drops after a long idle, a tool call wedges, a spinner stalls,
a permission gate blocks forever, the API has an outage, or your credentials
expire. `flight-doctor` is a small, dependency-light Bash script (run every ~60s
by a systemd timer) that detects each of these and takes the *right* action --
including refusing to act when a restart would not help.

> Not affiliated with Anthropic. "Claude Code" is Anthropic's product; this is a
> third-party operational wrapper around its CLI.

This is as much a documented **operational pattern** as a tool: the value is the
detection model and the policy, and the script is a reference implementation you
fork and adapt.

### From copilot to pilot

An AI coding agent is a *copilot* when every action needs a human hand on the
yoke. It edges toward *pilot* -- acting on its own within a safe envelope -- the
way aviation autopilots earned trust: not by being smarter, but by **envelope
protection** -- hard limits it cannot cross, and a human it pages when something
nears the edge. flight-doctor is that envelope for an unattended Claude Code
session: routine actions proceed, catastrophic ones are held for a human, and the
agent is restarted or stood down when continuing would do harm. The guardrails
are what *buy* the autonomy.

They buy it; they do not guarantee it. A denylist narrows the envelope -- it is
not a certificate of safe flight (this project shipped, and then fixed, denylist
bypasses). Treat the autonomy as *earned and bounded*, and read
[SECURITY.md](SECURITY.md) before you trust it unattended.

---

## Quickstart

It's a dependency-light Bash script run every ~60s. Install by picking a
[deployment profile](#deployment-profiles) then the [install steps](#install) --
**read [SECURITY.md](SECURITY.md) first** (it auto-approves commands). Once running,
`flight-doctor --selftest` reports health + TUI/upgrade drift:

```text
flight-doctor --selftest (tested against Claude Code 2.1.187):
  [OK  ] tmux session 'flight' present
  [OK  ] claude pid 12890 (comm-filtered)
  [OK  ] resume-pin present
  [OK  ] Claude Code 2.1.187 == tested
  [OK  ] detector regexes match known fixtures
  [OK  ] claude auth status: logged in
  [OK  ] hook layer active (session.alive present)
  [OK  ] state dir 28KB
RESULT: HEALTHY
```

When something breaks, the event log shows exactly what it did (sanitized):

```text
2026-01-02T07:41:03Z WARN  rc_drop      0 outbound :443 conns while idle; RC websocket dropped
2026-01-02T07:41:23Z WARN  kill_resume  restarting (reason=rc_drop, oldpid=12345)
2026-01-02T07:41:43Z INFO  kill_resume  restart complete (newpid=12890)
```

## Why

`claude --remote-control <name>` prints a `claude.ai/code/session_...` URL you
can open anywhere. Wrapped in `tmux` + a respawn loop, it survives detach,
laptop sleep, and crashes. But a bare session still has failure modes a human
has to notice and fix. `flight-doctor` is the missing watchdog:

- It tells a **silent idle RC drop** (process alive, websocket dead) apart from
  a real **API outage**, and only restarts in the first case.
- It auto-approves **routine** permission gates so unattended work proceeds, but
  **holds catastrophic ones** for a human.
- It detects **auth/billing failures** and escalates them instead of pointlessly
  restarting into the same wall.
- It has a **circuit breaker** so a flapping channel cannot become a restart loop.
- All recovery is **lossless**: a pinned session UUID means every restart
  resumes the *same* conversation.

## Prior art -- why not just systemd / monit / a liveness probe?

Use those for what they are good at; flight-doctor sits a layer above them.

| Tool | What it restarts | What it cannot do |
|---|---|---|
| systemd `Restart=`, supervisord, monit | a **dead process** | sees nothing wrong with a *live* process whose application-layer channel died |
| Kubernetes liveness/readiness probes | a container failing a health check | no notion of an interactive permission prompt or a provider outage |
| Claude Code's built-in reconnect | network blips while the machine sleeps | a silent idle websocket drop, a wedged TUI, or a stuck gate |

flight-doctor's narrow, genuinely-different surface:
- it heals a **live process whose Remote Control websocket silently died**
  (detected by socket count, not by the process being gone) -- a generic
  supervisor sees a healthy process and does nothing;
- it **declines to restart** when a restart cannot help (API outage, expired
  credential) instead of thrashing -- the inverse of "always restart";
- it **answers a semantic UI prompt** (the permission gate), approving routine
  and holding catastrophic.

If all you need is "restart the process when it dies," use systemd -- and in fact
flight-doctor runs *under* a systemd timer. It is the supervisor for the failures
a supervisor cannot see.

### Related projects

Other tools overlap on pieces of this; none combine them. claude-flight is the
union of *keep the session alive* + *denylist-gated auto-approve* + *detect a
dropped channel* + *alert* -- which none of these ship together.

- **[gpayne9/claude-always-on](https://github.com/gpayne9/claude-always-on)** --
  closest: self-healing remote-control sessions via a tmux restart loop + health
  monitor + backoff. No semantic auto-approve, no catastrophic denylist, no
  websocket-drop detection (macOS-focused).
- **[claude-yolo](https://github.com/claude-yolo/claude-yolo)** -- the same
  `capture-pane` + `send-keys` auto-approve mechanism, but **no denylist**: it
  approves every prompt, destructive ones included. The unsafe baseline this
  improves on.
- **[mixpeek/amux](https://github.com/mixpeek/amux)** -- fleet multiplexer that
  restarts sessions and unblocks stuck prompts by type; an orchestration tool, no
  safety denylist.
- **[flavio87/tap-to-tmux](https://github.com/flavio87/tap-to-tmux)** -- ntfy
  alerts when an agent needs attention, with per-project dedup and deep links; it
  *pages*, it doesn't *act*.
- **[a5c-ai/babysitter](https://github.com/a5c-ai/babysitter)** -- enforced human
  gates + `harness:doctor`/`harness:resume` + an event journal; a build-time
  orchestrator, not a session watchdog (naming lineage for "doctor").
- **[Anthropic Auto Mode](https://www.anthropic.com/engineering/claude-code-auto-mode)**
  -- the official safety analogue: a model classifier + circuit breaker + hard
  denylist. claude-flight is the deterministic, terminal-level version that works
  on the Remote Control TUI where the classifier is not in the loop.

Why it exists: Claude Code's Remote Control silently drops and does not self-heal,
and the trust prompt blocks unattended start (Claude Code issues
[#31853](https://github.com/anthropics/claude-code/issues/31853),
[#34255](https://github.com/anthropics/claude-code/issues/34255),
[#28914](https://github.com/anthropics/claude-code/issues/28914),
[#53606](https://github.com/anthropics/claude-code/issues/53606)). claude-flight
is the watchdog the official feature lacks.

## How it works

### Detection signals (no screen-scraping for the important stuff)

| Condition | Signal used | Why it is reliable |
|---|---|---|
| RC channel alive? | count of ESTABLISHED `:443` sockets owned by the claude pid (`ss`) | a healthy RC holds a persistent websocket; idle-drop takes it to 0. The on-screen `/rc active` footer is hidden during generation, so socket truth beats grepping the pane |
| API reachable? | one `curl` to the API (any HTTP status = up; only a timeout/000 = down) | distinguishes an idle drop (restart helps) from an outage (restart thrashes) |
| Which process to act on | `pgrep -f "claude --remote-control <name>"` filtered by `comm=claude` | a bare cmdline match can hit an editor/grep/this script; the comm filter prevents killing the wrong pid |
| Wedged / stalled | no child process + flat CPU + frozen pane frame over a short interval | only acts when genuinely stuck, not merely slow |
| Catastrophic command at a gate | regex over a **wrap-joined** pane capture (`tmux ... -J`) | joining wrapped rows stops a long command from hiding a dangerous token across a line break |

### Recovery state machine (in order, first match wins)

1. **Session missing** -> launch it (and alert `relaunch`).
2. **Trust prompt** -> accept.
3. **Routine permission gate** -> approve (so unattended work continues).
4. **Catastrophic gate** (denylist) -> HOLD, alert, never auto-approve.
5. **Auth / credential / billing failure** -> HOLD, alert. A restart cannot fix
   an expired credential.
6. **Wedged tool call** -> kill + resume (lossless).
7. **Stalled spinner** -> send Escape; if that fails, kill + resume.
8. **RC websocket dropped while idle** -> kill + resume (guarded by the outage
   probe and the flap breaker).

Every kill+resume is gated by:
- the **outage probe** -- if the API is unreachable, it refuses and alerts
  rather than thrashing;
- the **flap circuit breaker** -- after `FLAP_MAX` restarts within
  `FLAP_WINDOW`, it stops and escalates.

### Safety model

The default policy is **"routine yes, catastrophic no"**: anything *not* on the
catastrophic denylist is auto-approved. The denylist (`MUTATION_RE`) covers
system-root `rm -rf`, load-bearing home dirs (`.ssh`, repos, config), cluster
teardown (k3s/cilium/helm/`kubectl delete namespace|node|pv|pvc`), host power,
disk/filesystem ops, network-lockout (`ufw`/`iptables`/`nft`), cloud-infra
destruction (`hcloud`/`aws`/`gcloud`/...), mass prune, recursive perms from
root, data-loss git (`reset --hard`, `clean -f`, `push`), pipe-to-shell remote
execution, IaC `destroy`, and package purges. Tune it to your environment without
editing the script -- add ERE patterns to `~/.config/flight-denylist` (one per
line) or `FLIGHT_MUTATION_EXTRA`; both are OR'd into the built-in list. It is a
denylist, so review the gaps before trusting it unattended.

## Logging and lifecycle

- A structured event log (default `~/.local/state/flight/flight-doctor.log`),
  one line per noteworthy event: `TIMESTAMP LEVEL EVENT detail`.
- Healthy runs do **not** spam it: a heartbeat is written at most once per
  `FLIGHT_HEARTBEAT_SECS`.
- **Rotation/retention** is built in: past `FLIGHT_LOG_MAX_BYTES` the log is
  trimmed to the last `FLIGHT_LOG_KEEP_LINES` lines. (journald already keeps the
  raw per-run stdout; this file is the durable, bounded event trail.)
- `flight-doctor --status` is **read-only**: it reports state and writes nothing.

Example excerpt (sanitized):

```
2026-01-02T07:41:03Z WARN  rc_drop        0 outbound :443 conns while idle; RC websocket dropped
2026-01-02T07:41:23Z WARN  kill_resume    restarting (reason=rc_drop, oldpid=12345)
2026-01-02T07:41:43Z INFO  kill_resume    restart complete (newpid=12890)
2026-01-02T08:41:43Z INFO  heartbeat      rc=active pid=12890
```

## Alerting (optional)

Critical events (`relaunch`, `mutation_hold`, `auth_hold`, `outage_hold`,
`flap`) can post to an [ntfy](https://ntfy.sh) topic for a phone push. Alerts
are **off by default** -- set `FLIGHT_NTFY_URL` to enable. They are rate-limited
per event key, and bodies are deliberately **generic** (no session URL, tokens,
or pane contents), because an ntfy topic is a shared bearer capability.

## Deployment profiles

Pick the row that matches where you're running this. **Egress restriction and
keeping the Remote Control URL secret apply to every row** -- they cost nothing
and contain a hijacked or prompt-injected agent regardless of privilege.

| Profile | You're running on... | Run as | Credentials | Auto-approve |
|---|---|---|---|---|
| **Personal dev box** | a single-user host you own and administer | yourself / a privileged user -- it *is* your remote dev box | your normal ones (you accept the reach) | tune `MUTATION_RE` to your stack, or hand-run `flight-doctor` |
| **Shared / sensitive host** | a multi-user box, or one holding prod secrets, others' data, or a pivot to other systems | a **dedicated unprivileged user** (no blanket sudo, no `docker`/`wheel` group) | **scoped**: K8s `Role` not cluster-admin, project-scoped cloud token, read-only secret tokens | denylist + hold more than default; alert on holds; review the event log |
| **Throwaway sandbox** | a disposable VM you rebuild freely, nothing valuable on it | whatever is convenient | none / minimal | full auto is fine |

Reasoning and the full threat model are in [SECURITY.md](SECURITY.md).

## Install

```sh
# 1. Scripts
install -m755 bin/flight-doctor.sh   ~/.local/bin/flight-doctor
install -m755 bin/flight-claude.sh   ~/.local/bin/flight-claude.sh

# 2. Config (optional; needed for alerts / non-default paths)
mkdir -p ~/.config
cp flight-doctor.conf.example ~/.config/flight-doctor.conf
chmod 600 ~/.config/flight-doctor.conf   # then edit

# 3. Start the persistent session under tmux
tmux new-session -d -s flight ~/.local/bin/flight-claude.sh

# 4. Run the watchdog every ~60s as a user service
mkdir -p ~/.config/systemd/user
cp systemd/flight-doctor.{service,timer} ~/.config/systemd/user/
systemctl --user enable --now flight-doctor.timer
loginctl enable-linger "$USER"   # survive logout / reboot
```

`flight-claude.sh` reads an optional resume-pin file
(`~/.local/state/flight-resume`) containing a session UUID, so every respawn
continues the same conversation. Remove the file for a fresh session.

## Configuration

All site-specific values come from environment variables or the config file;
the script's own defaults are generic so it is publishable as-is. See
[`flight-doctor.conf.example`](flight-doctor.conf.example) for the full list.
Key ones: `RC_NAME`, `FLIGHT_LAUNCHER`, `FLIGHT_NTFY_URL`, `FLIGHT_STALL_SECS`,
`FLIGHT_FLAP_MAX`/`_WINDOW`, `FLIGHT_LOG_MAX_BYTES`/`_KEEP_LINES`.

## Hooks: structured signals (optional)

Detection currently scrapes the TUI. A more robust path -- immune to UI restyling
and to pane-content injection -- is Claude Code's own lifecycle hooks.
[`hooks/flight-notify.sh`](hooks/flight-notify.sh) is a receiver Claude Code
invokes on each event; it writes atomic **sentinel files** into the state dir
(`gate.pending` on a permission prompt, `apifail` on an API/auth failure,
`session.alive`, a `progress` heartbeat on Stop/UserPromptSubmit):

```sh
install -m755 hooks/flight-notify.sh ~/.local/bin/flight-notify.sh
cp hooks/flight-hooks.json.example ~/.config/flight-hooks.json   # point commands at the abs path
export FLIGHT_SETTINGS=~/.config/flight-hooks.json               # the launcher passes --settings
```

Verified firing under `claude --remote-control` (Claude Code 2.1.187):
SessionStart, UserPromptSubmit, Stop, StopFailure, Notification. Caveats found
empirically: hooks do not fire until the workspace-trust prompt is accepted;
`StopFailure` carries `error` + `last_assistant_message` (**not** `error_type`);
`Notification` carries `notification_type` (`permission_prompt` vs `idle_prompt`);
and if the session runs in **Auto Mode**, Claude's own classifier handles benign
gates, so no `permission_prompt` fires (flight-doctor's gate handling applies in
default/accept-edits mode).

flight-doctor **consumes** these sentinels sentinel-first (with pane-scrape
fallback) -- e.g. a `StopFailure` sentinel forces an outage-hold deterministically,
and `gate.pending` corroborates a permission gate. It is wired and, where the hook
layer is enabled, active.

## Testing

```sh
bin/flight-doctor.test.sh              # unit suite (helpers, regexes, sentinels)
bin/flight-doctor.integration.test.sh  # whole if-ladder vs canned pane fixtures
```

The **integration** suite drives the entire decision if-ladder against stub
`tmux`/`pgrep`/`ss`/`curl`/`claude` and recorded pane fixtures, asserting the
DECISION (approve routine gate / hold mutation gate / hold auth / restart on RC
drop / refuse restart on outage) -- the coverage the unit suite can't reach.

The unit suite sources the script in **library mode** (`FLIGHT_DOCTOR_LIB=1`) so only
the pure helpers load, then exercises them with mocked `ss`/`curl`/`kill`/
`tmux`/`date`. No real session is touched, no network call is made, no process
is killed. It covers socket parsing, the reachability probe, the auth and
catastrophic regexes (positive and false-positive cases), the comm-filtered pid
resolver, the outage-guarded restart, the flap breaker, logging + the read-only
`--status` guard, rotation, the heartbeat rate limiter, and alert
rate-limiting / opt-outs / generic-body guarantees.

## Security considerations

- This watchdog can drive a privileged session and auto-approves non-denylisted
  commands. **Review `MUTATION_RE` against your environment** before running it
  unattended; a denylist is never complete.
- The catastrophic match runs against a wrap-joined capture to resist
  line-break evasion, but gate decisions ultimately read pane text, which can
  contain arbitrary content. Treat auto-approval as a convenience, not a
  security boundary.
- ntfy topics are shared bearer capabilities (read + inject). Use an
  authenticated or self-hosted instance for anything sensitive; keep alert
  bodies generic (this tool does).
- The session's Remote Control URL is itself reach-to-control -- protect it like
  a credential and do not paste it into shared logs.

See [SECURITY.md](SECURITY.md) for the full threat model, the denylist's known
limits, and the preconditions you are accepting by running this unattended.

## Compatibility

**Tested against Claude Code `2.1.187`.** The Claude Code *CLI version* is the
compatibility factor that matters: detection keys off the CLI's behavior and its
(undocumented) TUI strings, so a future release can change them. Run a version at
or above the tested one and re-validate after upgrades -- `flight-doctor --selftest`
is a read-only drift canary that flags exactly this (version change, a detector
regex that stopped matching its fixture, hooks that stopped firing, lost auth).

**Model-agnostic.** The watchdog operates at the session / CLI layer, *below* the
model. It never inspects or depends on which Claude model the session runs, so the
model you pick (Opus / Sonnet / Haiku) does not affect it.

Remote Control is a recent Claude Code feature; if `claude --remote-control` is not
available, upgrade. (The structured-signal roadmap in [SECURITY.md](SECURITY.md)
uses newer sub-commands such as `claude auth status --json`.)

## Requirements & platform support

**Runtime dependencies** (the watchdog):
- **bash >= 4.4** (arrays + `set -u`-safe empty-array expansion)
- **tmux**, and the **`claude` CLI** with `--remote-control` support
- **GNU coreutils** (`stat -c`, `date`, `du`, `timeout`) + **grep / sed / awk**
- **iproute2** (`ss`) -- socket-truth RC-drop detection
- **util-linux** (`flock`) -- single-instance guard
- **procps** (`pgrep` / `ps`)
- optional: **curl** (reachability probe + ntfy alerts), **jq** (hook receiver),
  **systemd** (any ~60s scheduler works -- cron/launchd too)

**Platform support:**

| Platform | Status |
|---|---|
| Linux, glibc + GNU coreutils (Debian / Ubuntu / Fedora / Arch) | ✅ supported, CI-tested |
| Linux, musl / busybox (Alpine) | ⚠️ best-effort -- install `bash coreutils iproute2 util-linux procps`; CI advisory |
| macOS | ❌ not yet -- needs bash 4.4+ + GNU coreutils (Homebrew) and `ss`->`lsof` + `flock` shims; CI advisory |
| Windows | ❌ not native -- run it inside **WSL** (= Linux). It is a server-side tmux watchdog, not a desktop app |

This is a **Linux-first** tool -- it lives on an always-on host next to tmux.
macOS portability (lsof/flock/coreutils shims) is a tracked follow-up, not a flag.

## License

MIT -- see [LICENSE](LICENSE).

## License

MIT -- see [LICENSE](LICENSE).
