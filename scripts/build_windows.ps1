# Builds DaySeven for Windows 11 and packages it as an MSIX.
#
# Run from the repository root on a Windows machine with the Flutter Windows
# toolchain installed (Visual Studio 2022 with the "Desktop development with
# C++" workload).
#
# Signing needs an Authenticode certificate; without one the MSIX installs only
# with developer mode enabled. Set the certificate in pubspec.yaml's
# msix_config before releasing.

$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

$envFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { "env/supabase.json" }
if (-not (Test-Path $envFile)) {
    Write-Error "Missing $envFile. Copy env/supabase.example.json and fill it in."
}

flutter build windows --release --dart-define-from-file=$envFile
dart run msix:create

Write-Host "Built build/windows/x64/runner/Release and the MSIX beside it."
