#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <result-bundle-path> <report-directory>" >&2
  exit 64
fi

result_bundle="$1"
report_directory="$2"

if [[ ! -d "$result_bundle" ]]; then
  echo "No result bundle was produced at $result_bundle" >&2
  exit 0
fi

mkdir -p "$report_directory"

# Export failures must not replace the original xcodebuild failure. The raw
# .xcresult is uploaded alongside these human-reviewable derivatives.
if ! xcrun xcresulttool get test-results summary \
  --path "$result_bundle" \
  --compact > "$report_directory/summary.json"; then
  echo "Unable to export test summary from $result_bundle" >&2
fi

if ! xcrun xcresulttool get test-results tests \
  --path "$result_bundle" \
  --compact > "$report_directory/tests.json"; then
  echo "Unable to export test details from $result_bundle" >&2
fi

if ! xcrun xcresulttool export attachments \
  --path "$result_bundle" \
  --output-path "$report_directory/attachments"; then
  echo "No XCTest attachments were exportable from $result_bundle" >&2
fi

if ! xcrun xcresulttool export diagnostics \
  --path "$result_bundle" \
  --output-path "$report_directory/diagnostics"; then
  echo "No diagnostics were exportable from $result_bundle" >&2
fi
