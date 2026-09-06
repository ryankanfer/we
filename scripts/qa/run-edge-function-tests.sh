#!/usr/bin/env bash

# The private-to-shared contract's automated half.
#
# `docs/PRIVATE_TO_SHARED_CONTRACT.md` is the authority; these tests enforce it.
# They are the only automated check that private answers cannot reach shared
# copy, so this script is a required check rather than an advisory one.

set -euo pipefail

artifact_directory="${1:-artifacts/edge-functions}"
mkdir -p "$artifact_directory"

if ! command -v deno >/dev/null 2>&1; then
  echo "Deno is required to run the Edge Function contract tests." >&2
  exit 69
fi

# The config must be passed explicitly. The repository root carries the frozen
# Next.js `package.json`, and without `--config` Deno resolves that instead,
# drops into node-compat mode, and stops resolving `Deno` itself during
# type-check — which fails in a way that looks unrelated to this suite.
config="supabase/functions/deno.json"

set +e
deno test --config "$config" supabase/functions/ \
  2>&1 | tee "$artifact_directory/edge-function-tests.log"
status="${PIPESTATUS[0]}"
set -e

if [ "$status" -ne 0 ]; then
  echo "Edge Function contract tests failed." >&2
fi

exit "$status"
