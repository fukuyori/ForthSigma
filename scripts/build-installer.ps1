[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\installer'),
    # Both makes the installer of the full version and that of the FORTH 2012 profile.
    [ValidateSet('Both', 'Full', 'Forth2012')]
    [string] $Variant = 'Both',
    [switch] $Sign
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
# The version is always VERSION's, which the executable is built with too, so that the
# names of the packages and the executable inside them agree.
$versionFile = Join-Path $repositoryRoot 'VERSION'
$Version = (Get-Content -LiteralPath $versionFile -Raw).Trim()
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid version '$Version' in $versionFile. Expected MAJOR.MINOR.PATCH."
}

$releaseDirectory = Join-Path $repositoryRoot '.work\installer-release'
$forth2012ReleaseDirectory = Join-Path $repositoryRoot '.work\installer-release-forth2012'
$outputPath = [IO.Path]::GetFullPath($OutputDirectory, (Get-Location).Path)
$releaseScript = Join-Path $PSScriptRoot 'build-release.ps1'
$installerDefinition = Join-Path $repositoryRoot 'installer\sigma.iss'

if ($Sign -and [string]::IsNullOrWhiteSpace($env:CODESIGN_CERT)) {
    throw 'Set CODESIGN_CERT to the signing certificate subject before using -Sign.'
}

# Each profile is its own product (installer\sigma.iss), so both can be installed.
$releaseParameters = @{
    OutputDirectory          = $releaseDirectory
    Forth2012OutputDirectory = $forth2012ReleaseDirectory
    Variant                  = $Variant
}
if ($Sign) {
    $releaseParameters.Sign = $true
}
& $releaseScript @releaseParameters | Out-Null
$installers = @()
if ($Variant -ne 'Forth2012') {
    $installers += @{ Executable = (Join-Path $releaseDirectory 'bin\sigma.exe'); Suffix = ''; Defines = @() }
}
if ($Variant -ne 'Full') {
    $installers += @{ Executable = (Join-Path $forth2012ReleaseDirectory 'bin\sigma.exe'); Suffix = '-forth2012'; Defines = @('/DForth2012') }
}
foreach ($installer in $installers) {
    if (-not (Test-Path -LiteralPath $installer.Executable -PathType Leaf)) {
        throw "Windows release executable is missing: $($installer.Executable)"
    }
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
$signingArguments = @()
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

    # RFC 3161 timestamp, so that the signature stays valid after the certificate expires.
    # The certificate chains to DigiCert Trusted Root G4; CODESIGN_TIMESTAMP_URL overrides the server.
    $timestampUrl = if ([string]::IsNullOrWhiteSpace($env:CODESIGN_TIMESTAMP_URL)) { 'http://timestamp.digicert.com' } else { $env:CODESIGN_TIMESTAMP_URL }
    # $q, not a literal quote: PowerShell passes an embedded quote as \", which ISCC splits at the space in the path.
    $signCommand = '$q{0}$q sign /n $q{1}$q /fd SHA256 /tr {2} /td SHA256 $f' -f $signToolPath, $env:CODESIGN_CERT, $timestampUrl
    $signingArguments += "/Ssigma=$signCommand"
    $signingArguments += '/DEnableSigning'
}

foreach ($installer in $installers) {
    $compilerArguments = @(
        "/DAppVersion=$Version",
        "/DPayloadExe=$($installer.Executable)",
        "/O$outputPath"
    ) + $installer.Defines + $signingArguments + @($installerDefinition)

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

    $installerPath = Join-Path $outputPath "sigma-$Version-windows-x86_64$($installer.Suffix)-setup.exe"
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw "Installer output was not produced: $installerPath"
    }

    if ($Sign) {
        & $signToolPath verify /pa /all $installerPath
        if ($LASTEXITCODE -ne 0) {
            throw "Installer signature verification failed with exit code $LASTEXITCODE"
        }
        if (-not (Get-AuthenticodeSignature -LiteralPath $installerPath).TimeStamperCertificate) {
            throw "The installer signature has no timestamp: $installerPath"
        }
    }

    Write-Output $installerPath
}
