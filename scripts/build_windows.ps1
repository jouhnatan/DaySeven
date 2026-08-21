# Builds DaySeven for Windows 11 and packages it as an MSIX.
#
# Run from the repository root on a Windows machine with the Flutter Windows
# toolchain installed (Visual Studio 2022 with the "Desktop development with
# C++" workload).
#
# For a signed build, set MSIX_CERTIFICATE_PATH and
# MSIX_CERTIFICATE_PASSWORD. GitHub Actions creates a temporary test certificate
# and publishes its public half beside the installer. Use a publicly trusted
# code-signing certificate for a production release.

$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

$envFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { "env/supabase.json" }
if (-not (Test-Path $envFile)) {
    Write-Error "Missing $envFile. Copy env/supabase.example.json and fill it in."
}

flutter build windows --release --dart-define-from-file=$envFile
if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows failed with exit code $LASTEXITCODE."
}

$msixArguments = @("run", "msix:create")
if ($env:MSIX_CERTIFICATE_PATH) {
    if (-not (Test-Path $env:MSIX_CERTIFICATE_PATH)) {
        throw "MSIX certificate not found: $env:MSIX_CERTIFICATE_PATH"
    }
    if (-not $env:MSIX_CERTIFICATE_PASSWORD) {
        throw "MSIX_CERTIFICATE_PASSWORD is required when MSIX_CERTIFICATE_PATH is set."
    }

    $msixArguments += @(
        "--certificate-path", $env:MSIX_CERTIFICATE_PATH,
        "--certificate-password", $env:MSIX_CERTIFICATE_PASSWORD,
        "--install-certificate", "false"
    )
}

& dart $msixArguments
if ($LASTEXITCODE -ne 0) {
    throw "dart run msix:create failed with exit code $LASTEXITCODE."
}

Write-Host "Built build/windows/x64/runner/Release and the MSIX beside it."
