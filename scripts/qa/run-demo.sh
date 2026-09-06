#!/usr/bin/env bash
#
# Build and launch WE on a simulator with one of the demo accounts, and open
# the Simulator window so it can be used by hand.
#
# The zones read entirely from a local fixture in these modes — no network, no
# Supabase, no real couple. Nothing here touches live data.
#
#   scripts/qa/run-demo.sh [account] [simulator-name]
#
#   demo     a couple three months in — the matured account   (default)
#   seeded   the fictional couple — Life's four bands, in full
#   sparse   the same couple in their first week, four items —
#            the only account that shows Life's strata collapsed (§16a)
#   resting  the seeded couple with no question pending — the only account
#            that shows Us as a field (§14d) rather than a question
#   empty    day one: nothing written down at all
#
# Examples:
#   scripts/qa/run-demo.sh
#   scripts/qa/run-demo.sh sparse
#   scripts/qa/run-demo.sh seeded "iPhone 16e"

set -euo pipefail

account="${1:-demo}"
simulator_name="${2:-iPhone 17 Pro Max}"

case "$account" in
  demo | seeded | sparse | resting | empty) ;;
  *)
    echo "unknown account: $account (want: demo, seeded, sparse, resting, empty)" >&2
    exit 64
    ;;
esac

cd "$(dirname "$0")/../.."

project_path="WE/WE.xcodeproj"
scheme="WE Test Account"
bundle_id="com.ryankanfer.WE"
derived_data="${WE_DEMO_DERIVED_DATA:-artifacts/demo-derived-data}"
packages_path="${WE_QA_CLONED_PACKAGES_DIR:-artifacts/swift-packages}"

# Pick the newest available simulator with this name. `simctl list` prints the
# runtime as a section header, so the last match is the newest runtime.
udid="$(
  xcrun simctl list devices available \
    | grep -F "    $simulator_name (" \
    | tail -1 \
    | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/'
)"

if [[ -z "$udid" ]]; then
  echo "no available simulator named \"$simulator_name\"." >&2
  echo "available:" >&2
  xcrun simctl list devices available | grep -E "^    iPhone" | sed 's/^/  /' >&2
  exit 66
fi

echo "Building WE…"
xcodebuild \
  -project "$project_path" \
  -scheme "$scheme" \
  -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$derived_data" \
  -clonedSourcePackagesDirPath "$packages_path" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build >/dev/null

app_path="$derived_data/Build/Products/Debug-iphonesimulator/WE.app"
if [[ ! -d "$app_path" ]]; then
  echo "build produced no app at $app_path" >&2
  exit 70
fi

open -a Simulator --args -CurrentDeviceUDID "$udid" || true
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
xcrun simctl install "$udid" "$app_path"
xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true

# The fictional fixture is written around a fixed Wednesday. Without this the
# seeded dates read as months overdue and every band lands wrong.
export SIMCTL_CHILD_WE_QA_FIXED_NOW="2025-08-13T12:00:00Z"
export SIMCTL_CHILD_WE_REPOSITORY="preview"
export SIMCTL_CHILD_WE_SKIP_PROMISE="1"
export SIMCTL_CHILD_WE_SKIP_WALKTHROUGH="1"
export SIMCTL_CHILD_WE_DISABLE_CREDENTIAL_PROMPTS="1"

case "$account" in
  empty)
    export SIMCTL_CHILD_WE_PREVIEW_SCENARIO="empty"
    ;;
  resting)
    # Seeded material, but no shared journey pending. `WE_FIELD` drives the
    # store; `WE_PREVIEW_SCENARIO` drives the journey, and Us only shows its
    # field when no question is waiting to be answered.
    export SIMCTL_CHILD_WE_FIELD="seeded"
    export SIMCTL_CHILD_WE_PREVIEW_SCENARIO="empty"
    ;;
  *)
    export SIMCTL_CHILD_WE_FIELD="$account"
    ;;
esac

xcrun simctl launch "$udid" "$bundle_id" >/dev/null

echo
echo "WE is running as \"$account\" on $simulator_name."
echo "Tap LIFE in the bar at the bottom to see the strata."
case "$account" in
  seeded) echo "Life here has enough in it to show all four bands." ;;
  sparse) echo "Life here has four things, so the bands collapse (§16a)." ;;
  empty)  echo "Nothing is written down yet — every zone's empty state." ;;
  resting) echo "Us renders as a field here — size is mention frequency." ;;
  demo)   echo "A couple three months in, with a shared question waiting." ;;
esac
