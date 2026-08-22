#!/usr/bin/env bash
# Publishes a built macOS app to Supabase as the current release.
#
# Unlike Windows, macOS has no operating-system update feed: the row this
# writes into app_releases *is* the mechanism. The app reads it, compares it
# against its own version, and downloads download_url. So the upload must land
# before the row does — a row pointing at a zip that is still uploading would
# hand every client a broken update.
#
# Requires SUPABASE_SERVICE_ROLE_KEY. ENV_FILE defaults to env/supabase.json.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/pubspec_version.sh
source scripts/pubspec_version.sh

if [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "SUPABASE_SERVICE_ROLE_KEY is not set. Publishing writes the release feed, which no client-facing role may do." >&2
  exit 1
fi

ENV_FILE=${ENV_FILE:-env/supabase.json}
SUPABASE_URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["SUPABASE_URL"].rstrip("/"))' "$ENV_FILE")
PUBLIC_BASE="$SUPABASE_URL/storage/v1/object/public/releases"

OUT="build/dist"
DMG="$OUT/DaySeven.dmg"
ZIP="$OUT/DaySeven-macos.zip"

for f in "$DMG" "$ZIP"; do
  [[ -f "$f" ]] || { echo "Missing $f. Run scripts/build_macos.sh first." >&2; exit 1; }
done

upload() {
  local path=$1 object=$2 content_type=$3 cache=${4:-max-age=3600}
  echo "Uploading $object"
  curl --fail-with-body --silent --show-error \
    -X POST "$SUPABASE_URL/storage/v1/object/releases/$object" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Content-Type: $content_type" \
    -H "cache-control: $cache" \
    -H "x-upsert: true" \
    --data-binary "@$path" > /dev/null
}

# Version-stamped paths, so a client that started downloading before a newer
# release landed still finds the bytes it was promised.
upload "$ZIP" "macos/$DS_VERSION_NAME/DaySeven-macos.zip" "application/zip"
upload "$DMG" "macos/$DS_VERSION_NAME/DaySeven.dmg" "application/x-apple-diskimage"

SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
SIZE=$(wc -c < "$ZIP" | tr -d ' ')

# The zip is download_url because it is what the updater consumes; the dmg is
# install_url, the link offered when the in-place update cannot proceed.
curl --fail-with-body --silent --show-error \
  -X POST "$SUPABASE_URL/rest/v1/rpc/publish_release" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "$(python3 - "$DS_VERSION_NAME" "$DS_VERSION_BUILD" "$PUBLIC_BASE" "$SHA" "$SIZE" <<'PY'
import json, os, sys
name, build, base, sha, size = sys.argv[1:6]
print(json.dumps({
    "p_platform": "macos",
    "p_version": name,
    "p_build_number": int(build),
    "p_download_url": f"{base}/macos/{name}/DaySeven-macos.zip",
    "p_install_url": f"{base}/macos/{name}/DaySeven.dmg",
    "p_sha256": sha,
    "p_size_bytes": int(size),
    "p_release_notes": os.environ.get("RELEASE_NOTES") or None,
}))
PY
)" > /dev/null

echo "Published DaySeven $DS_VERSION_FULL for macOS."
echo "Download: $PUBLIC_BASE/macos/$DS_VERSION_NAME/DaySeven.dmg"
