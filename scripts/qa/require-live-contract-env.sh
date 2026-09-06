#!/usr/bin/env bash

set -euo pipefail

required_names=(
  WE_QA_SUPABASE_URL
  WE_QA_SUPABASE_ANON_KEY
  WE_QA_SUPABASE_SERVICE_ROLE_KEY
  WE_QA_RUN_ID
)

missing_names=()
for variable_name in "${required_names[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    missing_names+=("$variable_name")
  fi
done

if [[ "${#missing_names[@]}" -gt 0 ]]; then
  echo "The isolated live-contract environment is incomplete." >&2
  printf 'Missing GitHub Actions secret: %s\n' "${missing_names[@]}" >&2
  exit 78
fi

case "$WE_QA_SUPABASE_URL" in
  https://*) ;;
  *)
    echo "WE_QA_SUPABASE_URL must be an HTTPS URL for the isolated QA stack." >&2
    exit 78
    ;;
esac

echo "Live-contract environment is configured (secret values withheld)."
