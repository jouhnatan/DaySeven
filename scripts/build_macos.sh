#!/usr/bin/env bash
# Builds DaySeven for macOS and packages it two ways:
#
#   DaySeven.dmg         what a person downloads and drags to Applications
#   DaySeven-macos.zip   what an installed copy downloads to update itself
#
# The zip is not a convenience duplicate. The in-app updater has to unpack a
# bundle and move it into place; a DMG would mean mounting a disk image from
# inside the app it is about to replace. `ditto` is used rather than `zip`
# because an .app is full of symlinks and extended attributes that ordinary zip
# flattens, producing a bundle that no longer launches.
#
# Signing is optional and off by default. Set CODESIGN_IDENTITY to a
# "Developer ID Application: ..." identity to sign, and NOTARY_PROFILE to also
# notarise. Without them the build still works; Gatekeeper warns on first
# launch.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/pubspec_version.sh
source scripts/pubspec_version.sh

CONFIG=${1:-release}
ENV_FILE=${ENV_FILE:-env/supabase.json}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy env/supabase.example.json and fill it in." >&2
  exit 1
fi

echo "Building DaySeven $DS_VERSION_FULL for macOS"

flutter build macos --"$CONFIG" --dart-define-from-file="$ENV_FILE"

APP="build/macos/Build/Products/$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}/dayseven.app"
OUT="build/dist"
DMG="$OUT/DaySeven.dmg"
ZIP="$OUT/DaySeven-macos.zip"
STAGE="$OUT/stage"

rm -rf "$STAGE" "$DMG" "$ZIP"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/DaySeven.app"

# Sign the bundle before it is packaged, not after: once it is inside a DMG or
# a zip there is nothing left to sign, and a signature applied to the archive
# does not travel with the app that comes out of it.
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Signing with $CODESIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp \
    --entitlements macos/Runner/Release.entitlements \
    --sign "$CODESIGN_IDENTITY" "$STAGE/DaySeven.app"
fi

# Either way the bundle must carry a valid signature. Xcode ad-hoc signs it
# (CODE_SIGN_IDENTITY = "-"), and the updater relies on that still holding
# after it moves the bundle into /Applications.
codesign --verify --deep --strict "$STAGE/DaySeven.app"

ln -s /Applications "$STAGE/Applications"
hdiutil create -volname DaySeven -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm "$STAGE/Applications"

ditto -c -k --keepParent "$STAGE/DaySeven.app" "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Notarising"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

rm -rf "$STAGE"

shasum -a 256 "$DMG" "$ZIP"
echo "Built $DMG and $ZIP"
