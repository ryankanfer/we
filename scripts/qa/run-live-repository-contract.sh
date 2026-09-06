#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <destination> <result-bundle-path> <derived-data-path>" >&2
  exit 64
fi

destination="$1"
result_bundle="$2"
derived_data="$3"

# shellcheck source=scripts/qa/live-contract-admin.sh
source scripts/qa/live-contract-admin.sh
we_qa_admin_initialize

# Save the host credential in a non-exported shell variable, then remove the
# workflow variable before any build or test subprocess can inherit it.
unset WE_QA_SUPABASE_SERVICE_ROLE_KEY

created_user_ids=()
partner_a_id=""
cleanup_users() {
  local user_id
  we_qa_admin_delete_couples_created_by "$partner_a_id"
  for user_id in "${created_user_ids[@]}"; do
    we_qa_admin_delete_user "$user_id"
  done
}
trap cleanup_users EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

we_qa_admin_create_user repository a "Contract A"
partner_a_id="$WE_QA_CREATED_USER_ID"
partner_a_email="$WE_QA_CREATED_USER_EMAIL"
partner_a_password="$WE_QA_CREATED_USER_PASSWORD"
created_user_ids+=("$partner_a_id")

we_qa_admin_create_user repository b "Contract B"
partner_b_id="$WE_QA_CREATED_USER_ID"
partner_b_email="$WE_QA_CREATED_USER_EMAIL"
partner_b_password="$WE_QA_CREATED_USER_PASSWORD"
created_user_ids+=("$partner_b_id")

we_qa_admin_create_user repository outsider "Contract Outsider"
outsider_id="$WE_QA_CREATED_USER_ID"
outsider_email="$WE_QA_CREATED_USER_EMAIL"
outsider_password="$WE_QA_CREATED_USER_PASSWORD"
created_user_ids+=("$outsider_id")

export WE_QA_PARTNER_A_ID="$partner_a_id"
export WE_QA_PARTNER_A_EMAIL="$partner_a_email"
export WE_QA_PARTNER_A_PASSWORD="$partner_a_password"
export WE_QA_PARTNER_B_ID="$partner_b_id"
export WE_QA_PARTNER_B_EMAIL="$partner_b_email"
export WE_QA_PARTNER_B_PASSWORD="$partner_b_password"
export WE_QA_OUTSIDER_ID="$outsider_id"
export WE_QA_OUTSIDER_EMAIL="$outsider_email"
export WE_QA_OUTSIDER_PASSWORD="$outsider_password"

echo "Running the disposable three-client repository lifecycle."
bash scripts/qa/run-xcode-tests.sh \
  live-contract \
  "$destination" \
  "$result_bundle" \
  "$derived_data"
