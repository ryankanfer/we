#!/usr/bin/env bash

# Host-only helpers for disposable live-contract identities.
#
# Source this file from a coordinator. Call we_qa_admin_initialize before
# unsetting WE_QA_SUPABASE_SERVICE_ROLE_KEY in that coordinator. The saved
# service credential is deliberately not exported, so child build/test
# processes cannot inherit it.

we_qa_admin_initialize() {
  for command_name in curl jq; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      echo "required command is unavailable: $command_name" >&2
      return 69
    fi
  done

  if [[ -z "${WE_QA_SUPABASE_URL:-}" ||
        -z "${WE_QA_SUPABASE_ANON_KEY:-}" ||
        -z "${WE_QA_SUPABASE_SERVICE_ROLE_KEY:-}" ||
        -z "${WE_QA_RUN_ID:-}" ]]; then
    echo "The host live-contract environment is incomplete." >&2
    return 78
  fi

  # Unsetting first guarantees a caller cannot leave the saved host secret
  # marked for export.
  unset WE_QA_ADMIN_SERVICE_KEY
  WE_QA_ADMIN_BASE_URL="${WE_QA_SUPABASE_URL%/}"
  WE_QA_ADMIN_ANON_KEY="$WE_QA_SUPABASE_ANON_KEY"
  WE_QA_ADMIN_SERVICE_KEY="$WE_QA_SUPABASE_SERVICE_ROLE_KEY"
  WE_QA_ADMIN_RUN_SLUG="$(
    printf '%s' "$WE_QA_RUN_ID" |
      tr -c '[:alnum:]' '-' |
      cut -c 1-28
  )"
  if [[ -z "$WE_QA_ADMIN_RUN_SLUG" ]]; then
    echo "WE_QA_RUN_ID must contain at least one letter or number." >&2
    return 78
  fi
}

we_qa_admin_create_user() {
  if [[ $# -ne 3 ]]; then
    echo "usage: we_qa_admin_create_user <cohort> <role> <display-name>" >&2
    return 64
  fi

  local cohort="$1"
  local role="$2"
  local display_name="$3"
  local email
  local password
  local response

  email="we-qa-${cohort}-${role}-${WE_QA_ADMIN_RUN_SLUG}@example.com"
  password="WE-QA-${WE_QA_ADMIN_RUN_SLUG}-${cohort}-${role}-aA1!"
  response="$(
    curl --fail-with-body --silent --show-error \
      --request POST \
      --header "apikey: $WE_QA_ADMIN_SERVICE_KEY" \
      --header "Authorization: Bearer $WE_QA_ADMIN_SERVICE_KEY" \
      --header "Content-Type: application/json" \
      --data "$(
        jq -cn \
          --arg email "$email" \
          --arg password "$password" \
          --arg name "$display_name" \
          '{
            email: $email,
            password: $password,
            email_confirm: true,
            user_metadata: {name: $name}
          }'
      )" \
      "$WE_QA_ADMIN_BASE_URL/auth/v1/admin/users"
  )"

  WE_QA_CREATED_USER_ID="$(printf '%s' "$response" | jq -er '.id')"
  WE_QA_CREATED_USER_EMAIL="$email"
  WE_QA_CREATED_USER_PASSWORD="$password"
}

