#!/usr/bin/env bash
# Enforces the import rules that lib/'s layout is meant to express:
#
#   shared/   may not import app/ or features/ — it is the bottom of the stack
#   features/ may not import another feature — they meet in app/, not directly
#   app/      may import anything; it is the composition root
#
# Run from the repository root. Exits non-zero on the first violation found.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

# --- shared/ must not depend on anything above it ---------------------------
while IFS= read -r hit; do
  echo "shared/ may not import app/ or features/:"
  echo "  $hit"
  fail=1
done < <(grep -rn "^import 'package:dayseven/\(app\|features\)/" lib/shared || true)

# --- no feature may import another feature ----------------------------------
for dir in lib/features/*/; do
  feature=$(basename "$dir")
  while IFS= read -r hit; do
    # An import of this feature's own folder is fine; anything else is not.
    imported=$(sed -E "s|.*package:dayseven/features/([^/]+)/.*|\1|" <<<"$hit")
    [ "$imported" = "$feature" ] && continue
    echo "features/$feature may not import features/$imported:"
    echo "  $hit"
    fail=1
  done < <(grep -rn "^import 'package:dayseven/features/" "$dir" || true)
done

if [ "$fail" -eq 0 ]; then
  echo "Layer check passed: shared/ is self-contained and no feature imports another."
fi
exit "$fail"
