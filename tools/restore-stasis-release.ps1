[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(
        "stasis-nightly-win-x64.zip",
        "stasis-nightly-linux-x64.tar.gz",
        "stasis-nightly-osx-arm64.tar.gz"
    )]
    [string]$AssetName,
    [string]$ReleaseTag,
    [string]$Destination = ".release-toolchain",
    [string]$Repository = "benwmaddox/StasisLang"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
    $ReleaseTag = (& (Join-Path $PSScriptRoot "resolve-stasis-nightly.ps1") -Repository $Repository | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($ReleaseTag)) { throw "Unable to resolve the latest complete Stasis nightly" }
}

$headers = @{
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "Stasis-weekly-release-builder"
}
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)"
}
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/tags/$ReleaseTag" -Headers $headers
$assets = @($release.assets | Where-Object { [string]($_.name) -eq $AssetName })
if ($assets.Count -ne 1) { throw "Release $ReleaseTag did not contain exactly one $AssetName asset" }
$asset = $assets[0]
$digest = [string]($asset.digest)
if ($digest -notmatch '^sha256:[0-9a-fA-F]{64}$') {
    throw "GitHub did not provide a SHA-256 digest for $AssetName"
}

$destinationFull = [IO.Path]::GetFullPath((Join-Path $projectRoot $Destination))
$projectFull = [IO.Path]::GetFullPath($projectRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$destinationWithSeparator = $destinationFull.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $destinationWithSeparator.StartsWith($projectFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to restore the toolchain outside the project: $destinationFull"
}
if (Test-Path -LiteralPath $destinationFull) { Remove-Item -LiteralPath $destinationFull -Recurse -Force }
New-Item -ItemType Directory -Force -Path $destinationFull | Out-Null
$archivePath = Join-Path $destinationFull $AssetName
Invoke-WebRequest -Uri $asset.browser_download_url -Headers @{ "User-Agent" = "Stasis-weekly-release-builder" } -OutFile $archivePath
$actualDigest = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedDigest = $digest.Substring(7).ToLowerInvariant()
if ($actualDigest -ne $expectedDigest) {
    throw "Stasis toolchain digest mismatch for $AssetName (expected $expectedDigest, actual $actualDigest)"
}

if ($AssetName.EndsWith(".zip", [StringComparison]::OrdinalIgnoreCase)) {
    $extractRoot = Join-Path $destinationFull ".extract"
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot
    $exeInArchive = Join-Path $extractRoot "stasis.exe"
    if (-not (Test-Path -LiteralPath $exeInArchive -PathType Leaf)) {
        $exeInArchive = (Get-ChildItem -LiteralPath $extractRoot -Filter stasis.exe -File -Recurse | Select-Object -First 1).FullName
    }
    if ([string]::IsNullOrWhiteSpace($exeInArchive)) { throw "Archive did not contain stasis.exe" }
    $archiveRoot = Split-Path -Parent $exeInArchive
    Get-ChildItem -LiteralPath $archiveRoot -Force | Move-Item -Destination $destinationFull -Force
    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
} else {
    & tar -xzf $archivePath -C $destinationFull --strip-components=1
    if ($LASTEXITCODE -ne 0) { throw "Unable to extract $AssetName" }
}
Remove-Item -LiteralPath $archivePath -Force

$executable = if ($AssetName -like "*-win-*") { Join-Path $destinationFull "stasis.exe" } else { Join-Path $destinationFull "bin/stasis" }
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw "Restored Stasis executable is missing: $executable" }
$runningOnWindows = [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)
if (-not $runningOnWindows) {
    & chmod +x $executable
    if ($LASTEXITCODE -ne 0) { throw "Unable to mark $executable executable" }
}
& $executable editor-info --json
if ($LASTEXITCODE -ne 0) { throw "Restored Stasis toolchain failed its editor-info probe" }
Write-Output "STASIS_RELEASE_OK|tag=$ReleaseTag|asset=$AssetName|sha256=$actualDigest|executable=$executable"