we_qa_admin_delete_user() {
  if [[ $# -ne 1 || -z "$1" ]]; then
    return 0
  fi
  if ! curl --fail-with-body --silent --show-error \
      --request DELETE \
      --header "apikey: $WE_QA_ADMIN_SERVICE_KEY" \
      --header "Authorization: Bearer $WE_QA_ADMIN_SERVICE_KEY" \
      "$WE_QA_ADMIN_BASE_URL/auth/v1/admin/users/$1" \
      >/dev/null; then
    echo "warning: could not delete disposable QA user $1" >&2
  fi
}

we_qa_admin_delete_couple() {
  if [[ $# -ne 1 || -z "$1" ]]; then
    return 0
  fi
  if ! curl --fail-with-body --silent --show-error \
      --request DELETE \
      --header "apikey: $WE_QA_ADMIN_SERVICE_KEY" \
      --header "Authorization: Bearer $WE_QA_ADMIN_SERVICE_KEY" \
      --header "Prefer: return=minimal" \
      "$WE_QA_ADMIN_BASE_URL/rest/v1/couples?id=eq.$1" \
      >/dev/null; then
    echo "warning: could not delete disposable QA couple $1" >&2
  fi
}

we_qa_admin_delete_couples_created_by() {
  if [[ $# -ne 1 || -z "$1" ]]; then
    return 0
  fi
  # The creator is a unique disposable user for this run. Deleting by that
  # exact UUID removes a partially-created relationship before its profile is
  # deleted and `couples.created_by` becomes null.
  if ! curl --fail-with-body --silent --show-error \
      --request DELETE \
      --header "apikey: $WE_QA_ADMIN_SERVICE_KEY" \
      --header "Authorization: Bearer $WE_QA_ADMIN_SERVICE_KEY" \
      --header "Prefer: return=minimal" \
      "$WE_QA_ADMIN_BASE_URL/rest/v1/couples?created_by=eq.$1" \
      >/dev/null; then
    echo "warning: could not delete QA couples created by $1" >&2
  fi
}

we_qa_user_sign_in() {
  if [[ $# -ne 2 ]]; then
    echo "usage: we_qa_user_sign_in <email> <password>" >&2
    return 64
  fi
  local response
  response="$(
    curl --fail-with-body --silent --show-error \
      --request POST \
      --header "apikey: $WE_QA_ADMIN_ANON_KEY" \
      --header "Content-Type: application/json" \
      --data "$(
        jq -cn --arg email "$1" --arg password "$2" \
          '{email: $email, password: $password}'
      )" \
      "$WE_QA_ADMIN_BASE_URL/auth/v1/token?grant_type=password"
  )"
  WE_QA_USER_ACCESS_TOKEN="$(
    printf '%s' "$response" | jq -er '.access_token'
  )"
}

we_qa_user_create_couple() {
  if [[ $# -ne 1 || -z "$1" ]]; then
    echo "usage: we_qa_user_create_couple <access-token>" >&2
    return 64
  fi
  local response
  response="$(
    curl --fail-with-body --silent --show-error \
      --request POST \
      --header "apikey: $WE_QA_ADMIN_ANON_KEY" \
      --header "Authorization: Bearer $1" \
      --header "Content-Type: application/json" \
      --data '{}' \
      "$WE_QA_ADMIN_BASE_URL/rest/v1/rpc/create_couple"
  )"
  WE_QA_CREATED_COUPLE_ID="$(
    printf '%s' "$response" | jq -er '.couple_id'
  )"
  WE_QA_CREATED_JOIN_CODE="$(
    printf '%s' "$response" | jq -er '.join_code'
  )"
}

we_qa_user_join_couple() {
  if [[ $# -ne 2 || -z "$1" || -z "$2" ]]; then
    echo "usage: we_qa_user_join_couple <access-token> <join-code>" >&2
    return 64
  fi
  curl --fail-with-body --silent --show-error \
    --request POST \
    --header "apikey: $WE_QA_ADMIN_ANON_KEY" \
    --header "Authorization: Bearer $1" \
    --header "Content-Type: application/json" \
    --data "$(jq -cn --arg code "$2" '{p_code: $code}')" \
    "$WE_QA_ADMIN_BASE_URL/rest/v1/rpc/join_couple" \
    >/dev/null
}

we_qa_admin_capture_exists() {
  if [[ $# -ne 2 ]]; then
    echo "usage: we_qa_admin_capture_exists <couple-id> <text>" >&2
    return 64
  fi
  local response
  response="$(
    curl --fail-with-body --silent --show-error \
      --header "apikey: $WE_QA_ADMIN_SERVICE_KEY" \
      --header "Authorization: Bearer $WE_QA_ADMIN_SERVICE_KEY" \
      --get \
      --data-urlencode "select=id" \
      --data-urlencode "couple_id=eq.$1" \
      --data-urlencode "text=eq.$2" \
      "$WE_QA_ADMIN_BASE_URL/rest/v1/field_captures"
  )"
  [[ "$(printf '%s' "$response" | jq 'length')" -gt 0 ]]
}
