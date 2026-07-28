---
title: claude-flight
---

A persistent, remote-controllable **Claude Code** session you leave running on an
always-on box, plus **`flight-doctor`**, the watchdog that keeps it healthy
without you.

> [!warning]
> `flight-doctor` **auto-approves shell commands an LLM proposes**, holding back
> only what matches a denylist *you* must complete for your environment. A
> denylist is never complete. Read [Safety model](explanation/safety-model) and
> [SECURITY.md](https://github.com/Wombat164/claude-flight/blob/main/SECURITY.md)
> before pointing this at anything you cannot afford to lose.

## Start here

- [Getting started](tutorials/getting-started) -- install it and watch it heal something.
- [Run it under systemd](how-to/run-under-systemd) -- the deployment that actually survives a reboot.
- [Configuration](reference/configuration) -- every environment variable.
- [Why not just a supervisor?](explanation/why-not-a-supervisor) -- what this does that systemd cannot.

## What it actually does

A bare `claude --remote-control` session inside tmux survives detach, sleep and
crashes. It does not survive the interesting failures:

| Failure | What a supervisor sees | What flight-doctor does |
|---|---|---|
| Remote Control websocket drops while idle | a healthy process | counts outbound `:443` sockets, restarts on zero |
| Tool call wedges | a healthy process | detects no-child + flat CPU + frozen frame, kill+resume |
| Permission gate blocks forever | a healthy process | approves routine, **holds catastrophic** |
| API outage | a healthy process | declines to restart, because restarting cannot help |
| Credential expired | a healthy process | escalates and names `/login` |
| Host rebooted, no tmux server | nothing to restart | relaunches into its own scope |

Every recovery is lossless: a pinned conversation id means a restart resumes the
*same* conversation.

## The docs, by shape

- **[Tutorials](tutorials/)** -- learning-oriented. Follow along and it works.
- **[How-to](how-to/)** -- task-oriented. You have a problem; this solves it.
- **[Reference](reference/)** -- information-oriented. Look something up.
- **[Explanation](explanation/)** -- understanding-oriented. Why it is built this way.

When these pages and the script disagree, the script wins. Behaviour here should
be traceable to `bin/flight-doctor.sh` or an assertion in the test suites.
