#!/usr/bin/env bash
# tofu_apply.sh — applies a saved plan for a single stack.
#
# Usage:
#   tofu_apply.sh <stack_rel_path> <plan_file>

set -euo pipefail

STACK_REL_PATH="${1:?stack_rel_path required}"
PLAN_FILE="${2:?plan_file required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${SCRIPT_DIR}/../live/${STACK_REL_PATH}"

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: plan file not found: ${PLAN_FILE}" >&2
  exit 1
fi

echo "=== Applying: ${STACK_REL_PATH} ==="
cd "$STACK_DIR"
terragrunt apply --terragrunt-non-interactive "${PLAN_FILE}"
echo "=== Apply complete: ${STACK_REL_PATH} ==="
