[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$StasisPath,
    [switch]$RestoreToolchain,
    [switch]$SkipBrowserInstall,
    [switch]$ValidateOnly,
    [switch]$NoSandbox,
    [string]$OutputDirectory,
    [string]$ReceiptPath,
    [string]$PrBodyPath,
    [string]$PlaywrightRoot
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath($Path)
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Get-ProjectRelativePath {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = Resolve-FullPath $Path
    $rootWithSeparator = $script:ProjectRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($fullPath.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($rootWithSeparator.Length).Replace('\', '/')
    }
    return $fullPath.Replace('\', '/')
}

function Add-Check {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet("pass", "fail", "skip")][string]$Status,
        [double]$DurationSeconds = 0,
        [string]$ErrorMessage,
        [hashtable]$Details
    )
    $entry = [ordered]@{
        name = $Name
        status = $Status
        duration_seconds = [Math]::Round($DurationSeconds, 3)
    }
    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
        $entry.error = $ErrorMessage
    }
    if ($null -ne $Details) {
        foreach ($key in $Details.Keys) {
            $entry[$key] = $Details[$key]
        }
    }
    [void]$script:Checks.Add([pscustomobject]$entry)
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$Arguments = @()
    )
    $started = [DateTimeOffset]::UtcNow
    $output = @()
    $status = "fail"
    $errorMessage = $null
    $exitCode = 0
    Write-Host "==> $Name"
    try {
        $global:LASTEXITCODE = 0
        $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
        if ($null -ne $global:LASTEXITCODE) {
            $exitCode = [int]$global:LASTEXITCODE
        }
        $output | ForEach-Object { Write-Host $_ }
        if ($exitCode -ne 0) {
            throw "Command exited with code $exitCode"
        }
        $status = "pass"
    } catch {
        $errorMessage = $_.Exception.Message
        if ($output.Count -gt 0) {
            $output | Select-Object -Last 12 | ForEach-Object { Write-Host $_ }
        }
        throw
    } finally {
        $duration = ([DateTimeOffset]::UtcNow - $started).TotalSeconds
        $details = @{}
        if ($output.Count -gt 0) {
            $details.output_tail = @($output | Select-Object -Last 12)
        }
        Add-Check -Name $Name -Status $status -DurationSeconds $duration -ErrorMessage $errorMessage -Details $details
    }
}

function Resolve-Executable {
    param(
        [string]$Candidate,
        [Parameter(Mandatory)][string]$CommandName
    )
    if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            return (Resolve-FullPath $Candidate)
        }
        $resolved = Get-Command $Candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $resolved) {
            return $resolved.Source
        }
        throw "Unable to find executable: $Candidate"
    }
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        throw "Required executable is not on PATH: $CommandName"
    }
    return $command.Source
}

function Get-StasisExecutable {
    if (-not [string]::IsNullOrWhiteSpace($StasisPath)) {
        return Resolve-Executable -Candidate $StasisPath -CommandName "stasis"
    }

    $candidatePaths = @(
        (Join-Path $script:ProjectRoot ".release-toolchain/stasis.exe"),
        (Join-Path $script:ProjectRoot ".release-toolchain/bin/stasis")
    )
    foreach ($candidate in $candidatePaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return Resolve-FullPath $candidate
        }
    }
    return Resolve-Executable -CommandName "stasis"
}

function Test-BrowserReport {
    param(
        [Parameter(Mandatory)][string]$Browser,
        [Parameter(Mandatory)][string]$ReportPath
    )
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
        throw "Missing $Browser browser report: $ReportPath"
    }
    $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    if ([string]$report.browser -ne $Browser) {
        throw "Browser report identity mismatch: expected $Browser, got $($report.browser)"
    }
    $scenarios = if ($report.scenarios -is [array]) {
        @($report.scenarios | ForEach-Object { [string]$_.status })
    } else {
        @($report.scenarios.PSObject.Properties | ForEach-Object { [string]$_.Value.status })
    }
    if ($scenarios.Count -eq 0 -or @($scenarios | Where-Object { $_ -ne "pass" }).Count -ne 0) {
        throw "One or more $Browser browser regression scenarios did not pass"
    }
}

