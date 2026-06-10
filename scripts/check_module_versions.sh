#!/usr/bin/env bash
# check_module_versions.sh
#
# Scans every live/ terragrunt stack and reports which module refs are
# behind the latest git tag.  Works with BOTH layouts:
#
#   Multi-repo  (one repo per module, tags: v1.0.0)
#     source = "git::https://github.com/org/tf-module-vpc.git?ref=v1.0.0"
#
#   Monorepo    (all modules in one repo, tags: vpc/v1.0.0)
#     source = "git::https://github.com/org/infra.git//modules/vpc?ref=vpc/v1.0.0"
#
# The repo URL, module name and tag format are ALL read from the source
# line in each terragrunt.hcl — no hardcoded repo URL needed.
#
# Usage:
#   check_module_versions.sh [env_filter] [updates_file]
#
# Args:
#   env_filter    optional; restrict to a specific env dir (e.g. dev or prod)
#   updates_file  optional; path to write stale entries as pipe-delimited TSV:
#                 <stack_path>|<module_name>|<current_ref>|<latest_ref>
#
# Exit code:
#   0  all stacks up to date
#   N  number of stacks behind

set -euo pipefail

ENV_FILTER="${1:-}"
UPDATES_FILE="${2:-}"

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

# ── Tag cache: keyed by "repo_url|tag_prefix" to avoid redundant ls-remote ──
CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$CACHE_DIR"' EXIT

get_latest_version() {
  local repo_url="$1"
  local tag_prefix="$2"   # e.g. "vpc/" for monorepo, "" for multi-repo

  local cache_key
  cache_key=$(printf '%s|%s' "$repo_url" "$tag_prefix" | md5 -q 2>/dev/null \
              || printf '%s|%s' "$repo_url" "$tag_prefix" | md5sum | cut -d' ' -f1)
  local cache_file="${CACHE_DIR}/${cache_key}"

  if [[ -f "$cache_file" ]]; then
    cat "$cache_file"
    return
  fi

  local latest
  latest=$(git ls-remote --tags "$repo_url" "refs/tags/${tag_prefix}v*" 2>/dev/null \
    | grep -v '\^{}' \
    | sed "s|.*refs/tags/${tag_prefix}||" \
    | sort -V \
    | tail -1)
  latest="${latest:-unknown}"
  echo "$latest" > "$cache_file"
  echo "$latest"
}

# ── Scan ──────────────────────────────────────────────────────────────────────
STALE=0
TOTAL=0
ROWS=()
STALE_ENTRIES=()

while IFS= read -r -d '' tg_file; do
  # Match: git::https://...?ref=...
  source_line=$(grep -oE 'git::[^"]+\?ref=[^"]+' "$tg_file" 2>/dev/null || true)
  [[ -z "$source_line" ]] && continue

  # ── Parse repo URL ─────────────────────────────────────────────────────────
  # Strip git:: prefix, isolate the URL before any ?
  raw_url="${source_line#git::}"
  url_part="${raw_url%%\?*}"

  # Repo URL = scheme + host + org + repo.git  (stops before //subdir)
  # Works for both:
  #   https://github.com/org/tf-module-vpc.git
  #   https://github.com/org/monorepo.git//modules/vpc
  repo_url=$(echo "$url_part" | sed -E 's|(https?://[^/]+/[^/]+/[^/?]+).*|\1|')

  # ── Parse current ref ──────────────────────────────────────────────────────
  current_ref="${source_line##*\?ref=}"

  [[ -z "$repo_url" || -z "$current_ref" ]] && continue

  # ── Derive module name ─────────────────────────────────────────────────────
  # Look for a //subdir AFTER the repo URL (skip the https:// protocol part)
  after_repo=$(echo "$url_part" | sed -E 's|https?://[^/]+/[^/]+/[^/?]+||')
  subpath=$(echo "$after_repo" | grep -oE '//[^?]+' 2>/dev/null | sed 's|^//||' | head -1 || true)
  if [[ -n "$subpath" ]]; then
    # monorepo style: //modules/vpc → module = vpc
    module_name=$(basename "$subpath")
  else
    # multi-repo style: repo name is the module name
    module_name=$(basename "$repo_url" .git)
    module_name="${module_name#tf-module-}"
    module_name="${module_name#terraform-}"
    module_name="${module_name#terraform-aws-}"
  fi

  # ── Determine tag prefix ───────────────────────────────────────────────────
  # Monorepo style:  ref = "vpc/v1.0.0"  → prefix = "vpc/"
  # Multi-repo style: ref = "v1.0.0"     → prefix = ""
  if [[ "$current_ref" =~ ^[^/]+/v[0-9] ]]; then
    tag_prefix="${current_ref%%/v*}/"
    version_part="v${current_ref##*/v}"
  else
    tag_prefix=""
    version_part="$current_ref"
  fi

  stack_rel="${tg_file%/terragrunt.hcl}"
  stack_rel="${stack_rel#"$LIVE_ROOT/"}"

  # ── Get latest version for this repo ──────────────────────────────────────
  latest_version=$(get_latest_version "$repo_url" "$tag_prefix")

  if [[ -n "$tag_prefix" ]]; then
    latest_ref="${tag_prefix}${latest_version}"
  else
    latest_ref="$latest_version"
  fi

  TOTAL=$((TOTAL + 1))

  if [[ "$current_ref" == "$latest_ref" ]]; then
    status="✓ up to date"
  else
    status="⚠  BEHIND"
    STALE=$((STALE + 1))
    STALE_ENTRIES+=("${stack_rel}|${module_name}|${current_ref}|${latest_ref}")
  fi

  ROWS+=("$(printf '%-38s %-8s %-10s %-10s %s' \
    "$stack_rel" "$module_name" "$current_ref" "$latest_ref" "$status")")

done < <(find "$SEARCH_ROOT" -name "terragrunt.hcl" -print0 | sort -z)

# ── Report ────────────────────────────────────────────────────────────────────
printf "\n"
printf '%-38s %-8s %-10s %-10s %s\n' \
  "Stack" "Module" "Current" "Latest" "Status"
printf '%-38s %-8s %-10s %-10s %s\n' \
  "$(printf '%0.s─' {1..38})" \
  "$(printf '%0.s─' {1..8})" \
  "$(printf '%0.s─' {1..10})" \
  "$(printf '%0.s─' {1..10})" \
  "$(printf '%0.s─' {1..14})"

for row in "${ROWS[@]}"; do echo "$row"; done

printf "\n"
if [[ $STALE -eq 0 ]]; then
  echo "✓ All ${TOTAL} stack(s) are running the latest module tags."
else
  echo "⚠  ${STALE}/${TOTAL} stack(s) are behind the latest module tags."
  echo ""
  echo "Set UPDATE_MODULES=true in the live-infra pipeline to bump and commit."
fi
printf "\n"

# ── Write machine-readable updates file (for downstream update step) ──────────
if [[ -n "$UPDATES_FILE" && ${#STALE_ENTRIES[@]} -gt 0 ]]; then
  printf '%s\n' "${STALE_ENTRIES[@]}" > "$UPDATES_FILE"
fi

exit $STALE
