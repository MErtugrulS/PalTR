[CmdletBinding()]
param(
    [string]$Repository = "MErtugrulS/PalTR",
    [string]$OutputDirectory = "artifacts/paltr-update"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$packageRoot = Join-Path $repoRoot "Client/PalTRUI/Package"
$infoPath = Join-Path $packageRoot "Info.json"
$pakPath = Join-Path $packageRoot "LogicMods/PalTRUI.pak"
$scriptsPath = Join-Path $packageRoot "Scripts"

if (!(Test-Path -LiteralPath $infoPath) -or
    !(Test-Path -LiteralPath $pakPath) -or
    !(Test-Path -LiteralPath $scriptsPath -PathType Container)) {
    throw "PalTRUI package eksik: $packageRoot"
}

$info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
$version = [string]$info.Version
if ([string]::IsNullOrWhiteSpace($version)) {
    throw "Info.json Version alani bos."
}

$resolvedOutput = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    [IO.Path]::GetFullPath($OutputDirectory)
} else {
    [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputDirectory))
}

New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
$stagingRoot = Join-Path $resolvedOutput "staging"
$payloadRoot = Join-Path $stagingRoot "Payload/PalTRUI"
if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
Copy-Item -LiteralPath $infoPath -Destination (Join-Path $payloadRoot "Info.json")
Copy-Item -LiteralPath $pakPath -Destination (Join-Path $payloadRoot "PalTRUI.pak")
New-Item -ItemType Directory -Path (Join-Path $payloadRoot "LogicMods") -Force | Out-Null
Move-Item -LiteralPath (Join-Path $payloadRoot "PalTRUI.pak") -Destination (Join-Path $payloadRoot "LogicMods/PalTRUI.pak")
Copy-Item -LiteralPath $scriptsPath -Destination (Join-Path $payloadRoot "Scripts") -Recurse

$archiveName = "PalTRUI-$version.zip"
$archivePath = Join-Path $resolvedOutput $archiveName
if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}
Compress-Archive -Path (Join-Path $stagingRoot "Payload") -DestinationPath $archivePath -CompressionLevel Optimal

$archive = Get-Item -LiteralPath $archivePath
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$tag = "paltr-ui-v$version"
$manifest = [ordered]@{
    schemaVersion = 1
    channel = "stable"
    version = $version
    packageUrl = "https://github.com/$Repository/releases/download/$tag/$archiveName"
    sha256 = $hash
    size = $archive.Length
    publishedAtUtc = [DateTime]::UtcNow.ToString("o")
}
$manifestPath = Join-Path $resolvedOutput "paltr-update.json"
$manifestJson = $manifest | ConvertTo-Json
[IO.File]::WriteAllText($manifestPath, $manifestJson, [Text.UTF8Encoding]::new($false))
Remove-Item -LiteralPath $stagingRoot -Recurse -Force

[pscustomobject]@{
    Tag = $tag
    Version = $version
    Archive = $archivePath
    Manifest = $manifestPath
    Sha256 = $hash
    Size = $archive.Length
}
