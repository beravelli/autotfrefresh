#!/usr/bin/env bash
# tofu_plan.sh
#
# Plans (or validates in dry-run) a single terragrunt stack after temporarily
# patching the module ref to the new version. Restores the original file on exit.
#
# Usage:
#   tofu_plan.sh <stack_rel_path> <module_repo_url> <module_name> \
#                <module_version> <plan_file> <dry_run>
#
# Args:
#   stack_rel_path  – e.g. dev/us-east-1/vpc
#   module_repo_url – e.g. https://github.com/beravelli/autotfrefresh.git
#   module_name     – e.g. vpc
#   module_version  – e.g. v1.2.3
#   plan_file       – path to save the plan binary (ignored in dry-run)
#   dry_run         – "true" = tofu validate only; "false" = terragrunt plan
#
# Exit codes:
#   0  – success, no changes (or dry-run passed)
#   2  – success, changes detected
#   1+ – error

set -euo pipefail

STACK_REL_PATH="${1:?stack_rel_path required}"
MODULE_REPO_URL="${2:?module_repo_url required}"
MODULE_NAME="${3:?module_name required}"
MODULE_VERSION="${4:?module_version required}"
PLAN_FILE="${5:?plan_file required}"
DRY_RUN="${6:-true}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE_ROOT="${SCRIPT_DIR}/../live"
STACK_DIR="${LIVE_ROOT}/${STACK_REL_PATH}"
TG_FILE="${STACK_DIR}/terragrunt.hcl"
TG_BACKUP="${TG_FILE}.bak"

if [[ ! -f "$TG_FILE" ]]; then
  echo "ERROR: terragrunt.hcl not found at ${TG_FILE}" >&2
  exit 1
fi

# The source pattern to patch:
#   git::https://github.com/beravelli/autotfrefresh.git//modules/vpc?ref=vpc/v1.0.0
OLD_REF_PATTERN="${MODULE_REPO_URL}//modules/${MODULE_NAME}?ref=${MODULE_NAME}/"
NEW_SOURCE="${MODULE_REPO_URL}//modules/${MODULE_NAME}?ref=${MODULE_NAME}/${MODULE_VERSION}"

cleanup() {
  if [[ -f "$TG_BACKUP" ]]; then
    mv "$TG_BACKUP" "$TG_FILE"
  fi
}
trap cleanup EXIT

# Backup and patch ref
cp "$TG_FILE" "$TG_BACKUP"
perl -i -pe "s|git::${MODULE_REPO_URL}//modules/${MODULE_NAME}\?ref=[^\"']+|git::${NEW_SOURCE}|g" "$TG_FILE"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Stack   : ${STACK_REL_PATH}"
echo " Module  : ${MODULE_NAME} → ${MODULE_VERSION}"
echo " DRY_RUN : ${DRY_RUN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$STACK_DIR"

if [[ "$DRY_RUN" == "true" ]]; then
  # Validate only — no backend, no AWS credentials required
  tofu init -backend=false -input=false -upgrade 2>&1
  tofu validate 2>&1
  echo "✓ Validation passed for ${STACK_REL_PATH}"
  # Exit 2 to signal "changes would be applied" (consistent with plan semantics)
  exit 2
else
  # Real plan via terragrunt
  terragrunt plan \
    --terragrunt-non-interactive \
    -out="${PLAN_FILE}" \
    -detailed-exitcode
  PLAN_EXIT=$?
  [[ $PLAN_EXIT -eq 0 ]] && echo "✓ No changes for ${STACK_REL_PATH}"
  [[ $PLAN_EXIT -eq 2 ]] && echo "⚠ Changes detected for ${STACK_REL_PATH}"
  exit $PLAN_EXIT
fi
