[CmdletBinding()]
param(
    [string]$StasisPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$androidDeps = Join-Path $projectRoot "vendor/android-deps"
$stasis = if ($StasisPath) {
    [IO.Path]::GetFullPath($StasisPath)
} else {
    [IO.Path]::GetFullPath((Join-Path $projectRoot ".release-toolchain/stasis.exe"))
}

if (-not (Test-Path -LiteralPath $stasis -PathType Leaf)) {
    throw "Restored Stasis executable is missing: $stasis"
}
New-Item -ItemType Directory -Force -Path $androidDeps | Out-Null

& $stasis vendor update --workspace $projectRoot
if ($LASTEXITCODE -ne 0) { throw "Stasis vendor update failed" }

function Restore-PinnedCheckout {
    param(
        [string]$Name,
        [string]$Repository,
        [string]$Commit,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath (Join-Path $Destination ".git") -PathType Container)) {
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
        git init $Destination
        if ($LASTEXITCODE -ne 0) { throw "Unable to initialize $Name checkout" }
        git -C $Destination remote add origin $Repository
        if ($LASTEXITCODE -ne 0) { throw "Unable to configure $Name repository" }
    }
    git -C $Destination fetch --depth 1 origin $Commit
    if ($LASTEXITCODE -ne 0) { throw "Unable to fetch pinned $Name commit $Commit" }
    git -C $Destination checkout --detach --force $Commit
    if ($LASTEXITCODE -ne 0) { throw "Unable to check out pinned $Name commit $Commit" }
    $actualCommit = (git -C $Destination rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $Commit) {
        throw "$Name checkout does not match pinned commit $Commit (actual: $actualCommit)"
    }
}

Restore-PinnedCheckout -Name "SDL3" `
    -Repository "https://github.com/libsdl-org/SDL.git" `
    -Commit "147a8ee32dbf9ac02f3794964490687b6bbda1bc" `
    -Destination (Join-Path $androidDeps "SDL3")
Restore-PinnedCheckout -Name "SDL3_image" `
    -Repository "https://github.com/libsdl-org/SDL_image.git" `
    -Commit "bec9134a26c7d0f31b36d6083c25296e04cabff5" `
    -Destination (Join-Path $androidDeps "SDL3_image")

$gradleZip = Join-Path $androidDeps "gradle-8.11.1-bin.zip"
$gradleRoot = Join-Path $androidDeps "gradle-8.11.1"
$gradleExe = Join-Path $gradleRoot "bin/gradle.bat"
if (-not (Test-Path -LiteralPath $gradleExe -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath $gradleZip -PathType Leaf)) {
        Invoke-WebRequest -Uri "https://services.gradle.org/distributions/gradle-8.11.1-bin.zip" -OutFile $gradleZip
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $gradleZip).Hash
    if ($hash -ne "F397B287023ACDBA1E9F6FC5EA72D22DD63669D59ED4A289A29B1A76EEE151C6") {
        throw "Gradle 8.11.1 archive failed SHA-256 verification"
    }
    Expand-Archive -LiteralPath $gradleZip -DestinationPath $androidDeps -Force
}
if (-not (Test-Path -LiteralPath $gradleExe -PathType Leaf)) {
    throw "Pinned Gradle 8.11.1 executable is missing: $gradleExe"
}

Write-Host "Pinned Android dependencies are ready: SDL3=$((git -C (Join-Path $androidDeps 'SDL3') rev-parse HEAD).Trim()), SDL3_image=$((git -C (Join-Path $androidDeps 'SDL3_image') rev-parse HEAD).Trim())"
