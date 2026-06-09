#!/usr/bin/env bash
# discover_stacks.sh — find live stacks matching optional filters
#
# Usage:
#   discover_stacks.sh [env_filter] [region_filter] [module_filter] [stack_filter]
#
# Arguments (all optional, empty string = match all):
#   env_filter    e.g. "dev" or "prod"
#   region_filter e.g. "us-east-1"
#   module_filter e.g. "vpc" or "eks"
#   stack_filter  exact path e.g. "dev/us-east-1/vpc"  — overrides other filters
#
# Output: one stack path per line (relative to repo root live/ dir), e.g.
#   dev/us-east-1/eks
#   dev/us-east-1/vpc
#   prod/us-east-1/vpc

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIVE_DIR="${REPO_ROOT}/live"

ENV_FILTER="${1:-}"
REGION_FILTER="${2:-}"
MODULE_FILTER="${3:-}"
STACK_FILTER="${4:-}"

# ── Exact stack override ────────────────────────────────────────────────────
if [[ -n "$STACK_FILTER" ]]; then
  if [[ -f "${LIVE_DIR}/${STACK_FILTER}/terragrunt.hcl" ]]; then
    echo "$STACK_FILTER"
    exit 0
  else
    echo "ERROR: Stack not found: live/${STACK_FILTER}/terragrunt.hcl" >&2
    exit 1
  fi
fi

# ── Discover with filters ───────────────────────────────────────────────────
found=0
while IFS= read -r tgfile; do
  # Get path relative to live/ dir: dev/us-east-1/vpc/terragrunt.hcl
  rel="${tgfile#${LIVE_DIR}/}"
  dir="$(dirname "$rel")"

  # Must be exactly 3 levels deep: env/region/module
  depth=$(echo "$dir" | tr -cd '/' | wc -c)
  [[ "$depth" -ne 2 ]] && continue

  env_part="$(echo "$dir"    | cut -d'/' -f1)"
  region_part="$(echo "$dir" | cut -d'/' -f2)"
  module_part="$(echo "$dir" | cut -d'/' -f3)"

  [[ -n "$ENV_FILTER"    && "$env_part"    != "$ENV_FILTER"    ]] && continue
  [[ -n "$REGION_FILTER" && "$region_part" != "$REGION_FILTER" ]] && continue
  [[ -n "$MODULE_FILTER" && "$module_part" != "$MODULE_FILTER" ]] && continue

  echo "$dir"
  found=$((found + 1))
done < <(find "$LIVE_DIR" -name "terragrunt.hcl" | sort)

if [[ "$found" -eq 0 ]]; then
  echo "No stacks matched filters: env='${ENV_FILTER}' region='${REGION_FILTER}' module='${MODULE_FILTER}'" >&2
fi
