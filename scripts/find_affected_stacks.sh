#!/usr/bin/env bash
# find_affected_stacks.sh
#
# Scans live/ for terragrunt stacks whose source references
# the specific module subdirectory inside the monorepo.
#
# Usage:
#   find_affected_stacks.sh <module_repo_url> <module_name> [env_filter]
#
# Args:
#   module_repo_url – e.g. https://github.com/beravelli/autotfrefresh.git
#   module_name     – e.g. vpc  (matches //modules/vpc in source)
#   env_filter      – optional; restrict to a specific env dir (e.g. dev)
#
# Outputs one stack path per line, relative to live/.
# Exits 0 on success (even with zero results), non-zero on setup errors.

set -euo pipefail

MODULE_REPO_URL="${1:?module_repo_url required}"
MODULE_NAME="${2:?module_name required}"
ENV_FILTER="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE_ROOT="${SCRIPT_DIR}/../live"

if [[ ! -d "$LIVE_ROOT" ]]; then
  echo "ERROR: live/ directory not found at ${LIVE_ROOT}" >&2
  exit 1
fi

SEARCH_ROOT="$LIVE_ROOT"
if [[ -n "$ENV_FILTER" ]]; then
  SEARCH_ROOT="${LIVE_ROOT}/${ENV_FILTER}"
  if [[ ! -d "$SEARCH_ROOT" ]]; then
    echo "ERROR: env filter directory not found: ${SEARCH_ROOT}" >&2
    exit 1
  fi
fi

# Build the exact string to look for in terragrunt.hcl source lines:
#   git::https://github.com/beravelli/autotfrefresh.git//modules/vpc
SEARCH_STRING="git::${MODULE_REPO_URL}//modules/${MODULE_NAME}"

while IFS= read -r -d '' tg_file; do
  if grep -qF "${SEARCH_STRING}" "$tg_file"; then
    dir="$(dirname "$tg_file")"
    echo "${dir#"$LIVE_ROOT/"}"
  fi
done < <(find "$SEARCH_ROOT" -name "terragrunt.hcl" -not -name "root" -print0)
