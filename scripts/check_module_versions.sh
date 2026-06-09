#!/usr/bin/env bash
# check_module_versions.sh
#
# Scans every live/ terragrunt stack and reports which module refs
# are behind the latest git tag in the upstream repo.
#
# Usage:
#   check_module_versions.sh [module_repo_url] [env_filter]
#
# Args:
#   module_repo_url – defaults to https://github.com/beravelli/autotfrefresh.git
#   env_filter      – optional; restrict to a specific env dir (e.g. dev or prod)
#
# Output:
#   Table to stdout showing Current vs Latest for each stack.
#
# Exit code:
#   0 – all stacks up to date
#   N – number of stacks behind (so Jenkins can set UNSTABLE on N > 0)

set -euo pipefail

MODULE_REPO_URL="${1:-https://github.com/beravelli/autotfrefresh.git}"
ENV_FILTER="${2:-}"

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

# ── Tag cache: avoids one git ls-remote per stack for the same module ──────────
# Uses a temp dir so it works on Bash 3 (macOS) and Bash 4+ (Linux/Jenkins)
CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$CACHE_DIR"' EXIT

get_latest_version() {
  local module="$1"
  local cache_file="${CACHE_DIR}/${module}"
  if [[ -f "$cache_file" ]]; then
    cat "$cache_file"
    return
  fi
  # List all vX.Y.Z tags for this module, sort by semver, take the highest
  local latest
  latest=$(git ls-remote --tags "$MODULE_REPO_URL" "refs/tags/${module}/v*" 2>/dev/null \
    | grep -v '\^{}' \
    | sed "s|.*refs/tags/${module}/||" \
    | sort -V \
    | tail -1)
  latest="${latest:-unknown}"
  echo "$latest" > "$cache_file"
  echo "$latest"
}

# ── Scan ───────────────────────────────────────────────────────────────────────
STALE=0
TOTAL=0
ROWS=()

while IFS= read -r -d '' tg_file; do
  # Match lines like:
  #   source = "git::https://…//modules/vpc?ref=vpc/v1.0.0"
  source_line=$(grep -oE 'git::[^"]+//modules/[^"]+\?ref=[^"]+' "$tg_file" 2>/dev/null || true)
  [[ -z "$source_line" ]] && continue

  module_name=$(echo "$source_line" | sed -n 's|.*//modules/\([^?]*\).*|\1|p')
  full_ref=$(echo "$source_line"    | sed -n 's|.*?ref=[^/]*/\(v[^"'"'"' ]*\).*|\1|p')

  [[ -z "$module_name" || -z "$full_ref" ]] && continue

  stack_rel="${tg_file%/terragrunt.hcl}"
  stack_rel="${stack_rel#"$LIVE_ROOT/"}"

  latest_ver=$(get_latest_version "$module_name")

  TOTAL=$((TOTAL + 1))

  if [[ "$full_ref" == "$latest_ver" ]]; then
    status="✓ up to date"
  else
    status="⚠  BEHIND"
    STALE=$((STALE + 1))
  fi

  ROWS+=("$(printf '%-38s %-8s %-10s %-10s %s' \
    "$stack_rel" "$module_name" "$full_ref" "$latest_ver" "$status")")

done < <(find "$SEARCH_ROOT" -name "terragrunt.hcl" -print0 | sort -z)

# ── Report ─────────────────────────────────────────────────────────────────────
printf "\n"
printf '%-38s %-8s %-10s %-10s %s\n' \
  "Stack" "Module" "Current" "Latest" "Status"
printf '%-38s %-8s %-10s %-10s %s\n' \
  "$(printf '%0.s─' {1..38})" \
  "$(printf '%0.s─' {1..8})" \
  "$(printf '%0.s─' {1..10})" \
  "$(printf '%0.s─' {1..10})" \
  "$(printf '%0.s─' {1..14})"

for row in "${ROWS[@]}"; do
  echo "$row"
done

printf "\n"
if [[ $STALE -eq 0 ]]; then
  echo "✓ All ${TOTAL} stack(s) are running the latest module tags."
else
  echo "⚠  ${STALE}/${TOTAL} stack(s) are behind the latest module tags."
  echo ""
  echo "To refresh a stale module, push a new tag or trigger the refresh pipeline:"
  echo "  gitops/refresh-pipeline  MODULE_NAME=<name>  MODULE_VERSION=<latest>"
fi
printf "\n"

# Exit code = number of stale stacks (0 = clean, >0 = drift detected)
exit $STALE
