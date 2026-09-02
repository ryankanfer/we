#!/usr/bin/env bash
#
# Compare the migrations in this repository against the migrations a Supabase
# project has actually applied, and print the difference.
#
# WE reached a state where the live project was 27 migrations ahead of `main`
# and nobody could tell from the repository. This makes that visible in one
# command, so it can be caught the week it happens instead of a quarter later.
#
# Usage:
#   supabase/scripts/check-drift.sh                 # uses the linked project
#   supabase/scripts/check-drift.sh --project-ref X
#
# Exits non-zero when the repository and the project disagree.

set -euo pipefail

cd "$(dirname "$0")/../.."

PROJECT_ARGS=(--linked)
if [ "${1:-}" = "--project-ref" ] && [ -n "${2:-}" ]; then
  PROJECT_ARGS=(--project-ref "$2")
fi

if ! command -v supabase >/dev/null 2>&1; then
  echo "The Supabase CLI is not installed. See https://supabase.com/docs/guides/cli" >&2
  exit 2
fi

repo_versions=$(
  find supabase/migrations -maxdepth 1 -name '*.sql' -print0 \
    | xargs -0 -n1 basename \
    | sed -E 's/^([0-9]+)_.*/\1/' \
    | sort -u
)

# `migration list` prints a Local | Remote table; take the remote column.
remote_versions=$(
  supabase migration list "${PROJECT_ARGS[@]}" 2>/dev/null \
    | awk -F'|' 'NF >= 2 { gsub(/[^0-9]/, "", $2); if ($2 != "") print $2 }' \
    | sort -u
)

if [ -z "$remote_versions" ]; then
  echo "Could not read the remote migration list. Is the project linked and are you logged in?" >&2
  exit 2
fi

only_remote=$(comm -13 <(echo "$repo_versions") <(echo "$remote_versions"))
only_repo=$(comm -23 <(echo "$repo_versions") <(echo "$remote_versions"))

status=0

if [ -n "$only_remote" ]; then
  echo "Applied to the project but MISSING from this repository:"
  echo "$only_remote" | sed 's/^/  /'
  echo
  echo "  The repository cannot rebuild this project. Recover the SQL from"
  echo "  whoever applied it, or baseline from a schema dump — see"
  echo "  supabase/README.md."
  echo
  status=1
fi

if [ -n "$only_repo" ]; then
  echo "In this repository but NOT yet applied to the project:"
  echo "$only_repo" | sed 's/^/  /'
  echo
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "In sync: $(echo "$repo_versions" | wc -l | tr -d ' ') migrations."
fi

exit "$status"
