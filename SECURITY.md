# Security model

flight-doctor exists to keep an **unattended** Claude Code session alive and
unblock it. That convenience is also its risk surface. Read this before running
it on anything you care about.

## The one thing to understand

**Auto-approval is not a security boundary.** flight-doctor approves any
permission prompt that does **not** match a catastrophic denylist (`MUTATION_RE`).
A denylist is, by definition, incomplete: it can only block what its author
thought to list. Anything it does not recognize as catastrophic is run. So the
real control is not the denylist -- it is *what you point this at*.

Corollary: the denylist shipped here is tuned for one author's environment. It
names tool **classes** (cluster teardown, cloud-infra destruction, disk/network
ops, data-loss git, pipe-to-shell, package purges). **Yours will differ.** Before
unattended use, add the destructive commands specific to your stack -- WITHOUT
editing the script: drop regexes (one ERE per line) into `~/.config/flight-denylist`
(see `flight-denylist.example`), or set `FLIGHT_MUTATION_EXTRA`. Both are OR'd into
the built-in list. Treat the defaults as a starting point, not coverage.

## Privilege level: the biggest blast-radius lever -- and a real trade-off

Because the denylist is incomplete, the **OS privileges of the user the session
runs as** are the biggest lever on how much a bad call (or a hijacked agent) can
do. But privilege is also *why many people run this* -- a remote, sudo-capable dev
box you drive from your phone. So pick a level deliberately for your threat model;
this is a trade-off, not a commandment.

**Running as a standard / privileged user (even as yourself) is a legitimate
choice when:**
- it is a single-user box you own and administer,
- you accept the blast radius (the agent can already reach anything you can), and
- the agent's actual job needs that access -- it *is* your remote dev / jump-shell.

This is a common, primary use case; the reference deployment runs this way on
purpose. A dedicated user wouldn't even protect your `~/repos` when working in
`~/repos` is the whole point.

**Prefer a dedicated, least-privilege user when any of these holds:**
- the host is shared / multi-user, or holds other people's data;
- production secrets, credentials, or a path to lateral movement live on it;
- you want to contain a *compromised or prompt-injected* agent (this applies to
  almost anyone exposing a session -- see the injection notes below).

**If you isolate, the baseline:** a dedicated unprivileged user (own home,
`loginctl enable-linger`); **no blanket sudo, no `docker`/`wheel`/`adm` groups**
(docker is root-equivalent); a narrow `sudoers` NOPASSWD entry per specific
command if truly needed; scoped credentials (K8s `Role` not cluster-admin,
project-scoped cloud tokens, read-only secret tokens); optional systemd hardening
(`NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`).

**Whatever level you choose, these cost nothing and matter most against a hijacked
agent:** keep the Remote Control URL secret; **restrict egress** so an injected
agent cannot freely exfiltrate or phone home; keep the denylist as defense-in-depth;
alert on holds; and don't co-locate unrelated secrets on the box. Privilege caps
*how much* a compromise can touch; egress control caps *where it can go*; the
denylist catches the obvious. Dial each to what your threat model warrants -- and
note that egress restriction lets you keep a privileged dev box and still contain
an injection.

> The reference deployment intentionally runs as a sudo-capable user because the
> session doubles as the operator's own infra jump-shell -- a deliberate,
> owner-accepted exception, not the recommended default. Make that trade-off
> consciously for your own deployment.

## Preconditions you accept by running it unattended

- A long-running, possibly **sudo-capable** agent will execute commands an LLM
  proposes, without a human in the loop for anything off the denylist.
- The session is reachable from wherever its Remote Control channel is open.
- You are comfortable with the blast radius of the account/host it runs as.

If any of those is not acceptable, do not run it unattended -- run `flight-doctor`
by hand (it is idempotent), or do not auto-approve at all.

## Specific risks and mitigations

- **Denylist evasion.** The catastrophic match runs on a *wrap-joined* pane
  capture so a long command cannot hide a dangerous token across a line break.
  This narrows evasion; it does not eliminate the incompleteness above.
- **Pane content is untrusted input.** Gate decisions read terminal text, which
  can include arbitrary tool output, file contents, or fetched web pages -- a
  prompt-injection surface. The socket-based liveness checks are *not*
  pane-derived and cannot be spoofed this way; the gate/auth/catastrophic
  *string* checks can be influenced by content. Two consequences seen in
  practice (this design is informed by a real prompt-injection incident):
    - **False holds (DoS).** Content that merely contains `Please run /login`
      can trip the auth-hold and stall the watchdog. The fix in progress is to
      corroborate with a structured signal (`claude auth status --json`, exit
      0/1) rather than trust the string alone.
    - **Hidden-instruction / homoglyph tricks.** Treat newly-arrived content as
      untrusted by provenance; be aware that zero-width or control characters can
      be used to hide or split a token. The catastrophic match strips quotes and
      joins wrapped lines; a fuller normalization (stripping zero-width/control
      chars) is a planned hardening.
- **Roadmap: prefer structured signals over scraping.** Claude Code now exposes
  machine-readable signals (`claude auth status --json`, `Notification`/`Stop`/
  `StopFailure` hooks, `history.jsonl` progress) that are immune to TUI
  restyling. Migrating the fragile string checks onto these (with pane-scraping
  as a guarded fallback plus a `--selftest` drift canary) is the durable fix for
  both UI drift and the injection surface above.
- **The ntfy alert topic is a bearer capability.** Anyone who learns the topic
  can read your alerts and post fakes. Alerts are off by default; when enabled,
  bodies are kept generic (no session URL, tokens, or pane dumps). Prefer an
  authenticated or self-hosted ntfy for anything sensitive.
- **The Remote Control URL is reach-to-control.** Treat the
  `claude.ai/code/session_...` URL like a credential; never paste it into shared
  logs, screenshots, or issues.
- **Config secrecy.** Site-specific values (including any private ntfy topic)
  live in an untracked config file, never in the script. Keep it `chmod 600` and
  out of version control (`.gitignore` excludes `*.conf`).

## Known limitation: TUI-string drift

Detection of trust prompts, permission gates, "waiting"/stalled states, and login
failures relies on **undocumented Claude Code TUI strings**. A future Claude Code
release can change these and silently disable a healer with no error. Pin/track
the Claude Code version you have validated against, and re-check after upgrades.
Run `flight-doctor --selftest` -- a read-only drift canary that flags a version
change, a regex that stopped matching its known fixture, hooks that stopped
firing, or a lost auth, with a HEALTHY/WARNING/CRITICAL rollup.

## Reporting

This is a small, single-maintainer project provided as-is under the MIT license
(no warranty). If you find a security issue, please open an issue describing it
without including any sensitive values.
