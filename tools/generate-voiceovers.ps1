[CmdletBinding()]
param(
    [switch]$Force,
    [string]$EnvPath = "D:\code\ChessTD\.env"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$audioRoot = Join-Path $repoRoot "assets\audio"
$catalogPath = Join-Path $audioRoot "voiceover-catalog.json"
$receiptPath = Join-Path $audioRoot "voiceover-receipt.json"

function Read-DotEnvValue {
    param([string]$Path, [string]$Name)
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match ('^\s*' + [regex]::Escape($Name) + '\s*=\s*(.*)\s*$')) {
            $value = $Matches[1].Trim()
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            return $value
        }
    }
    return $null
}

function Find-Ffprobe {
    $command = Get-Command ffprobe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw "ffprobe is required to record voiceover metadata."
}

$apiKey = [Environment]::GetEnvironmentVariable("ELEVENLABS_API_KEY")
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    $apiKey = Read-DotEnvValue -Path $EnvPath -Name "ELEVENLABS_API_KEY"
}
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw "ELEVENLABS_API_KEY was not found in the process environment or configured .env file."
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$expectedTexts = @("Match by color", "Match by shape", "Match by number")
$prompts = @($catalog.prompts)
if ($prompts.Count -ne 3) { throw "Voiceover catalog must contain exactly three prompts." }
for ($i = 0; $i -lt $prompts.Count; $i++) {
    if ([string]$prompts[$i].text -cne $expectedTexts[$i]) {
        throw "Voiceover prompt $i must be exactly '$($expectedTexts[$i])'."
    }
}

New-Item -ItemType Directory -Force -Path $audioRoot | Out-Null
$headers = @{ "xi-api-key" = $apiKey }
$voice = $catalog.voice
foreach ($prompt in $prompts) {
    $outputPath = Join-Path $audioRoot ([string]$prompt.file)
    if ($Force -or !(Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        $body = @{
            text = [string]$prompt.text
            model_id = [string]$voice.model_id
            seed = [int]$prompt.seed
            voice_settings = @{
                stability = [double]$voice.settings.stability
                similarity_boost = [double]$voice.settings.similarity_boost
                style = [double]$voice.settings.style
                use_speaker_boost = [bool]$voice.settings.use_speaker_boost
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $uri = "https://api.elevenlabs.io/v1/text-to-speech/$($voice.id)?output_format=$($voice.output_format)"
        $temporaryPath = "$outputPath.partial"
        try {
            $utf8Body = [Text.Encoding]::UTF8.GetBytes($body)
            Invoke-WebRequest -Method Post -Uri $uri -Headers $headers -ContentType "application/json; charset=utf-8" -Body $utf8Body -OutFile $temporaryPath
            Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
        } finally {
            if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
        }
    }
    Write-Output "VOICEOVER_READY|file=$($prompt.file)"
}

$ffprobe = Find-Ffprobe
$streams = @($prompts | ForEach-Object {
    $path = Join-Path $audioRoot ([string]$_.file)
    $probe = & $ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,bit_rate,sample_rate,channels:format=duration -of json $path | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "ffprobe failed for $($_.file)." }
    $stream = @($probe.streams)[0]
    if ([string]$stream.codec_name -ne "mp3" -or [int]$stream.sample_rate -ne 44100 -or [int64]$stream.bit_rate -ne 128000) {
        throw "$($_.file) does not satisfy the MP3 44.1 kHz 128 kbps contract."
    }
    [ordered]@{
        file = [string]$_.file
        text = [string]$_.text
        codec = [string]$stream.codec_name
        sample_rate = [int]$stream.sample_rate
        bitrate = [int64]$stream.bit_rate
        channels = [int]$stream.channels
        duration_seconds = [math]::Round([double]$probe.format.duration, 3)
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})

$receipt = [ordered]@{
    generated_utc = [DateTime]::UtcNow.ToString("o")
    provider = [string]$catalog.provider
    voice_id = [string]$voice.id
    voice_name = [string]$voice.name
    voice_category = [string]$voice.category
    model_id = [string]$voice.model_id
    requested_output_format = [string]$voice.output_format
    catalog_sha256 = (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash.ToLowerInvariant()
    clips = $streams
} | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($receiptPath, $receipt + "`r`n", [Text.UTF8Encoding]::new($false))
Write-Output "VOICEOVER_RECEIPT_READY|clips=$($streams.Count)"
