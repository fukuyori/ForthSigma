[CmdletBinding()]
param(
    [string] $Version,
    [string] $OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\zip'),
    [switch] $Sign
)

# Builds the Windows x86_64 ZIP that .github/workflows/release.yml makes,
# sigma-VERSION-windows-x86_64.zip, and signs the executable with -Sign.

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$versionFile = Join-Path $repositoryRoot 'VERSION'
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = (Get-Content -LiteralPath $versionFile -Raw).Trim()
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid version '$Version'. Expected MAJOR.MINOR.PATCH."
}

if ($Sign -and [string]::IsNullOrWhiteSpace($env:CODESIGN_CERT)) {
    throw 'Set CODESIGN_CERT to the signing certificate subject before using -Sign.'
}

$releaseDirectory = Join-Path $repositoryRoot '.work\zip-release'
$outputPath = [IO.Path]::GetFullPath($OutputDirectory, (Get-Location).Path)
$releaseScript = Join-Path $PSScriptRoot 'build-release.ps1'

# The same target as the CI build.
$releaseParameters = @{
    OutputDirectory = $releaseDirectory
    Target          = 'x86_64-windows-gnu'
}
if ($Sign) {
    $releaseParameters.Sign = $true
}
& $releaseScript @releaseParameters | Out-Null
$executablePath = Join-Path $releaseDirectory 'bin\sigma.exe'
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Windows release executable is missing: $executablePath"
}

# The ZIP holds one folder with the executable and the same documents as the CI ZIP.
$packageName = "sigma-$Version-windows-x86_64"
$stagingRoot = Join-Path $repositoryRoot '.work\zip-staging'
$packageDirectory = Join-Path $stagingRoot $packageName
if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
$files = @(
    $executablePath,
    (Join-Path $repositoryRoot 'LICENSE'),
    (Join-Path $repositoryRoot 'THIRD_PARTY_NOTICES.md'),
    (Join-Path $repositoryRoot 'README.md'),
    (Join-Path $repositoryRoot 'forth\sigma\USER_MANUAL.md')
)
foreach ($file in $files) {
    Copy-Item -LiteralPath $file -Destination $packageDirectory
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$zipPath = Join-Path $outputPath "$packageName.zip"
Compress-Archive -LiteralPath $packageDirectory -DestinationPath $zipPath -Force
Remove-Item -LiteralPath $stagingRoot -Recurse -Force

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
Write-Output $zipPath
Write-Output "SHA256 $hash"
