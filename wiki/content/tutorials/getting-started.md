---
title: Getting started
---

By the end of this you will have a session that survives you killing it.

Read
[SECURITY.md](https://github.com/Wombat164/claude-flight/blob/main/SECURITY.md)
first. This tool auto-approves commands. Use a host you can afford to break.

## 1. Requirements

`bash`, `tmux`, `claude` (Claude Code CLI), and a systemd user manager. `ss`,
`curl` and `flock` are used where present. macOS works with the shipped shims.

## 2. Get the scripts

```bash
git clone https://github.com/Wombat164/claude-flight
cd claude-flight
install -m 0755 bin/flight-claude.sh bin/flight-doctor.sh ~/.local/bin/
```

## 3. Start a session by hand, once

```bash
tmux new-session -d -s flight ~/.local/bin/flight-claude.sh
tmux attach -t flight
```

Accept the trust prompt. Claude prints a `claude.ai/code/session_...` URL --
that is your session, openable from a phone. Detach with `Ctrl-B d`; it keeps
running.

## 4. Pin the conversation

Copy the session id and pin it, so every future restart resumes this same
conversation instead of starting blank:

```bash
echo "<session-uuid>" > ~/.local/state/flight-resume
```

## 5. Install the watchdog

```bash
mkdir -p ~/.config/systemd/user
cp systemd/flight-doctor.{service,timer} ~/.config/systemd/user/
systemctl --user enable --now flight-doctor.timer
loginctl enable-linger "$USER"
```

`enable-linger` is what lets it survive logout and reboot. Skipping it is the
most common reason a deployment quietly stops working.

## 6. Check it

```bash
flight-doctor --selftest
```

```text
flight-doctor --selftest [flight-host-user] (tested against Claude Code 2.1.220):
  [OK  ] tmux session 'flight' present
  [OK  ] claude pid 12890 (comm-filtered)
  [OK  ] resume-pin present
  [OK  ] Claude Code 2.1.220 == tested
  [OK  ] detector regexes match known fixtures
  [OK  ] claude auth status: logged in
RESULT: HEALTHY
```

## 7. Break it on purpose

This is the part worth doing. Destroy the whole tmux server and walk away:

```bash
tmux kill-server
```

Do not relaunch it. Within about a minute the timer fires and the session comes
back on its own, resuming your pinned conversation. Confirm:

```bash
tmux has-session -t flight && echo recovered
pgrep -af "claude --remote-control"     # note the --resume <uuid>
```

If it does *not* come back and instead loops, you have hit the cgroup trap:
see [Run it under systemd](../how-to/run-under-systemd).

## Next

- [Configuration](../reference/configuration) to tune it.
- [Safety model](../explanation/safety-model) before you leave it unattended.
