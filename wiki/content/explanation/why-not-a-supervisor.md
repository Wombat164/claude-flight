---
title: Why not just a supervisor?
---

Use systemd, supervisord, monit or a Kubernetes probe for what they are good at.
`flight-doctor` sits a layer above them, and in fact runs *under* a systemd
timer.

## What a supervisor can restart

A supervisor restarts a **dead process**. That is a sharp, reliable signal, and
if that is your failure mode you do not need this project.

The failures that matter here leave the process **alive**:

- the Remote Control websocket drops after a long idle -- the process is fine,
  the channel is gone
- a tool call wedges -- the process is fine, it is waiting forever
- a permission gate blocks -- the process is fine, it is waiting for a human
- the API has an outage -- the process is fine, and restarting makes it worse
- the credential expired -- the process is fine, and restarting makes it worse

A liveness probe sees a healthy process in all five cases and does nothing. That
is not a flaw in the probe; the failure is above the layer it observes.

## Three genuinely different behaviours

**It heals a live process whose channel died.** Detection is socket truth: count
outbound `:443` connections while idle. Zero means the websocket is gone even
though the process is healthy. No supervisor has a reason to look at that.

**It declines to restart when a restart cannot help.** This is the inverse of
"always restart". An outage probe and an auth check gate the recovery ladder, so
an outage produces a hold, not a thrash. A circuit breaker stops a flapping
channel from becoming a restart loop.

**It answers a semantic UI prompt.** A permission gate is a question in a TUI.
Approving the routine ones is what makes unattended operation possible at all;
holding the catastrophic ones is what makes it survivable. No process supervisor
models "should this command be allowed".

## Where the boundary sits

| Concern | Owner |
|---|---|
| process is dead, restart it | systemd |
| run me every 60 seconds | systemd timer |
| survive logout and reboot | `loginctl enable-linger` |
| the session exists at all | flight-doctor (relaunch) |
| the channel is alive | flight-doctor (socket truth) |
| the UI is not stuck | flight-doctor (wedge, stall) |
| this command is safe to approve | flight-doctor (denylist) -- and see [Safety model](safety-model) |
| a human is needed | flight-doctor (holds and alerts) |

The one thing to take away if you build your own: **the useful question is not
"is it running" but "is it making progress, and would restarting help".**
