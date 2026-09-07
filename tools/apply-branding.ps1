[CmdletBinding(DefaultParameterSetName = 'Android')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Android')][string]$AndroidRoot,
    [Parameter(Mandatory, ParameterSetName = 'Web')][string]$WebRoot
)

$ErrorActionPreference = 'Stop'
$branding = Join-Path (Split-Path -Parent $PSScriptRoot) 'branding'

if ($PSCmdlet.ParameterSetName -eq 'Android') {
    $manifestPath = Join-Path $AndroidRoot 'app/src/main/AndroidManifest.xml'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Package the Android project before applying branding: $manifestPath"
    }
    $resources = Join-Path $branding 'android/res'
    if (-not (Test-Path -LiteralPath (Join-Path $resources 'mipmap-anydpi-v26/ic_launcher.xml'))) {
        throw "Missing committed launcher resources: $resources"
    }
    $destination = Join-Path $AndroidRoot 'app/src/main/res'
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Get-ChildItem -LiteralPath $resources | Copy-Item -Destination $destination -Recurse -Force
    $manifest = [xml](Get-Content -LiteralPath $manifestPath -Raw)
    $application = $manifest.SelectSingleNode('/manifest/application')
    if ($null -eq $application) { throw 'Android manifest has no application element' }
    $namespace = 'http://schemas.android.com/apk/res/android'
    $application.SetAttribute('icon', $namespace, '@mipmap/ic_launcher') | Out-Null
    $application.SetAttribute('roundIcon', $namespace, '@mipmap/ic_launcher') | Out-Null
    $manifest.Save([IO.Path]::GetFullPath($manifestPath))
    Write-Output "Android launcher icon applied: $manifestPath"
} else {
    $indexPath = Join-Path $WebRoot 'index.html'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        throw "Package the web project before applying branding: $indexPath"
    }
    $html = Get-Content -LiteralPath $indexPath -Raw
    if ($html -notmatch '(?i)</head>') { throw 'Web entry has no closing head element' }
    $html = [regex]::Replace($html, '(?i)<link\b[^>]*\brel\s*=\s*["''](?:icon|shortcut icon|apple-touch-icon)["''][^>]*>\s*', '')
    foreach ($file in @('favicon.ico', 'icon-192.png', 'icon-512.png', 'apple-touch-icon.png')) {
        Copy-Item -LiteralPath (Join-Path $branding "web/$file") -Destination (Join-Path $WebRoot $file) -Force
    }
    $links = '<link rel="icon" href="favicon.ico" sizes="any">' + "`n" +
        '<link rel="icon" type="image/png" href="icon-192.png" sizes="192x192">' + "`n" +
        '<link rel="apple-touch-icon" href="apple-touch-icon.png">' + "`n"
    $html = [regex]::Replace($html, '(?i)</head>', $links + '</head>')
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($indexPath), $html, [Text.UTF8Encoding]::new($false))
    Write-Output "Web icons applied: $indexPath"
}
