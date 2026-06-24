#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# macOS shim test -- runs ONLY on Darwin (skips elsewhere). Validates that the
# portability shims (lsof-based rc_conns, BSD `stat -f` mtime, the comm filter)
# actually execute on a real Mac -- coverage the Linux + mocked suites cannot give.
# Run it with the SYSTEM BSD tools on PATH (not Homebrew coreutils) so it exercises
# the FALLBACK paths; it still needs bash 4.4+ (Homebrew bash). The macos-runtime CI
# job runs it on a real macos-latest runner.
set -uo pipefail
[ "$(uname -s)" = Darwin ] || { echo "SKIP: not macOS"; exit 0; }
HERE="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0
ok(){ echo "  ok   $1"; pass=$((pass+1)); }
no(){ echo "  FAIL $1"; fail=$((fail+1)); }

FLIGHT_CONF=/dev/null FLIGHT_DOCTOR_LIB=1 . "$HERE/flight-doctor.sh" >/dev/null 2>&1

echo "== macOS portability shims (real Darwin) =="
[ "${IS_MAC:-0}" = 1 ] && ok "IS_MAC detected on Darwin" || no "IS_MAC not set on Darwin"
command -v lsof >/dev/null 2>&1 && ok "lsof present (the ss replacement)" || no "lsof MISSING"

# _mtime must work via BSD `stat -f` (GNU `stat -c` is absent here).
m="$(_mtime "$HERE/flight-doctor.sh")"
case "$m" in ''|*[!0-9]*) no "_mtime non-numeric ('$m')" ;; *) [ "$m" -gt 0 ] && ok "_mtime via BSD stat -f works ($m)" || no "_mtime zero" ;; esac

# rc_conns must run the lsof path without error and return a non-negative integer.
r="$(rc_conns "$$")"
case "$r" in ''|*[!0-9]*) no "rc_conns (lsof path) non-numeric ('$r')" ;; *) ok "rc_conns lsof path returns an int ($r)" ;; esac

# the mkdir-lock fallback (used when flock is absent, i.e. stock macOS) is atomic.
ld="$(mktemp -d)/lock.d"
if mkdir "$ld" 2>/dev/null && ! mkdir "$ld" 2>/dev/null; then ok "mkdir lock is atomic (second acquire fails)"; else no "mkdir lock not atomic"; fi
rmdir "$ld" 2>/dev/null || true

echo "==================================================="
echo "MACOS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
