#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: run-two-simulator-contract.sh \
  <partner-a-destination> <partner-b-destination> \
  <result-root> <derived-data-path>
USAGE
}

if [[ $# -ne 4 ]]; then
  usage
  exit 64
fi

destination_a="$1"
destination_b="$2"
result_root="$3"
derived_data="$4"

udid_a="${destination_a##*id=}"
udid_b="${destination_b##*id=}"
if [[ -z "$udid_a" || -z "$udid_b" || "$udid_a" == "$udid_b" ]]; then
  echo "The two-simulator contract requires two distinct exact UDIDs." >&2
  exit 64
fi

# shellcheck source=scripts/qa/live-contract-admin.sh
source scripts/qa/live-contract-admin.sh
we_qa_admin_initialize

# Keep the service role in this host shell only. It is not exported under its
# saved name, and the workflow variable is gone before xcodebuild starts.
unset WE_QA_SUPABASE_SERVICE_ROLE_KEY
unset TEST_RUNNER_WE_QA_SUPABASE_SERVICE_ROLE_KEY

partner_a_pid=""
partner_a_id=""
partner_b_id=""
couple_id=""

cleanup() {
  if [[ -n "$partner_a_pid" ]]; then
    kill "$partner_a_pid" >/dev/null 2>&1 || true
    wait "$partner_a_pid" >/dev/null 2>&1 || true
  fi
  we_qa_admin_delete_couple "$couple_id"
  we_qa_admin_delete_user "$partner_b_id"
  we_qa_admin_delete_user "$partner_a_id"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

we_qa_admin_create_user two-sim a "Two Simulator A"
partner_a_id="$WE_QA_CREATED_USER_ID"
partner_a_email="$WE_QA_CREATED_USER_EMAIL"
partner_a_password="$WE_QA_CREATED_USER_PASSWORD"

we_qa_admin_create_user two-sim b "Two Simulator B"
partner_b_id="$WE_QA_CREATED_USER_ID"
partner_b_email="$WE_QA_CREATED_USER_EMAIL"
partner_b_password="$WE_QA_CREATED_USER_PASSWORD"

# Pair through the public authenticated RPCs. The service role is used only
# for identity lifecycle and readiness polling, never for relationship acts.
we_qa_user_sign_in "$partner_a_email" "$partner_a_password"
partner_a_access_token="$WE_QA_USER_ACCESS_TOKEN"
we_qa_user_create_couple "$partner_a_access_token"
couple_id="$WE_QA_CREATED_COUPLE_ID"
join_code="$WE_QA_CREATED_JOIN_CODE"

we_qa_user_sign_in "$partner_b_email" "$partner_b_password"
partner_b_access_token="$WE_QA_USER_ACCESS_TOKEN"
we_qa_user_join_couple "$partner_b_access_token" "$join_code"
unset partner_a_access_token partner_b_access_token WE_QA_USER_ACCESS_TOKEN

capture_text="Two simulator capture ${WE_QA_ADMIN_RUN_SLUG}"
ready_text="Two simulator ready ${WE_QA_ADMIN_RUN_SLUG}"
project_path="WE/WE.xcodeproj"
scheme="WE Live Contract"
test_plan="WE Live Contract"
packages_path="${WE_QA_CLONED_PACKAGES_DIR:-artifacts/swift-packages}"

mkdir -p "$result_root" "$derived_data" "$packages_path"
result_a="$result_root/partner-a.xcresult"
result_b="$result_root/partner-b.xcresult"
log_a="$result_root/partner-a.log"
log_b="$result_root/partner-b.log"
build_log="$result_root/build-for-testing.log"

for bundle in "$result_a" "$result_b"; do
  if [[ -e "$bundle" ]]; then
    echo "Result bundle already exists: $bundle" >&2
    exit 73
  fi
done

echo "Building the two-simulator host test once."
set +e
NSUnbufferedIO=YES xcodebuild \
  -project "$project_path" \
  -scheme "$scheme" \
  -testPlan "$test_plan" \
  -destination "$destination_a" \
  -destination-timeout 120 \
  -derivedDataPath "$derived_data" \
  -clonedSourcePackagesDirPath "$packages_path" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:WETests/FieldTwoSimulatorContractTests \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build-for-testing 2>&1 | tee "$build_log"
build_status="${PIPESTATUS[0]}"
set -e
if [[ "$build_status" -ne 0 ]]; then
  exit "$build_status"
fi

xctestrun_path="$(
  find "$derived_data/Build/Products" \
    -type f -name '*.xctestrun' -print -quit
)"
if [[ -z "$xctestrun_path" ]]; then
  echo "build-for-testing did not produce an .xctestrun file." >&2
  exit 66
fi

run_role() {
  local destination="$1"
  local selector="$2"
  local result_bundle="$3"
  local log_path="$4"
  local email="$5"
  local password="$6"

  set +e
  env \
    -u WE_QA_SUPABASE_SERVICE_ROLE_KEY \
    -u TEST_RUNNER_WE_QA_SUPABASE_SERVICE_ROLE_KEY \
    "TEST_RUNNER_WE_QA_SUPABASE_URL=$WE_QA_SUPABASE_URL" \
    "TEST_RUNNER_WE_QA_SUPABASE_ANON_KEY=$WE_QA_SUPABASE_ANON_KEY" \
    "TEST_RUNNER_WE_QA_RUN_ID=$WE_QA_RUN_ID" \
    "TEST_RUNNER_WE_QA_TWO_SIM_CAPTURE_TEXT=$capture_text" \
    "TEST_RUNNER_WE_QA_TWO_SIM_READY_TEXT=$ready_text" \
    "TEST_RUNNER_WE_QA_PARTNER_A_EMAIL=$email" \
    "TEST_RUNNER_WE_QA_PARTNER_A_PASSWORD=$password" \
    "TEST_RUNNER_WE_QA_PARTNER_B_EMAIL=$email" \
    "TEST_RUNNER_WE_QA_PARTNER_B_PASSWORD=$password" \
    NSUnbufferedIO=YES \
    xcodebuild \
      -xctestrun "$xctestrun_path" \
      -destination "$destination" \
      -destination-timeout 120 \
      -resultBundlePath "$result_bundle" \
      -parallel-testing-enabled NO \
      -maximum-concurrent-test-simulator-destinations 1 \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 180 \
      -maximum-test-execution-time-allowance 180 \
      "-only-testing:$selector" \
      test-without-building 2>&1 | tee "$log_path"
  local role_status="${PIPESTATUS[0]}"
  set -e
  return "$role_status"
}

echo "Starting Partner A's witness on simulator $udid_a."
run_role \
  "$destination_a" \
  "WETests/FieldTwoSimulatorContractTests/testPartnerAWitnessesPartnerBCaptureOverRealtime" \
  "$result_a" \
  "$log_a" \
  "$partner_a_email" \
  "$partner_a_password" &
partner_a_pid="$!"

# A writes the ready row only after Realtime reports SUBSCRIBED. Polling that
# row on the host gives B an event-ordering barrier without a guessed delay.
ready="false"
for _ in $(seq 1 120); do
  if ! kill -0 "$partner_a_pid" >/dev/null 2>&1; then
    set +e
    wait "$partner_a_pid"
    partner_a_status="$?"
    set -e
    partner_a_pid=""
    echo "Partner A exited before publishing the readiness barrier." >&2
    if [[ "$partner_a_status" -eq 0 ]]; then
      exit 1
    fi
    exit "$partner_a_status"
  fi
  if we_qa_admin_capture_exists "$couple_id" "$ready_text"; then
    ready="true"
    break
  fi
  sleep 1
done

if [[ "$ready" != "true" ]]; then
  echo "Timed out waiting for Partner A's Realtime readiness barrier." >&2
  exit 1
fi

echo "Starting Partner B's write on distinct simulator $udid_b."
set +e
run_role \
  "$destination_b" \
  "WETests/FieldTwoSimulatorContractTests/testPartnerBWritesCaptureAsPartnerB" \
  "$result_b" \
  "$log_b" \
  "$partner_b_email" \
  "$partner_b_password"
partner_b_status="$?"
if [[ "$partner_b_status" -ne 0 ]]; then
  kill "$partner_a_pid" >/dev/null 2>&1 || true
fi
wait "$partner_a_pid"
partner_a_status="$?"
partner_a_pid=""
set -e

if [[ "$partner_a_status" -ne 0 || "$partner_b_status" -ne 0 ]]; then
  echo "Two-simulator contract failed (A=$partner_a_status, B=$partner_b_status)." >&2
  exit 1
fi

echo "Two distinct simulator-hosted clients proved B-attributed Realtime arrival."
