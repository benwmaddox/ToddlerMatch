param([switch]$Check)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$shapeRoot = Join-Path $root "assets/shapes"
$goalRoot = Join-Path $root "assets/goals"
$assetRoot = Join-Path $root "assets"
$configPath = Join-Path $PSScriptRoot "svg-optimizer-config.json"
$configHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $configPath).Hash.ToLowerInvariant()
$colors = [ordered]@{ red="#ff5252"; green="#4caf50"; blue="#2196f3"; yellow="#f6d600"; black="#111111" }
$geometry = [ordered]@{
  circle='<circle cx="50" cy="50" r="40" fill="{0}"/>'
  square='<rect x="15" y="15" width="70" height="70" fill="{0}"/>'
  triangle='<polygon points="50,10 90,85 10,85" fill="{0}"/>'
  hexagon='<polygon points="50,5 90,25 90,75 50,95 10,75 10,25" fill="{0}"/>'
  star='<polygon points="50,5 63,38 98,38 70,59 79,95 50,75 21,95 30,59 2,38 37,38" fill="{0}"/>'
  curvy='<path d="M12 70C28 16 47 16 50 50S75 84 88 30" fill="none" stroke="{0}" stroke-linecap="round" stroke-linejoin="round" stroke-width="14"/>'
}
$assets = New-Object System.Collections.Generic.List[string]
function Add-Asset([string]$relative,[string]$body) {
  $canonical = "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"100`" height=`"100`" viewBox=`"0 0 100 100`">$body</svg>`n"
  $canonicalPath = Join-Path $assetRoot $relative
  if ($canonical -match '<(script|style|text|image|foreignObject|filter|mask|pattern|animate|animateTransform)\b' -or $canonical -match '(href|url\()') { throw "Forbidden SVG structure in $relative" }
  $fixedPoint = $canonical -replace ">\s+<","><"
  if ($fixedPoint -cne $canonical) { throw "Optimizer fixed point failed for $relative" }
  if ($Check) {
    if (!(Test-Path -LiteralPath $canonicalPath)) { throw "Missing canonical asset $relative" }
    if ((Get-Content -Raw -LiteralPath $canonicalPath) -cne $canonical) { throw "Canonical vector drift: $relative" }
  } else {
    New-Item -ItemType Directory -Force (Split-Path -Parent $canonicalPath) | Out-Null
    [IO.File]::WriteAllText($canonicalPath,$canonical,[Text.UTF8Encoding]::new($false))
  }
  $assets.Add($relative.Replace('\','/'))
}
foreach ($shape in $geometry.Keys) {
  foreach ($color in $colors.Keys) { Add-Asset "shapes/$shape-$color.svg" ($geometry[$shape] -f $colors[$color]) }
}
Add-Asset "goals/color.svg" '<circle cx="30" cy="30" r="18" fill="#ff5252"/><circle cx="70" cy="30" r="18" fill="#2196f3"/><circle cx="30" cy="70" r="18" fill="#f6d600"/><circle cx="70" cy="70" r="18" fill="#111111"/>'
Add-Asset "goals/shape.svg" '<rect x="10" y="10" width="30" height="30" fill="#666666"/><circle cx="70" cy="25" r="15" fill="#666666"/><polygon points="50,60 80,90 20,90" fill="#666666"/>'
Add-Asset "goals/number.svg" '<path d="M13 23H25V77H13M39 34C39 20 67 18 67 36C67 50 41 56 39 77H70M82 24H94V77H82" fill="none" stroke="#263238" stroke-linecap="round" stroke-linejoin="round" stroke-width="8"/>'
$fontPath = Join-Path $root "assets/fonts/Basic-Regular.ttf"
if (!(Test-Path -LiteralPath $fontPath)) { throw "Missing checked-in font $fontPath" }
if ($Check) {
  $actualAssets = @(
    Get-ChildItem -File -Recurse $shapeRoot,$goalRoot -Filter '*.svg' |
      ForEach-Object { $_.FullName.Substring($assetRoot.Length + 1).Replace('\','/') } |
      Sort-Object
  )
  $inventoryDrift = @(Compare-Object @($assets | Sort-Object) $actualAssets)
  if ($inventoryDrift.Count -ne 0) {
    throw "Canonical asset inventory drift:`n$($inventoryDrift | Out-String)"
  }
}
$canonicalTotal = 0
foreach ($relative in $assets) { $canonicalTotal += (Get-Item -LiteralPath (Join-Path $assetRoot $relative)).Length }
Write-Output "Promoted and audited $($assets.Count) vector-origin SVG assets; canonical bytes $canonicalTotal; optimizer config $configHash"
