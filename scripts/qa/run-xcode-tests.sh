#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: run-xcode-tests.sh \
  <unit|smoke|full-ui|accessibility|live-contract|widget-goldens> \
  <destination> <result-bundle-path> <derived-data-path>
USAGE
}

if [[ $# -ne 4 ]]; then
  usage
  exit 64
fi

lane="$1"
destination="$2"
result_bundle="$3"
derived_data="$4"

project_path="WE/WE.xcodeproj"
test_plan_path="WE/WE.xctestplan"
scheme="WE Test Account"
test_plan="WE"

if [[ "$lane" == "live-contract" ]]; then
  # Keep host-backed repository tests independent of the UI target and its
  # device-specific golden resources.
  test_plan_path="WE/WE Live Contract.xctestplan"
  scheme="WE Live Contract"
  test_plan="WE Live Contract"
fi

if [[ ! -d "$project_path" ]]; then
  echo "Xcode project not found: $project_path" >&2
  exit 66
fi

if [[ ! -f "$test_plan_path" ]]; then
  echo "Committed test plan not found: $test_plan_path" >&2
  exit 66
fi

if [[ -e "$result_bundle" ]]; then
  echo "Result bundle already exists: $result_bundle" >&2
  exit 73
fi

mkdir -p "$(dirname "$result_bundle")" "$derived_data"

selectors=()
case "$lane" in
  unit)
    selectors+=("-only-testing:WETests")
    ;;
  smoke)
    # This is deliberately a small, serial contract: launch/navigation,
    # day-one capture, correction/send, account deletion reachability, and
    # sign-out. Full UI and visual matrices remain nightly.
    selectors+=(
      "-only-testing:WEUITests/FieldZoneUITests/testZoneNavigationByLabelAndBySwipe"
      "-only-testing:WEUITests/FieldZoneUITests/testUsExplainsItselfBeforeItHoldsAnything"
      "-only-testing:WEUITests/FieldZoneUITests/testForTodayPutsSomethingOnTheClearDay"
      "-only-testing:WEUITests/FieldZoneUITests/testCaptureProducesAReceipt"
      "-only-testing:WEUITests/FieldZoneUITests/testAccountIsReachableAndOffersDeletion"
      "-only-testing:WEUITests/FieldZoneUITests/testSigningOutLeavesTheZones"
      "-only-testing:WEUITests/WEUITests/testAAuthRecoveryPairingAndHueRoutes"
    )
    ;;
  full-ui)
    selectors+=("-only-testing:WEUITests")
    ;;
  accessibility)
    selectors+=(
      "-only-testing:WEUITests/FieldZoneUITests/testEmptyUsAtMaximumAccessibilitySettings"
      "-only-testing:WEUITests/FieldZoneUITests/testCriticalZonesPassAccessibilityAudit"
    )
    ;;
  live-contract)
    live_selector="${WE_LIVE_CONTRACT_SELECTOR:-WETests/FieldSupabaseLiveContractTests}"
    selectors+=("-only-testing:$live_selector")
    ;;
  widget-goldens)
    selectors+=(
      "-only-testing:WETests/WEAmbientWidgetGoldenTests/testHomeWidgetContentSurfaces"
    )
    ;;
  *)
    usage
    exit 64
    ;;
esac

log_path="${result_bundle%.xcresult}.log"
packages_path="${WE_QA_CLONED_PACKAGES_DIR:-artifacts/swift-packages}"
mkdir -p "$packages_path"

# xcodebuild intentionally does not copy arbitrary shell variables into the
# XCTest runner. TEST_RUNNER_ is its documented forwarding contract; the
# prefix is stripped before the test process starts.
test_runner_variables=(
  WE_QA_SUPABASE_URL
  WE_QA_SUPABASE_ANON_KEY
  WE_QA_RUN_ID
  WE_QA_PARTNER_A_ID
  WE_QA_PARTNER_A_EMAIL
  WE_QA_PARTNER_A_PASSWORD
  WE_QA_PARTNER_B_ID
  WE_QA_PARTNER_B_EMAIL
  WE_QA_PARTNER_B_PASSWORD
  WE_QA_OUTSIDER_ID
  WE_QA_OUTSIDER_EMAIL
  WE_QA_OUTSIDER_PASSWORD
  WE_QA_TWO_SIM_CAPTURE_TEXT
  WE_QA_TWO_SIM_READY_TEXT
  WE_QA_FIXED_NOW
  WE_QA_DISABLE_ANIMATIONS
  WE_QA_DYNAMIC_TYPE
  WE_QA_REDUCE_TRANSPARENCY
  TZ
)
# A caller cannot opt the service role back into XCTest by pre-populating the
# forwarding prefix. Live coordinators keep that credential on the host.
unset TEST_RUNNER_WE_QA_SUPABASE_SERVICE_ROLE_KEY
for variable_name in "${test_runner_variables[@]}"; do
  if [[ -n "${!variable_name+x}" ]]; then
    export "TEST_RUNNER_${variable_name}=${!variable_name}"
  fi
done

common_arguments=(
  -project "$project_path"
  -scheme "$scheme"
  -testPlan "$test_plan"
  -destination "$destination"
  -destination-timeout 120
  -derivedDataPath "$derived_data"
  -clonedSourcePackagesDirPath "$packages_path"
  -resultBundlePath "$result_bundle"
  -parallel-testing-enabled NO
  -maximum-concurrent-test-simulator-destinations 1
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 180
  -maximum-test-execution-time-allowance 600
  CODE_SIGNING_ALLOWED=NO
  COMPILER_INDEX_STORE_ENABLE=NO
)

echo "Running $lane on $destination"
set +e
NSUnbufferedIO=YES xcodebuild \
  "${common_arguments[@]}" \
  "${selectors[@]}" \
  test 2>&1 | tee "$log_path"
xcode_status="${PIPESTATUS[0]}"
set -e

if [[ "$xcode_status" -ne 0 ]]; then
  echo "$lane failed; inspect $result_bundle and $log_path" >&2
fi

exit "$xcode_status"
