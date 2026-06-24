#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Acceptance test in a CLEAN container -- a fresh forker's first run. Installs ONLY
# the documented deps on a chosen base image, then runs the whole suite (including
# the REAL-tmux live test) + the gates. Validates that a from-scratch install on a
# stated-supported platform actually works. Needs podman or docker.
#   ci/container-test.sh [debian:stable-slim | alpine:latest | fedora:latest]
set -uo pipefail
IMG="${1:-debian:stable-slim}"
ENG="$(command -v podman || command -v docker || true)"
[ -n "$ENG" ] || { echo "need podman or docker"; exit 1; }
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
case "$IMG" in
  alpine*) deps="apk add --no-cache bash coreutils iproute2 util-linux procps grep gawk sed tmux curl git" ;;
  fedora*) deps="dnf install -y bash coreutils iproute procps-ng util-linux grep gawk sed tmux curl git" ;;
  *)       deps="apt-get update -qq && apt-get install -y -qq bash coreutils iproute2 util-linux procps grep gawk sed tmux curl git" ;;
esac
echo "== container acceptance test on $IMG =="
"$ENG" run --rm -v "$root":/app:ro -w /app "$IMG" sh -ec "
  $deps >/dev/null 2>&1
  echo \"deps: bash \$(bash --version | head -1 | grep -oE '[0-9]+([.][0-9]+)+') | tmux \$(tmux -V) | ss \$(command -v ss || echo MISSING) | flock \$(command -v flock || echo MISSING)\"
  bash bin/flight-doctor.test.sh             | tail -1
  bash bin/flight-doctor.integration.test.sh | tail -1
  bash bin/flight-doctor.live.test.sh        | tail -1
  echo -n 'dry --selftest (no session, fresh install): '
  FLIGHT_CONF=/dev/null bash bin/flight-doctor.sh --selftest 2>&1 | tail -1 || true
"

