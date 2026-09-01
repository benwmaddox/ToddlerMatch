[CmdletBinding()]
param(
    [string]$StasisPath = "",
    [string]$DebugKeystorePath = "",
    [ValidateRange(1, 2100000000)]
    [int]$VersionCode = 1,
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]{0,49}$')]
    [string]$VersionName = "1.0.0"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$stasis = if ($StasisPath) { [IO.Path]::GetFullPath($StasisPath) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot ".release-toolchain/stasis.exe")) }
$androidSdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { throw "ANDROID_HOME or ANDROID_SDK_ROOT is required" }
$debugStore = if ($DebugKeystorePath) { [IO.Path]::GetFullPath($DebugKeystorePath) } elseif ($env:WEEKLY_ANDROID_DEBUG_KEYSTORE_PATH) { [IO.Path]::GetFullPath($env:WEEKLY_ANDROID_DEBUG_KEYSTORE_PATH) } else { throw "A stable debug keystore path is required" }
$gradle = Join-Path $projectRoot "vendor/android-deps/gradle-8.11.1/bin/gradle.bat"
$packageOutput = "dist/android-weekly"
$androidRoot = Join-Path $projectRoot "$packageOutput/android"
$appGradlePath = Join-Path $androidRoot "app/build.gradle"
$rootGradlePath = Join-Path $androidRoot "build.gradle"

foreach ($required in @($stasis, $debugStore, $gradle)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing Android build dependency: $required" }
}
New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot "dist") | Out-Null
if (Test-Path -LiteralPath (Join-Path $projectRoot $packageOutput)) { Remove-Item -LiteralPath (Join-Path $projectRoot $packageOutput) -Recurse -Force }

$env:STASIS_SDL3_SOURCE = [IO.Path]::GetFullPath((Join-Path $projectRoot "vendor/android-deps/SDL3"))
$env:STASIS_SDL3_IMAGE_SOURCE = [IO.Path]::GetFullPath((Join-Path $projectRoot "vendor/android-deps/SDL3_image"))
$env:WEEKLY_ANDROID_DEBUG_STORE_FILE = $debugStore
$env:GRADLE_USER_HOME = [IO.Path]::GetFullPath((Join-Path $projectRoot ".gradle-cache"))
$env:CMAKE_BUILD_PARALLEL_LEVEL = "2"

Push-Location $projectRoot
try {
    & $stasis package-mobile --target android-arm64 --workspace $projectRoot --entry src/main.stasis --out $packageOutput
    if ($LASTEXITCODE -ne 0) { throw "Stasis Android packaging failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }

if (-not (Test-Path -LiteralPath $appGradlePath -PathType Leaf)) { throw "Generated Android app project is missing: $appGradlePath" }
$rootGradle = Get-Content -LiteralPath $rootGradlePath -Raw
$rootGradle = $rootGradle.Replace("id 'com.android.application' version '8.7.3'", "id 'com.android.application' version '8.10.1'")
if ($rootGradle -notmatch "id 'com.android.application' version '8.10.1'") { throw "Generated project did not accept Android Gradle Plugin 8.10.1" }
[IO.File]::WriteAllText($rootGradlePath, $rootGradle, [Text.UTF8Encoding]::new($false))

$appGradle = Get-Content -LiteralPath $appGradlePath -Raw
$appGradle = $appGradle.Replace('compileSdk 35', 'compileSdk 36').Replace('targetSdk 35', 'targetSdk 36')
$appGradle = [regex]::Replace($appGradle, '(?m)^(\s*)versionCode\s+\d+\s*$', "`$1versionCode $VersionCode")
$appGradle = [regex]::Replace($appGradle, "(?m)^(\s*)versionName\s+'[^']*'\s*$", "`$1versionName '$VersionName'")
$signing = @'
def weeklyDebugStoreFile = providers.environmentVariable('WEEKLY_ANDROID_DEBUG_STORE_FILE')
def weeklyDebugSigningAvailable = weeklyDebugStoreFile.isPresent()

'@
if ($appGradle -notmatch 'weeklyDebugSigningAvailable') { $appGradle = $appGradle.Replace('android {', "$signing`r`nandroid {") }
$releaseSigningConfig = @'
    signingConfigs {
        release {
            if (weeklyDebugSigningAvailable) {
                storeFile file(weeklyDebugStoreFile.get())
                storePassword 'android'
                keyAlias 'androiddebugkey'
                keyPassword 'android'
            }
        }
    }

'@
if ($appGradle -notmatch 'release \{ signingConfig signingConfigs\.release \}') {
    $appGradle = $appGradle.Replace('android {', "android {`r`n$releaseSigningConfig    buildTypes {`r`n        release { signingConfig signingConfigs.release }`r`n    }`r`n")
}
if ($appGradle -notmatch 'compileSdk 36' -or $appGradle -notmatch 'targetSdk 36' -or $appGradle -notmatch "versionCode $VersionCode" -or $appGradle -notmatch [regex]::Escape("versionName '$VersionName'") -or $appGradle -notmatch 'weeklyDebugStoreFile' -or $appGradle -notmatch '(?s)signingConfigs\s*\{\s*release\s*\{.*?weeklyDebugSigningAvailable' -or $appGradle -notmatch 'release \{ signingConfig signingConfigs\.release \}') { throw "Generated Gradle project did not accept weekly Android release configuration" }
[IO.File]::WriteAllText($appGradlePath, $appGradle, [Text.UTF8Encoding]::new($false))

$apksigner = Join-Path $androidSdk "build-tools/36.0.0/apksigner.bat"
if (-not (Test-Path -LiteralPath $apksigner -PathType Leaf)) { throw "Pinned Android build tools are missing apksigner: $apksigner" }
Push-Location (Join-Path $projectRoot "$packageOutput/android")
try {
    & $gradle ':app:assembleRelease' '--no-daemon' '--max-workers=2' '--console=plain'
    if ($LASTEXITCODE -ne 0) { throw "Gradle Android build failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }

$generatedApk = Join-Path $androidRoot "app/build/outputs/apk/release/app-release.apk"
$artifact = Join-Path $projectRoot "toddler-match-$VersionName-android-arm64.apk"
if (-not (Test-Path -LiteralPath $generatedApk -PathType Leaf) -or (Get-Item -LiteralPath $generatedApk).Length -le 0) { throw "Gradle did not produce a non-empty APK" }
Copy-Item -LiteralPath $generatedApk -Destination $artifact -Force

$verification = (& $apksigner verify --verbose --print-certs $artifact 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed: $verification" }
$digestPattern = 'Signer #1 certificate SHA-256 digest:\s*([0-9A-Fa-f:]+)'
if ($verification -notmatch $digestPattern) { throw "APK signature audit did not report a certificate SHA-256 digest" }
$digest = $Matches[1].Replace(':', '').ToLowerInvariant()
if ($digest -ne 'e2b1ba76e567a8db3937f87771c4eaa153ae652647bb7bbf4ded20426fcabd67') { throw "APK signer mismatch: expected e2b1ba76e567a8db3937f87771c4eaa153ae652647bb7bbf4ded20426fcabd67, got $digest" }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($artifact)
try {
    $nativeArm64 = @($archive.Entries | Where-Object { $_.FullName -like 'lib/arm64-v8a/*.so' })
    if ($nativeArm64.Count -eq 0) { throw 'APK architecture audit failed: no arm64-v8a native libraries found' }
} finally { $archive.Dispose() }
Write-Output "ANDROID_APK_OK|path=$artifact|signer_sha256=$digest|arm64_native_libs=$($nativeArm64.Count)"
