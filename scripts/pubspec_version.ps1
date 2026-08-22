# Reads `version: X.Y.Z+B` out of pubspec.yaml.
#
# One version, one place. Everything downstream — the storage path, the row in
# app_releases, the tag CI checks against — is derived from this rather than
# kept in step by hand.
#
# Returns an object with:
#   Full  '1.3.0+5'   as written in pubspec.yaml
#   Name  '1.3.0'     CFBundleShortVersionString / the `version` column
#   Build 5           CFBundleVersion / the `build_number` column

$ErrorActionPreference = "Stop"

$pubspec = Join-Path $PSScriptRoot "..\pubspec.yaml"
$line = Select-String -Path $pubspec -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$' |
    Select-Object -First 1

if (-not $line) {
    throw "pubspec.yaml has no `version: X.Y.Z+B` line. The build number is not optional: it is what distinguishes two releases of the same version."
}

$name = $line.Matches[0].Groups[1].Value
$build = [int]$line.Matches[0].Groups[2].Value

[PSCustomObject]@{
    Full  = "$name+$build"
    Name  = $name
    Build = $build
}
