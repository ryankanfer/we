#!/usr/bin/env bash

set -euo pipefail

artifact_directory="${1:-artifacts/supabase}"
mkdir -p "$artifact_directory"

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI is required." >&2
  exit 69
fi

cleanup() {
  supabase stop --no-backup >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_logged() {
  local log_name="$1"
  shift

  set +e
  "$@" 2>&1 | tee "$artifact_directory/$log_name"
  local command_status="${PIPESTATUS[0]}"
  set -e
  return "$command_status"
}

# The stack is isolated to this runner. Reset applies every committed
# migration from zero before pgTAP and lint inspect the resulting schema.
run_logged start.log supabase start
run_logged reset.log supabase db reset --local
run_logged pgtap.log supabase test db
run_logged lint.log supabase db lint \
  --local \
  --level warning \
  --fail-on warning
