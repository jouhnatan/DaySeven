#!/usr/bin/env bash
# Enforces the import rules that lib/'s layout is meant to express:
#
#   shared/   may not import app/ or features/ — it is the bottom of the stack
#   features/ may not import another feature or shell UI
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
done < <(rg -n "^import 'package:dayseven/(app|features)/" lib/shared || true)

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
  done < <(rg -n "^import 'package:dayseven/features/" "$dir" || true)
done

# --- feature UI must not borrow general controls from the application shell --
while IFS= read -r hit; do
  echo "features/ may not import app/shell; move shared UI to shared/ui/:"
  echo "  $hit"
  fail=1
done < <(rg -n "^import 'package:dayseven/app/shell/" lib/features || true)

# --- rendered font sizes must flow through the global settings --------------
# global_settings computes the two base scales, theme applies the UI scale to
# Material roles, and block_text_style derives footnotes from an editor style.
#
# app_settings_design is the one exception outside shared/ui: the App settings
# dialog follows a fixed design with its own type scale, so it states its sizes
# rather than deriving them. It still multiplies them by the configured UI text
# size, so the preference is not ignored.
while IFS= read -r hit; do
  echo "fontSize must come from uiTextStyle or editorTextStyle:"
  echo "  $hit"
  fail=1
done < <(
  rg -n "fontSize:" lib \
    --glob '!lib/shared/ui/global_settings.dart' \
    --glob '!lib/shared/ui/block_text_style.dart' \
    --glob '!lib/shared/ui/theme.dart' \
    --glob '!lib/features/app_settings/ui/app_settings_design.dart' || true
)

if [ "$fail" -eq 0 ]; then
  echo "Layer check passed: shared/ is self-contained and feature UI is decoupled."
fi
exit "$fail"
