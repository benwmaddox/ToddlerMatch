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
    foreach ($requiredText in @("pin-update-pr:", "git add stasis.json vendor/stasis", "gh pr create")) {
        if ($quarterly -notmatch [Regex]::Escape($requiredText)) { throw "Quarterly pin contract is missing: $requiredText" }
    }
    if ($quarterly -match 'stasis-pin-sentinel\.yml') { throw "Quarterly updater must not add a standalone sentinel workflow" }
    if ($quarterly -match 'gh workflow run|gh pr merge') { throw "Quarterly updater must leave the pin PR for normal review" }
    if ($quarterly -match [Regex]::Escape("git push origin master")) { throw "Quarterly updater must not push directly to master" }
    if ($quarterly -notmatch '(?m)^\s*schedule:\s*\r?\n\s*- cron: "17 13 1 1,4,7,10 \*"') { throw "Quarterly pin workflow must keep the stable quarter-start schedule" }
    if ($quarterly -notmatch 'ref: master' -or $quarterly -notmatch 'origin/master') { throw "Quarterly pin branch must start from master" }
    if ($quarterly -notmatch 'force-with-lease') { throw "Quarterly updater must protect the automation branch with force-with-lease" }
    if ($quarterly -notmatch 'vendor update --workspace' -or $quarterly -notmatch 'vendor status --workspace') { throw "Quarterly updater must perform only mechanical vendor validation" }
    if ($quarterly -match 'pre-pr-validation\.ps1|stasis fmt|stasis check|stasis test|stasis package|build-android-apk') { throw "Quarterly updater must not gate the pin on compatibility or release builds" }
    if ($quarterly -match '(?m)^\s*(strategy|matrix):') { throw "Quarterly pin workflow must not fan out a release matrix" }
    if ($quarterly -match 'stasis package|build-android-apk') { throw "Quarterly pin workflow must not build release artifacts" }

    $weekly = Get-Content -LiteralPath (Join-Path $ProjectRoot ".github/workflows/weekly-release.yml") -Raw
    foreach ($requiredText in @('"stasis.json"', '"vendor/stasis"', 'vendor status --workspace', 'stasis_release=$pinnedStasis')) {
        if ($weekly -notmatch [Regex]::Escape($requiredText)) { throw "Weekly checked-in pin contract is missing: $requiredText" }
    }
    if ($weekly -notmatch '(?m)^\s*default: false\s*$') { throw "Weekly manual force must default to false" }
    if ($weekly -match 'resolve-stasis-nightly\.ps1') { throw "Weekly release must not resolve a moving Stasis nightly" }
    if ($weekly -match 'vendor update --workspace') { throw "Weekly release must not mutate the checked-in vendor snapshot" }
    Write-Output "Pre-PR validation receipt contract passed."
} finally {
    if (Test-Path -LiteralPath $outputDirectory) {
        Remove-Item -LiteralPath $outputDirectory -Recurse -Force
    }
}
