#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "usage: $0 <simulator-udid>" >&2
  exit 64
fi

udid="$1"

# This script is intentionally limited to the exact ephemeral UDID emitted by
# prepare-simulator.sh. Cleanup must never target every simulator on a runner.
xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
if ! xcrun simctl delete "$udid"; then
  echo "Simulator cleanup did not complete for $udid." >&2
fi
