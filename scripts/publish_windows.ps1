# Publishes a built Windows zip to Supabase as the current release.
#
# The upload has to land before the row does. The row is what clients read to
# decide there is something newer, so writing it first would briefly point
# every client at an archive that is still uploading.
#
# Requires:
#   SUPABASE_SERVICE_ROLE_KEY   bypasses RLS; the only role allowed to publish
#   ENV_FILE                    optional, defaults to env/supabase.json

$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

if (-not $env:SUPABASE_SERVICE_ROLE_KEY) {
    throw "SUPABASE_SERVICE_ROLE_KEY is not set. Publishing writes the release feed, which no client-facing role may do."
}

$envFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { "env/supabase.json" }
$buildConfig = Get-Content -Raw $envFile | ConvertFrom-Json
$supabaseUrl = $buildConfig.SUPABASE_URL.TrimEnd('/')
$publicBase = "$supabaseUrl/storage/v1/object/public/releases"

$version = & "$PSScriptRoot\pubspec_version.ps1"

$zip = "dist\DaySeven-Windows-x64.zip"
if (-not (Test-Path $zip)) {
    throw "No archive at $zip. Run scripts\build_windows.ps1 first."
}

$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLowerInvariant()
$size = (Get-Item $zip).Length
$object = "windows/$($version.Name)/DaySeven-Windows-x64.zip"

Write-Host "Uploading $object"
Invoke-RestMethod `
    -Method Post `
    -Uri "$supabaseUrl/storage/v1/object/releases/$object" `
    -Headers @{
        "Authorization" = "Bearer $env:SUPABASE_SERVICE_ROLE_KEY"
        "apikey"        = $env:SUPABASE_SERVICE_ROLE_KEY
        "x-upsert"      = "true"
        "cache-control" = "max-age=3600"
    } `
    -ContentType "application/zip" `
    -InFile $zip | Out-Null

# download_url and install_url are the same file here: there is only one thing
# to fetch, whether the app unpacks it or a person does.
$body = @{
    p_platform      = "windows"
    p_version       = $version.Name
    p_build_number  = $version.Build
    p_download_url  = "$publicBase/$object"
    p_install_url   = "$publicBase/$object"
    p_sha256        = $hash
    p_size_bytes    = $size
    p_release_notes = $env:RELEASE_NOTES
} | ConvertTo-Json -Compress

Invoke-RestMethod `
    -Method Post `
    -Uri "$supabaseUrl/rest/v1/rpc/publish_release" `
    -Headers @{
        "Authorization" = "Bearer $env:SUPABASE_SERVICE_ROLE_KEY"
        "apikey"        = $env:SUPABASE_SERVICE_ROLE_KEY
    } `
    -ContentType "application/json" `
    -Body $body | Out-Null

Write-Host "Published DaySeven $($version.Full) for Windows."
