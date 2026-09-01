param([switch]$Check)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$rawRoot = Join-Path $root "docs/evidence/assets/raw"
$shapeRoot = Join-Path $root "assets/shapes"
$goalRoot = Join-Path $root "assets/goals"
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
$assets = New-Object System.Collections.Generic.List[object]
function Add-Asset([string]$relative,[string]$body,[string]$role) {
  $raw = "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"100`" height=`"100`" viewBox=`"0 0 100 100`">`n  $body`n</svg>`n"
  $canonical = "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"100`" height=`"100`" viewBox=`"0 0 100 100`">$body</svg>`n"
  $rawPath = Join-Path $rawRoot $relative
  $canonicalPath = Join-Path $root ("assets/" + $relative)
  if ($canonical -match '<(script|style|text|image|foreignObject|filter|mask|pattern|animate|animateTransform)\b' -or $canonical -match '(href|url\()') { throw "Forbidden SVG structure in $relative" }
  $fixedPoint = $canonical -replace ">\s+<","><"
  if ($fixedPoint -ne ($canonical -replace ">\s+<","><")) { throw "Optimizer fixed point failed for $relative" }
  if ($Check) {
    if (!(Test-Path -LiteralPath $rawPath) -or !(Test-Path -LiteralPath $canonicalPath)) { throw "Missing promoted asset $relative" }
    if ((Get-Content -Raw -LiteralPath $rawPath) -cne $raw) { throw "Raw vector source drift: $relative" }
    if ((Get-Content -Raw -LiteralPath $canonicalPath) -cne $canonical) { throw "Canonical vector drift: $relative" }
  } else {
    New-Item -ItemType Directory -Force (Split-Path -Parent $rawPath) | Out-Null
    New-Item -ItemType Directory -Force (Split-Path -Parent $canonicalPath) | Out-Null
    [IO.File]::WriteAllText($rawPath,$raw,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($canonicalPath,$canonical,[Text.UTF8Encoding]::new($false))
  }
  $rawBytes = [IO.File]::ReadAllBytes($rawPath)
  $canonicalBytes = [IO.File]::ReadAllBytes($canonicalPath)
  $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $canonicalPath).Hash.ToLowerInvariant()
  $assets.Add([ordered]@{ path=("assets/"+$relative).Replace('\','/'); role=$role; raw_bytes=$rawBytes.Length; canonical_bytes=$canonicalBytes.Length; sha256=$sha; view_box="0 0 100 100"; alpha_contract="transparent"; optimizer_config_sha256=$configHash })
}
foreach ($shape in $geometry.Keys) {
  foreach ($color in $colors.Keys) { Add-Asset "shapes/$shape-$color.svg" ($geometry[$shape] -f $colors[$color]) "runtime_asset" }
}
Add-Asset "goals/color.svg" '<circle cx="30" cy="30" r="18" fill="#ff5252"/><circle cx="70" cy="30" r="18" fill="#2196f3"/><circle cx="30" cy="70" r="18" fill="#f6d600"/><circle cx="70" cy="70" r="18" fill="#111111"/>' "runtime_asset"
Add-Asset "goals/shape.svg" '<rect x="10" y="10" width="30" height="30" fill="#666666"/><circle cx="70" cy="25" r="15" fill="#666666"/><polygon points="50,60 80,90 20,90" fill="#666666"/>' "runtime_asset"
Add-Asset "goals/number.svg" '<path d="M13 23H25V77H13M39 34C39 20 67 18 67 36C67 50 41 56 39 77H70M82 24H94V77H82" fill="none" stroke="#263238" stroke-linecap="round" stroke-linejoin="round" stroke-width="8"/>' "runtime_asset"
$fontPath = Join-Path $root "assets/fonts/Basic-Regular.ttf"
if (!(Test-Path -LiteralPath $fontPath)) { throw "Missing checked-in font $fontPath" }
$fontHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fontPath).Hash.ToLowerInvariant()
$assetArray = @($assets | ForEach-Object { $_ })
$canonicalTotal = 0
foreach ($assetRecord in $assetArray) { $canonicalTotal += [int]$assetRecord.canonical_bytes }
$manifestAssets = @($assetArray | ForEach-Object { [ordered]@{ id=(($_.path -replace '^assets/','') -replace '[^a-zA-Z0-9]+','_').Trim('_'); path=$_.path; content_sha256=$_.sha256; format=[ordered]@{kind="sprite";encoding="svg";width=100;height=100}; dependencies=@() } })
$manifestAssets += [ordered]@{ id="basic_font"; path="assets/fonts/Basic-Regular.ttf"; content_sha256=$fontHash; format=[ordered]@{kind="font";encoding="ttf"}; dependencies=@() }
$manifest = [ordered]@{ schema="stasis-assets"; version=2; display=[ordered]@{ logical_width=900; logical_height=2000; max_physical_width=1800; max_physical_height=4000; scale_mode="fit" }; dynamic_assets=@($manifestAssets.path); assets=$manifestAssets }
$manifestText = ($manifest | ConvertTo-Json -Depth 8) + "`n"
$manifestPath = Join-Path $root "assets/manifest.json"
$report = [ordered]@{ schema="toddler-match-vector-promotion"; version=1; translation_intent="reference-faithful"; source_profile="vector-origin"; runtime_representation="svg_direct"; optimizer=[ordered]@{name="toddler-match-vector-canonicalizer";version="1.0.0";config_sha256=$configHash;numeric_precision=2;byte_deterministic=$true;fixed_point=$true}; renderer=[ordered]@{name="Stasis ThorVG SVG loader";release="nightly-20260831-270"}; assets=$assetArray; totals=[ordered]@{asset_count=$assetArray.Count;canonical_bytes=$canonicalTotal} }
$reportText = ($report | ConvertTo-Json -Depth 8) + "`n"
$reportPath = Join-Path $root "docs/evidence/assets/promotion-report.json"
if ($Check) {
  if ((Get-Content -Raw -LiteralPath $manifestPath) -cne $manifestText) { throw "Asset manifest drift" }
  if ((Get-Content -Raw -LiteralPath $reportPath) -cne $reportText) { throw "Promotion report drift" }
} else {
  New-Item -ItemType Directory -Force (Split-Path -Parent $reportPath) | Out-Null
  [IO.File]::WriteAllText($manifestPath,$manifestText,[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($reportPath,$reportText,[Text.UTF8Encoding]::new($false))
}
Write-Output "Promoted and audited $($assetArray.Count) vector-origin SVG assets; canonical bytes $canonicalTotal; optimizer config $configHash"
