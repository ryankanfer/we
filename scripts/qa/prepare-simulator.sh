#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "usage: $0 <device-name> <iOS-runtime-version> <standard|accessibility>" >&2
}

if [[ $# -ne 3 ]]; then
  usage
  exit 64
fi

device_name="$1"
runtime_version="$2"
profile="$3"

case "$profile" in
  standard|accessibility) ;;
  *)
    usage
    exit 64
    ;;
esac

for command_name in xcrun jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "required command is unavailable: $command_name" >&2
    exit 69
  fi
done

runtime_identifier="$(
  xcrun simctl list --json runtimes |
    jq -r --arg version "$runtime_version" \
      '[.runtimes[]
        | select(.isAvailable == true and .version == $version)
        | .identifier][0] // empty'
)"

if [[ -z "$runtime_identifier" ]]; then
  echo "iOS Simulator runtime $runtime_version is not installed." >&2
  xcrun simctl list runtimes >&2
  exit 69
fi

device_type_identifier="$(
  xcrun simctl list --json devicetypes |
    jq -r --arg name "$device_name" \
      '[.devicetypes[]
        | select(.name == $name)
        | .identifier][0] // empty'
)"

if [[ -z "$device_type_identifier" ]]; then
  echo "Simulator device type '$device_name' is not installed." >&2
  xcrun simctl list devicetypes >&2
  exit 69
fi

run_id="${GITHUB_RUN_ID:-local}"
run_attempt="${GITHUB_RUN_ATTEMPT:-1}"
job_name="${GITHUB_JOB:-qa}"
simulator_name="WE QA ${job_name} ${device_name} ${run_id}-${run_attempt} ${profile}"
udid="$(xcrun simctl create \
  "$simulator_name" \
  "$device_type_identifier" \
  "$runtime_identifier")"

cleanup_on_error() {
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$udid" >/dev/null 2>&1 || true
}
trap cleanup_on_error ERR

xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b

# Keep locale, text sizing, motion, and transparency explicit. A fresh
# simulator avoids state leaking between jobs; the accessibility profile
# deliberately combines the most layout-stressing settings.
xcrun simctl spawn "$udid" defaults write NSGlobalDomain AppleLanguages -array en
xcrun simctl spawn "$udid" defaults write NSGlobalDomain AppleLocale -string en_US
xcrun simctl ui "$udid" appearance light
xcrun simctl ui "$udid" increase_contrast disabled

if [[ "$profile" == "accessibility" ]]; then
  xcrun simctl ui "$udid" content_size accessibility-extra-extra-extra-large
  xcrun simctl spawn "$udid" defaults write \
    com.apple.Accessibility ReduceMotionEnabled -bool true
  xcrun simctl spawn "$udid" defaults write \
    com.apple.Accessibility ReduceTransparencyEnabled -bool true
else
  xcrun simctl ui "$udid" content_size large
  xcrun simctl spawn "$udid" defaults write \
    com.apple.Accessibility ReduceMotionEnabled -bool false
  xcrun simctl spawn "$udid" defaults write \
    com.apple.Accessibility ReduceTransparencyEnabled -bool false
fi

# SpringBoard reads some accessibility defaults only during startup.
xcrun simctl shutdown "$udid"
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcrun simctl status_bar "$udid" override \
  --time 9:41 \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularBars 4

destination="platform=iOS Simulator,id=$udid"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "udid=$udid"
    echo "destination=$destination"
  } >> "$GITHUB_OUTPUT"
fi

echo "Prepared $device_name on iOS $runtime_version ($profile): $udid"
echo "$destination"

trap - ERR
