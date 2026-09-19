[CmdletBinding()]
param(
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$scriptPath = Join-Path $ProjectRoot "tools/pre-pr-validation.ps1"
$outputDirectory = Join-Path ([IO.Path]::GetTempPath()) ("toddler-match-pre-pr-contract-" + [Guid]::NewGuid().ToString("N"))

try {
    & $scriptPath -ProjectRoot $ProjectRoot -ValidateOnly -OutputDirectory $outputDirectory
    if ($LASTEXITCODE -ne 0) { throw "Pre-PR validation contract run failed with exit code $LASTEXITCODE" }

    $receiptPath = Join-Path $outputDirectory "receipt.json"
    $bodyPath = Join-Path $outputDirectory "pr-body.md"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "Receipt was not emitted" }
    if (-not (Test-Path -LiteralPath $bodyPath -PathType Leaf)) { throw "PR body summary was not emitted" }

    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ([int]$receipt.schema_version -ne 1) { throw "Unexpected receipt schema version" }
    if ([string]$receipt.status -ne "pass") { throw "Contract receipt did not pass" }
    if ([string]$receipt.head_sha -notmatch '^[0-9a-fA-F]{40}$') { throw "Receipt head_sha is invalid" }
    if ([string]$receipt.stasis.release_id -notmatch '^nightly-[0-9]{8}-[0-9]+$') { throw "Receipt Stasis release is invalid" }
    if ([string]$receipt.stasis.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw "Receipt Stasis checksum is invalid" }
    try { [DateTimeOffset]::Parse([string]$receipt.timestamp) | Out-Null } catch { throw "Receipt timestamp is invalid" }

    $checkNames = @($receipt.checks | ForEach-Object { [string]$_.name })
    foreach ($requiredName in @("manifest-pin", "head-sha", "full-local-validation")) {
        if ($checkNames -notcontains $requiredName) { throw "Receipt is missing check: $requiredName" }
    }
    $body = Get-Content -LiteralPath $bodyPath -Raw
    foreach ($requiredText in @("Local pre-PR validation", "Pinned Stasis", "Receipt:")) {
        if ($body -notmatch [Regex]::Escape($requiredText)) { throw "PR body summary is missing: $requiredText" }
    }
    $prWorkflow = Get-Content -LiteralPath (Join-Path $ProjectRoot ".github/workflows/pr-stasis-check.yml") -Raw
    foreach ($requiredText in @("workflow_dispatch:", "Required-check sentinel", "github.event.pull_request.head.sha || github.sha")) {
        if ($prWorkflow -notmatch [Regex]::Escape($requiredText)) { throw "PR workflow contract is missing: $requiredText" }
    }
    $quarterly = Get-Content -LiteralPath (Join-Path $ProjectRoot ".github/workflows/quarterly-stasis.yml") -Raw
    foreach ($requiredText in @("pin-update-pr:", "git add stasis.json vendor/stasis", "gh pr create", "gh workflow run pr-stasis-check.yml")) {
        if ($quarterly -notmatch [Regex]::Escape($requiredText)) { throw "Quarterly pin contract is missing: $requiredText" }
    }
    if ($quarterly -match [Regex]::Escape("git push origin master")) { throw "Quarterly updater must not push directly to master" }
    Write-Output "Pre-PR validation receipt contract passed."
} finally {
    if (Test-Path -LiteralPath $outputDirectory) {
        Remove-Item -LiteralPath $outputDirectory -Recurse -Force
    }
}
