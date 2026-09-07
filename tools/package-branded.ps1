[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('android-arm64', 'web')][string]$Target,
    [string]$StasisPath = 'stasis',
    [string]$Out = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Out) { $Out = "dist/$Target-branded" }
$outputRoot = if ([IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $projectRoot $Out }
$command = if ($Target -eq 'web') { 'package' } else { 'package-mobile' }
& $StasisPath $command --workspace $projectRoot --target $Target --out $outputRoot
if ($LASTEXITCODE -ne 0) { throw "Stasis packaging failed with exit code $LASTEXITCODE" }
if ($Target -eq 'web') {
    & (Join-Path $PSScriptRoot 'apply-branding.ps1') -WebRoot $outputRoot
} else {
    & (Join-Path $PSScriptRoot 'apply-branding.ps1') -AndroidRoot (Join-Path $outputRoot 'android')
}
