# Contributing

Small project, simple flow.

## Branches

- **`main`** — the release branch (what people clone). Keep it green + clean.
- **`dev`** — work-in-progress. Land changes here, then merge to `main` for a release.

```sh
git switch dev          # or: git switch -c dev
# ...work, commit...
git push origin dev     # WIP
# when ready to release:
git switch main && git merge --no-ff dev && git push origin main
```

## Enable the local gates (once per clone)

A versioned **pre-push hook** refuses to push if the secret/identity leak gate
trips, so nothing private can reach the remote:

```sh
git config core.hooksPath ci/hooks
```

You can also run the gates by hand anytime:

```sh
ci/leak-check.sh          # secret + estate-identifier scan
ci/check-scaffolding.sh   # required files / SPDX / README sections
```

## Tests

```sh
bin/flight-doctor.test.sh              # unit (mocked)
bin/flight-doctor.integration.test.sh  # if-ladder vs stub tmux/pgrep/ss/curl/claude
bin/flight-doctor.live.test.sh         # LIVE vs REAL tmux (fake pane) -- needs tmux
FLIGHT_LIVE_CLAUDE=1 \
  bin/flight-doctor.live-claude.test.sh  # opt-in: REAL handicapped claude (local only)
```

CI runs lint (shellcheck), the leak + scaffolding gates, the unit/integration/live
suites across Ubuntu/Debian/Fedora (Alpine + macOS best-effort). Keep it green.

Shell style: `shellcheck --severity=warning` clean, `set -uo pipefail`, ASCII only.
