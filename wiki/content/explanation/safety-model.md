---
title: Safety model
---

> [!warning]
> Auto-approval is **not a security boundary**. The real boundary is the OS
> privilege of the user the session runs as. Read
> [SECURITY.md](https://github.com/Wombat164/claude-flight/blob/main/SECURITY.md)
> in full before running this unattended.

## What the envelope is

An AI coding agent is a *copilot* when every action needs a hand on the yoke. It
edges toward *pilot* the way aviation autopilots earned trust: not by being
smarter, but by **envelope protection** -- hard limits it cannot cross, and a
human it pages when something nears the edge.

`flight-doctor` is that envelope. Routine actions proceed. Catastrophic ones are
held. The agent is stood down when continuing would do harm. The guardrails are
what *buy* the autonomy.

They buy it; they do not guarantee it.

## Why a denylist is the weak part

The catastrophic check is a regex denylist (`MUTATION_RE`, plus
`FLIGHT_MUTATION_EXTRA` and `FLIGHT_DENYLIST_FILE`). A denylist enumerates the
bad, which means it is **never complete**. The built-in entries are defaults
tuned to one environment; yours will differ.

This project has shipped, and then fixed, denylist bypasses. Two that are worth
understanding because they generalise:

- **Line-break evasion.** A command wrapped across lines in the pane did not
  match a regex written for one line. The fix was to match against a
  wrap-joined pane, not the raw capture.
- **Collapsed gates.** A gate can render collapsed, hiding the dangerous part of
  the command from the scrape. The fix was to expand before deciding.

Both were cases where the *text the detector saw* differed from the *command
that would run*. When you extend the denylist, assume that gap exists and look
for it.

## Two-signal gating

Where a detector can be fooled by pane text alone, it is corroborated against
something structural:

- an auth-looking pane is confirmed with `claude auth status`
- a gate decision is made on the expanded, wrap-joined pane
- a crash loop is corroborated against process age, because the exit banner it
  looks for is ordinary text that appears whenever someone reads the launcher
  source on screen

That last one was a real false-positive found in review: this project gets
developed inside a flight session, so viewing its own launcher would have fired
an urgent alert. Pane text is evidence, not proof.

## What it will not do

It never approves what matches the denylist -- it reports and alerts instead. It
never restarts into a wall it knows about: an outage or an expired credential
produces a hold. It never writes state under `--status`.

## Deploying it responsibly

- Run it as a user with the least privilege that still lets the work happen. The
  privilege of that user is your actual blast radius.
- Complete the denylist for *your* environment before going unattended.
- Treat the ntfy topic as a bearer credential: anyone who learns it reads your
  alerts and can post convincing fakes.
- Point `FLIGHT_ALERT_CLICK` at an auth-gated out-of-band terminal, never the
  session URL -- alerts often fire precisely when Remote Control is down, and
  the session URL is itself a credential.
- Do not point this at a host, account, or data you cannot afford to lose.