$script:ProjectRoot = Resolve-FullPath $ProjectRoot
$manifestPath = Join-Path $script:ProjectRoot "stasis.json"
$startedAt = [DateTimeOffset]::UtcNow
$script:Checks = New-Object System.Collections.ArrayList
$browserResults = New-Object System.Collections.ArrayList
$packageInfo = $null
$headSha = ""
$releaseId = ""
$releaseSha = ""
$status = "fail"
$errorSummary = $null
$playwrightEnvWasSet = Test-Path Env:PLAYWRIGHT_BROWSERS_PATH
$oldPlaywrightBrowsersPath = $env:PLAYWRIGHT_BROWSERS_PATH

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $runName = "{0}-{1}" -f $startedAt.ToString("yyyyMMdd-HHmmssfff"), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
    $OutputDirectory = Join-Path $script:ProjectRoot (Join-Path "output/pre-pr-validation" $runName)
}
$OutputDirectory = Resolve-FullPath $OutputDirectory
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
    $ReceiptPath = Join-Path $OutputDirectory "receipt.json"
}
if ([string]::IsNullOrWhiteSpace($PrBodyPath)) {
    $PrBodyPath = Join-Path $OutputDirectory "pr-body.md"
}
$ReceiptPath = Resolve-FullPath $ReceiptPath
$PrBodyPath = Resolve-FullPath $PrBodyPath

