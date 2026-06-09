#!/usr/bin/env bash
# stack_action.sh — run validate / plan / apply on a live stack
#
# Usage:
#   stack_action.sh <stack_path> <action> [plan_file]
#
# Arguments:
#   stack_path  relative path under live/, e.g. dev/us-east-1/vpc
#   action      validate | plan | apply
#   plan_file   (optional) path to write/read the plan binary
#               plan  → writes plan to this file (if supplied)
#               apply → reads plan from this file (if supplied and exists)
#
# Exit codes:
#   0  success / no changes (validate, apply)
#   2  changes detected (plan only — mirrors terraform/tofu semantics)
#   1+ error

set -euo pipefail

STACK_PATH="${1:?stack_path required}"
ACTION="${2:?action required (validate|plan|apply)}"
PLAN_FILE="${3:-}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/live/${STACK_PATH}"

if [[ ! -d "$STACK_DIR" ]]; then
  echo "ERROR: Stack directory not found: ${STACK_DIR}" >&2
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Stack  : ${STACK_PATH}"
echo " Action : ${ACTION}"
[[ -n "$PLAN_FILE" ]] && echo " Plan   : ${PLAN_FILE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$STACK_DIR"

case "$ACTION" in
  validate)
    tofu init -backend=false -input=false
    tofu validate
    echo "✓ Validation passed for ${STACK_PATH}"
    ;;

  plan)
    if [[ -n "$PLAN_FILE" ]]; then
      terragrunt plan -detailed-exitcode -out="${PLAN_FILE}"
    else
      terragrunt plan -detailed-exitcode
    fi
    ;;

  apply)
    if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
      terragrunt apply --terragrunt-non-interactive "${PLAN_FILE}"
    else
      # No saved plan — run apply directly (auto-approves within terragrunt)
      terragrunt apply --terragrunt-non-interactive
    fi
    echo "✓ Applied ${STACK_PATH}"
    ;;

  *)
    echo "ERROR: Unknown action '${ACTION}'. Must be validate, plan, or apply." >&2
    exit 1
    ;;
esac
