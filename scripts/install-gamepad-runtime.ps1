[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('x64', 'x86', 'arm64')][string]$Architecture = 'x64',
    [string]$DestinationDirectory = (Join-Path $PSScriptRoot '..\zig-out\bin'),
    [string]$ArchivePath
)
$ErrorActionPreference = 'Stop'
# Optional SDL runtime only; this does not build or package FORTH/Sigma.
# Official release asset SHA256 values from libsdl-org/SDL release-3.4.20.
$version = '3.4.20'
$hashes = @{
    x64 = '368bed8b24e44ad9ea372990814f2343fcfb9e468abb7f8f4a3bc146c7304752'
    x86 = 'f6fbf5afa42195a01b1da8adf25567377d0e212f4b2b6770923903eb3feea254'
    arm64 = '51c292eafc114ea3c63519fa2f5413a486979769d5444a636296f8a61c737267'
}
$destination = [IO.Path]::GetFullPath($DestinationDirectory)
if (-not $PSCmdlet.ShouldProcess($destination, "Install SDL $version ($Architecture) runtime and license")) { return }
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$stage = Join-Path $tempRoot ('sigma-gamepad-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    $archive = Join-Path $stage 'runtime.zip'
    if ($ArchivePath) {
        Copy-Item -LiteralPath $ArchivePath -Destination $archive
    } else {
        $name = "SDL3-$version-win32-$Architecture.zip"
        Invoke-WebRequest -Uri "https://github.com/libsdl-org/SDL/releases/download/release-$version/$name" -OutFile $archive
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $hashes[$Architecture]) {
        throw 'SDL runtime archive checksum does not match the official release asset.'
    }
    $expanded = Join-Path $stage 'expanded'
    Expand-Archive -LiteralPath $archive -DestinationPath $expanded
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $expanded 'SDL3.dll') -Destination (Join-Path $destination 'SDL3.dll') -Force
    Copy-Item -LiteralPath (Join-Path $expanded 'LICENSE.txt') -Destination (Join-Path $destination 'SDL3-LICENSE.txt') -Force
    Write-Output "Installed SDL $version ($Architecture) in $destination"
} finally {
    # Only remove this invocation's generated temporary directory.
    $resolved = [IO.Path]::GetFullPath($stage)
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notlike 'sigma-gamepad-*') { throw 'Invalid temporary directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
