[CmdletBinding()]
param(
    [string]$Repository = "benwmaddox/StasisLang",
    [string[]]$RequiredAssets = @(
        "stasis-nightly-win-x64.zip",
        "stasis-nightly-linux-x64.tar.gz",
        "stasis-nightly-osx-arm64.tar.gz"
    )
)

$ErrorActionPreference = "Stop"
$headers = @{
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "Stasis-weekly-release-builder"
}
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)"
}

$releaseResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases?per_page=100" -Headers $headers
$releases = if ($releaseResponse -is [Array]) {
    @($releaseResponse.GetEnumerator())
} else {
    @($releaseResponse)
}
$nightlies = @($releases | Where-Object {
    if ($_.draft -or [string]($_.tag_name) -notmatch '^nightly-[0-9]{8}-[0-9]+$') {
        $false
    } else {
        $assetNames = @($_.assets | ForEach-Object { [string]($_.name) })
        @($RequiredAssets | Where-Object { $assetNames -notcontains $_ }).Count -eq 0
    }
} | Sort-Object -Property @{ Expression = { [DateTimeOffset]($_.published_at) }; Descending = $true })

if ($nightlies.Count -eq 0) {
    throw "No complete non-draft Stasis nightly release was found in $Repository"
}

Write-Output ([string]($nightlies[0].tag_name))
