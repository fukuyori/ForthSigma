[CmdletBinding()]
param(
    [string] $Version,
    [string] $OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\installer'),
    [switch] $Sign
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$versionFile = Join-Path $repositoryRoot 'VERSION'
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = (Get-Content -LiteralPath $versionFile -Raw).Trim()
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid version '$Version'. Expected MAJOR.MINOR.PATCH."
}

$releaseDirectory = Join-Path $repositoryRoot '.work\installer-release'
$outputPath = [IO.Path]::GetFullPath($OutputDirectory, (Get-Location).Path)
$releaseScript = Join-Path $PSScriptRoot 'build-release.ps1'
$installerDefinition = Join-Path $repositoryRoot 'installer\sigma.iss'

if ($Sign -and [string]::IsNullOrWhiteSpace($env:CODESIGN_CERT)) {
    throw 'Set CODESIGN_CERT to the signing certificate subject before using -Sign.'
}

$releaseParameters = @{
    OutputDirectory = $releaseDirectory
}
if ($Sign) {
    $releaseParameters.Sign = $true
}
& $releaseScript @releaseParameters | Out-Null
$executablePath = Join-Path $releaseDirectory 'bin\sigma.exe'
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Windows release executable is missing: $executablePath"
}

$compiler = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
if ($compiler) {
    $compilerPath = $compiler.Source
}
else {
    $compilerPath = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $compilerPath) {
    throw 'ISCC.exe was not found. Install Inno Setup 6 or add ISCC.exe to PATH.'
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$compilerArguments = @(
    "/DAppVersion=$Version",
    "/DPayloadExe=$executablePath",
    "/O$outputPath",
    $installerDefinition
)

if ($Sign) {
    $signTool = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue
    if (-not $signTool) {
        $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
        $signToolPath = Get-ChildItem -LiteralPath $kitsRoot -Filter 'signtool.exe' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -match '\\x64$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $signToolPath) {
            throw 'signtool.exe was not found in PATH or the Windows 10 SDK.'
        }
    }
    else {
        $signToolPath = $signTool.Source
    }

    $signCommand = '"{0}" sign /n $q{1}$q /fd SHA256 $f' -f $signToolPath, $env:CODESIGN_CERT
    $compilerArguments += "/Ssigma=$signCommand"
    $compilerArguments += '/DEnableSigning'
}

Push-Location $repositoryRoot
try {
    & $compilerPath @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$installerPath = Join-Path $outputPath "FORTH-Sigma-Setup-$Version.exe"
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Installer output was not produced: $installerPath"
}

if ($Sign) {
    & $signToolPath verify /pa /all $installerPath
    if ($LASTEXITCODE -ne 0) {
        throw "Installer signature verification failed with exit code $LASTEXITCODE"
    }
}

Write-Output $installerPath
