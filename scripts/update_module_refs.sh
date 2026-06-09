#!/usr/bin/env bash
# update_module_refs.sh — patch stale module source refs in live/ terragrunt stacks
#
# Usage:
#   update_module_refs.sh <updates_file>
#
# Arguments:
#   updates_file    path to TSV produced by check_module_versions.sh:
#                   <stack_path>|<module>|<current_version>|<latest_version>
#
# What this script does:
#   - Patches each stale terragrunt.hcl in-place (sed on the ?ref= line)
#   - git add + git commit (does NOT push — the caller handles push with credentials)
#
# Environment variables:
#   GIT_AUTHOR_NAME    defaults to "Jenkins"
#   GIT_AUTHOR_EMAIL   defaults to "jenkins@ci.local"
#
# Exit codes:
#   0  success (files patched and committed, or nothing to do)
#   1  error

set -euo pipefail

UPDATES_FILE="${1:?updates_file required}"

export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Jenkins}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-jenkins@ci.local}"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -f "$UPDATES_FILE" ]]; then
  echo "ERROR: updates file not found: ${UPDATES_FILE}" >&2
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Updating module refs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

UPDATED=()
while IFS='|' read -r stack module current latest; do
  [[ -z "$stack" ]] && continue

  tg_file="${REPO_ROOT}/live/${stack}/terragrunt.hcl"
  if [[ ! -f "$tg_file" ]]; then
    echo "WARNING: terragrunt.hcl not found for stack '${stack}' — skipping" >&2
    continue
  fi

  echo "  ${stack}  ${module}/${current} → ${module}/${latest}"
  sed -i "s|?ref=${module}/${current}|?ref=${module}/${latest}|g" "$tg_file"
  UPDATED+=("$tg_file")

done < "$UPDATES_FILE"

if [[ ${#UPDATED[@]} -eq 0 ]]; then
  echo "Nothing to update."
  exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Committing and pushing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$REPO_ROOT"

git config user.email "$GIT_AUTHOR_EMAIL"
git config user.name  "$GIT_AUTHOR_NAME"

# Stage only the files we touched
git add "${UPDATED[@]}"

# Build a compact commit message listing each update
COMMIT_BODY=""
while IFS='|' read -r stack module current latest; do
  [[ -z "$stack" ]] && continue
  COMMIT_BODY="${COMMIT_BODY}  ${stack}: ${module}/${current} → ${module}/${latest}\n"
done < "$UPDATES_FILE"

git commit -m "$(printf 'chore: bump module refs to latest versions\n\n%b\n[skip ci]' "$COMMIT_BODY")"

echo ""
echo "✓ Module refs committed — caller will push with credentials."
