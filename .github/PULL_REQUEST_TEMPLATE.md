## What this changes


## Why


## Checklist
- [ ] `bin/flight-doctor.test.sh` + `bin/flight-doctor.integration.test.sh` pass
- [ ] `bin/flight-doctor.live.test.sh` passes (real tmux), if you have tmux
- [ ] `shellcheck --severity=warning bin/*.sh hooks/*.sh ci/*.sh` is clean
- [ ] `ci/leak-check.sh` + `ci/check-scaffolding.sh` pass (the pre-push hook enforces the leak gate)
- [ ] Docs updated (README / SECURITY.md) if behaviour changed
- [ ] ASCII-only; no secrets or deployment-private identifiers
