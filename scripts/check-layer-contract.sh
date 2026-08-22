#!/usr/bin/env bash
# Verifies the foundation -> workload output contract.
#
# The workload layer reads foundation outputs through terraform_remote_state. That
# link exists only at run time: renaming or deleting an output passes fmt, validate,
# every module test and Trivy, and fails during a workload apply — in production, if
# that is where it lands first.
#
# This compares two lists of names: outputs referenced under workload/, and outputs
# declared in foundation/outputs.tf. No credentials, no providers, no state.
#
# LIMIT, on purpose: this checks names only. An output that keeps its name and
# changes meaning or type still passes. Guarding that needs typed interfaces, not a
# name check — see ARCHITECTURE.md §9.
set -euo pipefail

cd "$(dirname "$0")/.."

FOUNDATION_OUTPUTS="foundation/outputs.tf"
WORKLOAD_DIR="workload"

[ -f "$FOUNDATION_OUTPUTS" ] || { echo "not found: $FOUNDATION_OUTPUTS" >&2; exit 2; }

declared=$(grep -oE '^output "[^"]+"' "$FOUNDATION_OUTPUTS" | sed -E 's/^output "([^"]+)"/\1/' | sort -u)

# Matches both data.terraform_remote_state.foundation.outputs.X and the
# shorter form used inside provider blocks.
referenced=$(grep -rhoE 'terraform_remote_state\.foundation\.outputs\.[a-zA-Z0-9_]+' \
  --include='*.tf' "$WORKLOAD_DIR" \
  | sed -E 's/.*\.outputs\.([a-zA-Z0-9_]+)/\1/' | sort -u)

if [ -z "$referenced" ]; then
  echo "no foundation outputs referenced under $WORKLOAD_DIR/ — nothing to check"
  exit 0
fi

missing=""
for name in $referenced; do
  if ! printf '%s\n' "$declared" | grep -qx "$name"; then
    missing="${missing}${name}\n"
  fi
done

if [ -n "$missing" ]; then
  echo "FAIL: workload/ references foundation outputs that do not exist" >&2
  echo >&2
  printf "  missing: %b" "$missing" >&2
  echo "  declared in $FOUNDATION_OUTPUTS:" >&2
  printf '%s\n' "$declared" | sed 's/^/    /' >&2
  echo >&2
  echo "Either restore the output or update the consumer in $WORKLOAD_DIR/." >&2
  exit 1
fi

count=$(printf '%s\n' "$referenced" | wc -l | tr -d ' ')
echo "OK: all $count foundation outputs consumed by $WORKLOAD_DIR/ are declared"
printf '%s\n' "$referenced" | sed 's/^/  - /'
