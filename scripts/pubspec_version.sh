#!/usr/bin/env bash
# Reads `version: X.Y.Z+B` out of pubspec.yaml — the bash half of
# pubspec_version.ps1, kept in step with it.
#
# Sourcing this exports:
#   DS_VERSION_FULL   1.3.0+5
#   DS_VERSION_NAME   1.3.0
#   DS_VERSION_BUILD  5
set -euo pipefail

_pubspec="$(dirname "${BASH_SOURCE[0]}")/../pubspec.yaml"

_line=$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$' "$_pubspec" | head -1 || true)
if [[ -z "$_line" ]]; then
  echo "pubspec.yaml has no 'version: X.Y.Z+B' line. The build number is not optional: it distinguishes consecutive releases of the same version." >&2
  exit 1
fi

DS_VERSION_FULL=$(echo "$_line" | sed -E 's/^version:[[:space:]]*//; s/[[:space:]]*$//')
DS_VERSION_NAME=${DS_VERSION_FULL%%+*}
DS_VERSION_BUILD=${DS_VERSION_FULL##*+}
export DS_VERSION_FULL DS_VERSION_NAME DS_VERSION_BUILD

# Running it directly prints the version, for CI steps that just want the value.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "$DS_VERSION_FULL"
fi
