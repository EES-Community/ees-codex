#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,

    [string]$ManifestPath,

    [string]$CachePath,

    [switch]$ForceRefresh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$versionPath = Join-Path $skillRoot 'VERSION.txt'
if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
    throw "The EES skill version file is missing: $versionPath"
}
$skillVersion = (Get-Content -LiteralPath $versionPath -Raw).Trim()
$statusHelper = Join-Path $PSScriptRoot 'Get-EES-UpdateStatus.ps1'
if (-not (Test-Path -LiteralPath $statusHelper -PathType Leaf)) {
    throw "The EES update-status helper is missing: $statusHelper"
}

$arguments = @{
    InstalledSkillVersion = $skillVersion
    ForceRefresh = $ForceRefresh
}
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { $arguments.ConfigPath = $ConfigPath }
if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) { $arguments.ManifestPath = $ManifestPath }
if (-not [string]::IsNullOrWhiteSpace($CachePath)) { $arguments.CachePath = $CachePath }

& $statusHelper @arguments
