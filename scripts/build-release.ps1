[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\release'),
    [string] $Target,
    [switch] $Sign
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$zig = Get-Command 'zig' -ErrorAction Stop
$outputPath = [IO.Path]::GetFullPath($OutputDirectory, (Get-Location).Path)
$buildArguments = @('build', '-Doptimize=ReleaseFast', '--prefix', $outputPath)

if ($Target) {
    $buildArguments += "-Dtarget=$Target"
}

Push-Location $repositoryRoot
try {
    & $zig.Source @buildArguments
    if ($LASTEXITCODE -ne 0) {
        throw "zig build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$isWindowsTarget = if ($Target) { $Target -match 'windows' } else { [OperatingSystem]::IsWindows() }
$executableName = if ($isWindowsTarget) { 'sigma.exe' } else { 'sigma' }
$executablePath = Join-Path $outputPath "bin\$executableName"
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Expected release executable was not produced: $executablePath"
}

if ($Sign) {
    if (-not $isWindowsTarget) {
        throw 'Code signing is supported only for a Windows executable.'
    }
    if ([string]::IsNullOrWhiteSpace($env:CODESIGN_CERT)) {
        throw 'Set CODESIGN_CERT to the signing certificate subject before using -Sign.'
    }

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

    & $signToolPath sign /n $env:CODESIGN_CERT /fd SHA256 $executablePath
    if ($LASTEXITCODE -ne 0) {
        throw "Signing the executable failed with exit code $LASTEXITCODE"
    }
    & $signToolPath verify /pa /all $executablePath
    if ($LASTEXITCODE -ne 0) {
        throw "Executable signature verification failed with exit code $LASTEXITCODE"
    }
}

Write-Output $executablePath
