[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\release'),
    # The Forth 2012 profile keeps standard word sets and excludes graphics, audio,
    # and Sigma's extension vocabulary.
    [string] $Forth2012OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\release-forth2012'),
    [string] $Target,
    # Both builds the full profile and Forth 2012 profile.
    [ValidateSet('Both', 'Full', 'Forth2012')]
    [string] $Variant = 'Both',
    [switch] $Sign
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$zig = Get-Command 'zig' -ErrorAction Stop
$isWindowsTarget = if ($Target) { $Target -match 'windows' } else { [OperatingSystem]::IsWindows() }
$executableName = if ($isWindowsTarget) { 'sigma.exe' } else { 'sigma' }

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

    # RFC 3161 timestamp, so that the signature stays valid after the certificate expires.
    # The certificate chains to DigiCert Trusted Root G4; CODESIGN_TIMESTAMP_URL overrides the server.
    $timestampUrl = if ([string]::IsNullOrWhiteSpace($env:CODESIGN_TIMESTAMP_URL)) { 'http://timestamp.digicert.com' } else { $env:CODESIGN_TIMESTAMP_URL }
}

# Builds one version into $Directory, signs it with -Sign, and returns the executable's path.
function Build-Sigma([string] $Directory, [string] $Profile) {
    $outputPath = [IO.Path]::GetFullPath($Directory, (Get-Location).Path)
    $buildArguments = @('build', '-Doptimize=fast', '--prefix', $outputPath)
    if ($Target) {
        $buildArguments += "-Dtarget=$Target"
    }
    else {
        # Without a target, Zig builds for the CPU of this machine, and the program can then
        # fail on a CPU without the same instructions (AVX-512, for example).
        $buildArguments += '-Dcpu=baseline'
    }
    if ($Profile -eq 'Forth2012') {
        $buildArguments += @('-Dgraphics=false', '-Daudio=false', '-Dextension=false')
    }

    Push-Location $repositoryRoot
    try {
        # zig's own output goes to the host, so that only the paths are returned.
        & $zig.Source @buildArguments | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "zig build failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    $executablePath = Join-Path $outputPath "bin\$executableName"
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        throw "Expected release executable was not produced: $executablePath"
    }

    if ($Sign) {
        & $signToolPath sign /n $env:CODESIGN_CERT /fd SHA256 /tr $timestampUrl /td SHA256 $executablePath | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Signing the executable failed with exit code $LASTEXITCODE"
        }
        & $signToolPath verify /pa /all $executablePath | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Executable signature verification failed with exit code $LASTEXITCODE"
        }
        if (-not (Get-AuthenticodeSignature -LiteralPath $executablePath).TimeStamperCertificate) {
            throw "The executable signature has no timestamp: $executablePath"
        }
    }
    return $executablePath
}

if ($Variant -ne 'Forth2012') {
    Write-Output (Build-Sigma $OutputDirectory 'Full')
}
if ($Variant -ne 'Full') {
    Write-Output (Build-Sigma $Forth2012OutputDirectory 'Forth2012')
}
