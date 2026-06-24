#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Secret + identity leak gate. Fails (exit 1) if any deployment-private identifier
# or secret-shaped token appears in tracked files. Runs in CI and locally:
#   ci/leak-check.sh
# Scans only tracked files (git grep), and EXCLUDES itself (it necessarily
# contains the very patterns it hunts for).
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo"; exit 2; }
rc=0
EXC=(':!ci/leak-check.sh')

scan(){ # scan "LABEL" "ERE"
  local out; out="$(git grep -IEni "$2" -- . "${EXC[@]}" 2>/dev/null || true)"
  [ -n "$out" ] && { echo ">>> LEAK ($1):"; echo "$out"; rc=1; }
}

# 1. estate-private identifiers (this tool was extracted from a private estate)
scan "estate identifier" 'vdhome|lron-rcde-[0-9]|teleport\.vdhome|rcde-hub|lron-hub|\bvdhoeven\b|\bmathias\b'
# 2. real personal/estate emails
scan "real email" '[A-Za-z0-9._%+-]+@(vdhome\.be|gmail\.com)'
# 3. secret-shaped tokens
scan "secret token" 'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|sk-[A-Za-z0-9]{20,}'
# 4. real Claude Code session URLs (the FORMAT reference session_... / session_[A-Za-z0-9]+
#    is fine; a real one carries a long id)
scan "session URL" 'session_[A-Za-z0-9]{16,}'

# 5. real (non-documentation) IPv4 -- RFC5737 / loopback / test-fixture IPs are allowed
ips="$(git grep -IEon '([0-9]{1,3}\.){3}[0-9]{1,3}' -- . "${EXC[@]}" 2>/dev/null \
       | grep -vE '(192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|127\.0\.0\.1|1\.2\.3\.4|5\.6\.7\.8|0\.0\.0\.0|255\.255\.255)' || true)"
[ -n "$ips" ] && { echo ">>> LEAK (non-documentation IP):"; echo "$ips"; rc=1; }

[ "$rc" -eq 0 ] && echo "leak-check: clean"
exit "$rc"
