# Builds DaySeven for Windows 11 and zips it.
#
# A Flutter Windows build is a folder — dayseven.exe, the Flutter DLLs, and
# data/ — so the zip is that folder, and installing is extracting it somewhere
# writable. There is no installer and no signing certificate: the app updates
# itself from the release feed rather than through anything the operating
# system manages, which is the whole reason it can be this plain.
#
# The trade is a one-time SmartScreen warning the first time an unsigned
# executable runs. Everything after that, including every update, is silent.

$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

$envFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { "env/supabase.json" }
if (-not (Test-Path $envFile)) {
    Write-Error "Missing $envFile. Copy env/supabase.example.json and fill it in."
}

try {
    $buildConfig = Get-Content -Raw $envFile | ConvertFrom-Json
} catch {
    throw "Could not read Supabase build configuration from ${envFile}: $($_.Exception.Message)"
}
if (-not $buildConfig.SUPABASE_URL) {
    throw "SUPABASE_URL is missing from $envFile."
}
if (-not $buildConfig.SUPABASE_PUBLISHABLE_KEY) {
    throw "SUPABASE_PUBLISHABLE_KEY is missing from $envFile."
}

$version = & "$PSScriptRoot\pubspec_version.ps1"
Write-Host "Building DaySeven $($version.Full) for Windows"

flutter build windows --release --dart-define-from-file=$envFile
if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows failed with exit code $LASTEXITCODE."
}

$release = "build\windows\x64\runner\Release"
if (-not (Test-Path "$release\dayseven.exe")) {
    throw "The build completed without producing $release\dayseven.exe."
}

New-Item -ItemType Directory -Force -Path dist | Out-Null
$zip = "dist\DaySeven-Windows-x64.zip"
Remove-Item $zip -ErrorAction SilentlyContinue

# The contents of Release\, not the folder itself: the updater replaces an
# install directory in place, so the archive has to unpack to the same shape
# the install already has.
Compress-Archive -Path "$release\*" -DestinationPath $zip -CompressionLevel Optimal

@"
DAYSEVEN FOR WINDOWS

1. Extract this ZIP somewhere you can write to — somewhere under your user
   folder is ideal. Program Files is not: DaySeven updates itself by replacing
   its own files, and that needs write access without prompting for admin.
2. Run dayseven.exe.
3. Windows will warn that it does not recognise the app, because it is not
   signed. Choose "More info", then "Run anyway". This happens once.

After that, use Menu (top right) -> Run updates to move to a newer version.
DaySeven downloads it, replaces itself and reopens.
"@ | Set-Content -Path "dist\INSTALL.txt" -Encoding utf8

Write-Host "Built $zip"