try {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Missing project manifest: $manifestPath"
    }
    $project = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $releaseId = [string]$project.vendor.stasis.release_id
    $releaseSha = [string]$project.vendor.stasis.sha256
    if ($releaseId -notmatch '^nightly-[0-9]{8}-[0-9]+$') {
        throw "Invalid pinned Stasis release: $releaseId"
    }
    if ($releaseSha -notmatch '^[0-9a-fA-F]{64}$') {
        throw "Invalid pinned Stasis checksum: $releaseSha"
    }
    Add-Check -Name "manifest-pin" -Status "pass" -Details @{ release_id = $releaseId; sha256 = $releaseSha }

    $headOutput = @(& git -C $script:ProjectRoot rev-parse HEAD 2>&1 | ForEach-Object { [string]$_ })
    if ($global:LASTEXITCODE -ne 0) { throw "Unable to determine the current Git head" }
    $headSha = ($headOutput -join "`n").Trim()
    if ($headSha -notmatch '^[0-9a-fA-F]{40}$') { throw "Git head is not a commit SHA: $headSha" }
    Add-Check -Name "head-sha" -Status "pass" -Details @{ head_sha = $headSha }

    if ($ValidateOnly) {
        Add-Check -Name "full-local-validation" -Status "skip" -Details @{ reason = "ValidateOnly requested" }
        $status = "pass"
    } else {
        $powerShellHost = (Get-Process -Id $PID).Path
        if ([string]::IsNullOrWhiteSpace($StasisPath) -and -not (Test-Path -LiteralPath (Join-Path $script:ProjectRoot ".release-toolchain/stasis.exe") -PathType Leaf) -and -not (Test-Path -LiteralPath (Join-Path $script:ProjectRoot ".release-toolchain/bin/stasis") -PathType Leaf) -and $RestoreToolchain) {
            $runningOnWindows = [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)
            $assetName = if ($runningOnWindows) { "stasis-nightly-win-x64.zip" } else { "stasis-nightly-linux-x64.tar.gz" }
            Invoke-Checked -Name "restore-pinned-stasis" -FilePath $powerShellHost -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $script:ProjectRoot "tools/restore-stasis-release.ps1"), "-AssetName", $assetName, "-ReleaseTag", $releaseId)
        }

        $stasis = Get-StasisExecutable
        Invoke-Checked -Name "stasis-vendor-status" -FilePath $stasis -Arguments @("vendor", "status", "--workspace", $script:ProjectRoot)
        Invoke-Checked -Name "stasis-fmt-check" -FilePath $stasis -Arguments @("fmt", "--check")
        Invoke-Checked -Name "stasis-check" -FilePath $stasis -Arguments @("check")
        Invoke-Checked -Name "stasis-test" -FilePath $stasis -Arguments @("test")
        Invoke-Checked -Name "vector-assets-check" -FilePath $powerShellHost -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $script:ProjectRoot "tools/promote-vector-assets.ps1"), "-Check")

        $packageDirectory = Join-Path $OutputDirectory "web"
        $packageOutputArgument = Get-ProjectRelativePath $packageDirectory
        Invoke-Checked -Name "package-web" -FilePath $stasis -Arguments @("package", "--target", "web", "--out", $packageOutputArgument)
        $packageEntries = New-Object System.Collections.ArrayList
        foreach ($relativeFile in @("index.html", "game.js", "game.wasm")) {
            $filePath = Join-Path $packageDirectory $relativeFile
            if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { throw "Web package is missing $relativeFile" }
            $file = Get-Item -LiteralPath $filePath
            if ($file.Length -le 0) { throw "Web package file is empty: $relativeFile" }
            $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
            [void]$packageEntries.Add([ordered]@{ path = $relativeFile; bytes = $file.Length; sha256 = $hash })
        }
        $packageInfo = [ordered]@{ directory = Get-ProjectRelativePath $packageDirectory; files = @($packageEntries) }
        Add-Check -Name "web-package-shape" -Status "pass" -Details @{ files = @($packageEntries) }

        $node = Resolve-Executable -CommandName "node"
        if ([string]::IsNullOrWhiteSpace($PlaywrightRoot)) {
            $PlaywrightRoot = Join-Path $script:ProjectRoot ".playwright-cli"
        }
        $PlaywrightRoot = Resolve-FullPath $PlaywrightRoot
        $playwrightPackage = Join-Path $PlaywrightRoot "node_modules/playwright"
        if (-not (Test-Path -LiteralPath (Join-Path $playwrightPackage "package.json") -PathType Leaf)) {
            if ($SkipBrowserInstall) { throw "Playwright is not installed at $playwrightPackage" }
            $npm = Resolve-Executable -CommandName "npm"
            Invoke-Checked -Name "install-playwright" -FilePath $npm -Arguments @("install", "--prefix", $PlaywrightRoot, "--no-save", "--no-package-lock", "playwright@1.58.2")
        }
        if (-not (Test-Path -LiteralPath (Join-Path $playwrightPackage "package.json") -PathType Leaf)) {
            throw "Playwright installation did not create $playwrightPackage"
        }
        $playwrightBinName = if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) { "playwright.cmd" } else { "playwright" }
        $playwrightBin = Join-Path $PlaywrightRoot (Join-Path "node_modules/.bin" $playwrightBinName)
        if (-not (Test-Path -LiteralPath $playwrightBin -PathType Leaf)) { throw "Missing Playwright CLI: $playwrightBin" }
        $browserCache = Join-Path $PlaywrightRoot "browsers"
        $env:PLAYWRIGHT_BROWSERS_PATH = $browserCache
        if (-not $SkipBrowserInstall) {
            Invoke-Checked -Name "install-playwright-browsers" -FilePath $playwrightBin -Arguments @("install", "chromium", "firefox")
        }

        $runner = Join-Path $script:ProjectRoot "tools/maddox-652-browser-regression.mjs"
        foreach ($browser in @("chromium", "firefox")) {
            $browserDirectory = Join-Path $OutputDirectory $browser
            $arguments = @($runner, "--package-dir", $packageDirectory, "--out", $browserDirectory, "--playwright-module", $playwrightPackage, "--browser", $browser)
            if ($NoSandbox -and $browser -eq "chromium") { $arguments += "--no-sandbox" }
            Invoke-Checked -Name "browser-$browser" -FilePath $node -Arguments $arguments
            $reportPath = Join-Path $browserDirectory "maddox-652-browser-report.json"
            Test-BrowserReport -Browser $browser -ReportPath $reportPath
            [void]$browserResults.Add([ordered]@{ browser = $browser; report = Get-ProjectRelativePath $reportPath; status = "pass" })
            Add-Check -Name "browser-$browser-report" -Status "pass" -Details @{ report = Get-ProjectRelativePath $reportPath }
        }
        $status = "pass"
    }
} catch {
    $status = "fail"
    $errorSummary = $_.Exception.Message
    Write-Host "ERROR: $errorSummary"
} finally {
    if ($playwrightEnvWasSet) {
        $env:PLAYWRIGHT_BROWSERS_PATH = $oldPlaywrightBrowsersPath
    } else {
        Remove-Item Env:PLAYWRIGHT_BROWSERS_PATH -ErrorAction SilentlyContinue
    }
    $finishedAt = [DateTimeOffset]::UtcNow
    $receipt = [ordered]@{
        schema_version = 1
        status = $status
        head_sha = $headSha
        stasis = [ordered]@{ release_id = $releaseId; sha256 = $releaseSha }
        timestamp = $finishedAt.ToString("o")
        started_at = $startedAt.ToString("o")
        finished_at = $finishedAt.ToString("o")
        checks = @($script:Checks)
        package = $packageInfo
        browsers = @($browserResults)
    }
    if (-not [string]::IsNullOrWhiteSpace($errorSummary)) { $receipt.error = $errorSummary }
    Write-Utf8NoBom -Path $ReceiptPath -Text ($receipt | ConvertTo-Json -Depth 12)

    $bodyLines = New-Object System.Collections.Generic.List[string]
    [void]$bodyLines.Add("# Local pre-PR validation")
    [void]$bodyLines.Add("")
    [void]$bodyLines.Add("- Status: **$status**")
    [void]$bodyLines.Add("- Head: $headSha")
    [void]$bodyLines.Add("- Pinned Stasis: $releaseId ($releaseSha)")
    [void]$bodyLines.Add("- Timestamp: $($finishedAt.ToString('o'))")
    [void]$bodyLines.Add("")
    [void]$bodyLines.Add("Checks:")
    foreach ($check in @($script:Checks)) {
        [void]$bodyLines.Add("- $($check.name): **$($check.status)**")
    }
    if ($null -ne $packageInfo) {
        [void]$bodyLines.Add("")
        [void]$bodyLines.Add("Web package: $($packageInfo.directory)")
        foreach ($file in @($packageInfo.files)) {
            [void]$bodyLines.Add("- $($file.path): $($file.bytes) bytes, SHA-256 $($file.sha256)")
        }
    }
    foreach ($browserResult in @($browserResults)) {
        [void]$bodyLines.Add("- $($browserResult.browser) report: $($browserResult.report) ($($browserResult.status))")
    }
    if (-not [string]::IsNullOrWhiteSpace($errorSummary)) {
        [void]$bodyLines.Add("")
        [void]$bodyLines.Add("Error: $errorSummary")
    }
    [void]$bodyLines.Add("")
    [void]$bodyLines.Add("Receipt: $(Get-ProjectRelativePath $ReceiptPath)")
    [void]$bodyLines.Add("The hosted PR gate intentionally repeats only the pinned identity/vendor/fmt/check/vector policy; it does not repeat this package/browser run.")
    Write-Utf8NoBom -Path $PrBodyPath -Text ($bodyLines -join "`n")
}

if ($status -ne "pass") {
    exit 1
}
Write-Host "Pre-PR validation passed. Receipt: $(Get-ProjectRelativePath $ReceiptPath)"
