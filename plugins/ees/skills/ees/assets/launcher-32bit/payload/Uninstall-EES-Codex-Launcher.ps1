#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallDirectory = (Join-Path $env:LOCALAPPDATA 'EES-Codex-Launcher'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $resolved = [System.IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\')
    $configPath = Join-Path $resolved 'config.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Refusing to remove an unrecognized directory. Launcher config not found: $configPath"
    }
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ($config.product -ne 'EES-Codex-Launcher' -or $config.install_directory -ne $resolved) {
        throw 'Refusing to remove a directory whose launcher identity does not match.'
    }
    $workspace = $config.workspace_root
    Remove-Item -LiteralPath $resolved -Recurse -Force
    Write-Host 'EES Codex Launcher removed.' -ForegroundColor Green
    Write-Host "Your models and results were preserved at: $workspace"
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
