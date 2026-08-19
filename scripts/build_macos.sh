#!/usr/bin/env bash
# Builds DaySeven for macOS and wraps it in a DMG that opens with a drag-to-
# Applications layout, because the app expects to live there.
#
# Signing and notarisation are the two commented steps at the end: they need an
# Apple Developer Program membership, and the build works without them apart
# from Gatekeeper warning the user on first launch.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG=${1:-release}
ENV_FILE=${ENV_FILE:-env/supabase.json}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy env/supabase.example.json and fill it in." >&2
  exit 1
fi

flutter build macos --"$CONFIG" --dart-define-from-file="$ENV_FILE"

APP="build/macos/Build/Products/$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}/dayseven.app"
OUT="build/dist"
DMG="$OUT/DaySeven.dmg"
STAGE="$OUT/stage"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/DaySeven.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname DaySeven -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "Built $DMG"

# Signing and notarisation, once certificates exist:
#
#   codesign --deep --force --options runtime --timestamp \
#     --entitlements macos/Runner/Release.entitlements \
#     --sign "Developer ID Application: <NAME> (<TEAMID>)" "$STAGE/DaySeven.app"
#   xcrun notarytool submit "$DMG" --keychain-profile <PROFILE> --wait
#   xcrun stapler staple "$DMG"
