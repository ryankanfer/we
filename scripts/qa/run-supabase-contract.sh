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
# Two lint findings are deliberate and cannot be fixed where the linter
# points, so they are named here and everything else still fails the lane.
# A finding that is not on this list — including a new one in either of these
# two functions — fails, and the list is checked for staleness below so a
# finding that gets fixed cannot quietly keep its exemption.
#
#   resolve_insight / p_choice
#     Ignored on purpose. `resolution_choice` is taken from the shared
#     direction's own title, never from client wording, and
#     private_answers_shared_directions.test.sql:76-82 asserts exactly that
#     ("resolution persists only server-produced direction wording"). The
#     parameter stays because SupabaseRepository.swift:485 still sends it and
#     the signature is asserted in two suites. Honouring it would break the
#     privacy property; removing it would break deployed clients.
#
#   refresh_shared_moments / p_local_date
#     A compatibility shim. 20260808120000:513 keeps the old symbol for
#     already-deployed clients while removing every canned daily behaviour
#     behind it, and what replaced it takes no date. Nothing in WE/ calls it.
expected_lint_findings=(
  'resolve_insight|unused parameter "p_choice"'
  'refresh_shared_moments|unused parameter "p_local_date"'
)

set +e
supabase db lint --local --level warning --fail-on warning \
  2>&1 | tee "$artifact_directory/lint.log"
lint_status="${PIPESTATUS[0]}"
set -e

if [[ "$lint_status" -ne 0 ]]; then
  unexplained_findings="$(
    python3 - "$artifact_directory/lint.log" "${expected_lint_findings[@]}" <<'PYLINT'
import json
import re
import sys

log = open(sys.argv[1]).read()
allowed = set(sys.argv[2:])

match = re.search(r"^\[$.*?^\]$", log, re.S | re.M)
if match is None:
    # Lint failed without producing a report at all. That is not something an
    # allowlist can speak to.
    print("lint produced no JSON report")
    raise SystemExit(0)

seen = set()
unexplained = []
for entry in json.loads(match.group(0)):
    function = entry["function"].split(".")[-1]
    for issue in entry["issues"]:
        finding = f"{function}|{issue['message']}"
        seen.add(finding)
        if finding not in allowed:
            unexplained.append(f"{entry['function']}: {issue['message']}")

for stale in sorted(allowed - seen):
    unexplained.append(
        f"allowlisted finding no longer reported, remove it: {stale}"
    )

print("\n".join(unexplained))
PYLINT
  )"

  if [[ -n "$unexplained_findings" ]]; then
    echo "db lint reported findings that are not accounted for:" >&2
    echo "$unexplained_findings" >&2
    exit 1
  fi

  echo "db lint reported only the findings recorded above."
elif [[ "${#expected_lint_findings[@]}" -gt 0 ]]; then
  echo "db lint is clean, so the recorded findings above are stale." >&2
  echo "Remove expected_lint_findings and let the lane fail on its own." >&2
  exit 1
fi
