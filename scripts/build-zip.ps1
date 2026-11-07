[CmdletBinding()]
param(
    [string] $Version,
    [string] $OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\zip'),
    # Both makes the ZIP of the version with floating-point words and the -nofloat ZIP of
    # the one without; Float or NoFloat makes only one of them.
    [ValidateSet('Both', 'Float', 'NoFloat')]
    [string] $Variant = 'Both',
    [switch] $Sign
)

# Builds the Windows x86_64 ZIPs that .github/workflows/release.yml makes,
# sigma-VERSION-windows-x86_64.zip and sigma-VERSION-windows-x86_64-nofloat.zip, and
# signs the executables with -Sign.

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
$noFloatReleaseDirectory = Join-Path $repositoryRoot '.work\zip-release-nofloat'
$outputPath = [IO.Path]::GetFullPath($OutputDirectory, (Get-Location).Path)
$releaseScript = Join-Path $PSScriptRoot 'build-release.ps1'

# The same target as the CI build.
$releaseParameters = @{
    OutputDirectory        = $releaseDirectory
    NoFloatOutputDirectory = $noFloatReleaseDirectory
    Target                 = 'x86_64-windows-gnu'
    Variant                = $Variant
}
if ($Sign) {
    $releaseParameters.Sign = $true
}
& $releaseScript @releaseParameters | Out-Null

$packages = @()
if ($Variant -ne 'NoFloat') {
    $packages += @{ Name = "sigma-$Version-windows-x86_64"; Directory = $releaseDirectory }
}
if ($Variant -ne 'Float') {
    $packages += @{ Name = "sigma-$Version-windows-x86_64-nofloat"; Directory = $noFloatReleaseDirectory }
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$stagingRoot = Join-Path $repositoryRoot '.work\zip-staging'
foreach ($package in $packages) {
    $executablePath = Join-Path $package.Directory 'bin\sigma.exe'
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        throw "Windows release executable is missing: $executablePath"
    }

    # The ZIP holds one folder with the executable and the same documents as the CI ZIP.
    $packageName = $package.Name
    $packageDirectory = Join-Path $stagingRoot $packageName
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
    $files = @(
        $executablePath,
        (Join-Path $repositoryRoot 'LICENSE'),
        (Join-Path $repositoryRoot 'THIRD_PARTY_NOTICES.md'),
        (Join-Path $repositoryRoot 'README.md')
    )
    foreach ($file in $files) {
        Copy-Item -LiteralPath $file -Destination $packageDirectory
    }

    $zipPath = Join-Path $outputPath "$packageName.zip"
    Compress-Archive -LiteralPath $packageDirectory -DestinationPath $zipPath -Force
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force

    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    Write-Output $zipPath
    Write-Output "SHA256 $hash"
}
