[CmdletBinding(SupportsShouldProcess = $true)]
param()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$fixed = Get-Content -LiteralPath (Join-Path $root '.work/windows-etw-control-20261116/fixed.json') -Raw | ConvertFrom-Json
$python = $fixed.environment.executable
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Frozen Python executable missing' }
Write-Output '128 baseline diagnostic runs; CPU0/2; minimal/full; ETW off/on. No calibration or adoption.'
Write-Output 'Creates two owned WPR sessions. Never stops other sessions. Retains failed captures without retry.'
if ($PSCmdlet.ShouldProcess($root, 'Capture fixed API/ETW control diagnostic')) {
    & $python -E -X utf8 (Join-Path $PSScriptRoot 'capture.py') --capture
    if ($LASTEXITCODE -ne 0) { throw 'Capture failed; inspect newest capture.json and owned-session cleanup state' }
}
