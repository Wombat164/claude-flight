#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Scaffolding + completeness gate: required files present; shell scripts carry an
# SPDX header, are executable, and parse; README has the load-bearing sections;
# example files are placeholders (not real values). Runs in CI and locally:
#   ci/check-scaffolding.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo"; exit 2; }
rc=0
fail(){ echo "FAIL: $1"; rc=1; }

req=(README.md LICENSE SECURITY.md .gitignore
     bin/flight-doctor.sh bin/flight-claude.sh
     bin/flight-doctor.test.sh bin/flight-doctor.integration.test.sh
     bin/flight-doctor.live.test.sh bin/flight-doctor.live-claude.test.sh
     hooks/flight-notify.sh hooks/flight-hooks.json.example
     flight-doctor.conf.example flight-denylist.example
     systemd/flight-doctor.service systemd/flight-doctor.timer
     assets/logo.svg .github/workflows/ci.yml)
for f in "${req[@]}"; do [ -f "$f" ] || fail "missing required file: $f"; done

for f in bin/*.sh hooks/*.sh ci/*.sh; do
  [ -f "$f" ] || continue
  head -3 "$f" | grep -q 'SPDX-License-Identifier' || fail "no SPDX header: $f"
  [ -x "$f" ] || fail "not executable: $f"
  bash -n "$f" || fail "syntax error: $f"
done

for s in '## Quickstart' '## Install' '## Deployment profiles' '## Compatibility' '## Security considerations' '## License'; do
  grep -qF "$s" README.md || fail "README missing section: $s"
done
grep -q 'SECURITY.md' README.md || fail "README does not link SECURITY.md"
grep -q 'assets/logo.svg' README.md || fail "README does not reference the logo"

# example files must stay placeholders, never carry real values
grep -qiE 'ntfy\.sh/(CHANGE|<)' flight-doctor.conf.example || fail "conf.example: ntfy topic is not a CHANGE-ME placeholder"

[ "$rc" -eq 0 ] && echo "scaffolding: complete"
exit "$rc"
