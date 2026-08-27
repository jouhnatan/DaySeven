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
# global_settings computes the two base scales and states the type scale, theme
# applies the UI scale to Material roles, and block_text_style derives footnotes
# from an editor style.
#
# There are no exceptions outside shared/ui. App settings used to be one, when
# it carried a design of its own; it is now built from the same tokens as
# everything else.
while IFS= read -r hit; do
  echo "fontSize must come from uiTextStyle or editorTextStyle:"
  echo "  $hit"
  fail=1
done < <(
  rg -n "fontSize:" lib \
    --glob '!lib/shared/ui/global_settings.dart' \
    --glob '!lib/shared/ui/block_text_style.dart' \
    --glob '!lib/shared/ui/theme.dart' || true
)

# --- colour must come from the palette --------------------------------------
# theme.dart states the palette; block_text_style turns a colour stored in a
# document into a Color, which is the user's content rather than the interface.
# Colors.transparent is not a colour — it is the absence of one.
#
# Everything else asks the theme, so that the interface cannot quietly grow a
# hue the system does not have.
while IFS= read -r hit; do
  echo "colour must come from the palette in shared/ui/theme.dart:"
  echo "  $hit"
  fail=1
done < <(
  rg -n "Color\(0x|Colors\.[a-z]" lib \
    --glob '!lib/shared/ui/theme.dart' \
    --glob '!lib/shared/ui/block_text_style.dart' \
    | rg -v "Colors\.transparent" || true
)

if [ "$fail" -eq 0 ]; then
  echo "Layer check passed: shared/ is self-contained and feature UI is decoupled."
fi
exit "$fail"
