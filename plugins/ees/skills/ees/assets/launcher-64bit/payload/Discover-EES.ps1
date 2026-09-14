#Requires -Version 5.1
[CmdletBinding()]
param([string]$EesPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$requiredArchitecture = 'Any'
$configPath = Join-Path $PSScriptRoot 'config.json'
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ($config.PSObject.Properties.Name -contains 'required_architecture') {
        $requiredArchitecture = [string]$config.required_architecture
    }
}
$candidates = if ($EesPath) { @($EesPath) }
elseif ($requiredArchitecture -eq '32-bit') { @('C:\EES32\ees.exe') }
elseif ($requiredArchitecture -eq '64-bit') { @('C:\EES64\ees64.exe') }
else { @('C:\EES64\ees64.exe', 'C:\EES32\ees.exe') }
$installations = @()
foreach ($candidate in $candidates) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    $resolved = (Resolve-Path -LiteralPath $candidate).Path
    $leaf = [System.IO.Path]::GetFileName($resolved)
    if ($leaf -notin @('ees64.exe', 'ees.exe')) { continue }
    $architecture = if ($leaf -eq 'ees64.exe') { '64-bit' } else { '32-bit' }
    if ($requiredArchitecture -in @('32-bit', '64-bit') -and $architecture -ne $requiredArchitecture) {
        if ($EesPath) {
            throw "This installed discovery tool requires $requiredArchitecture EES and cannot inspect $architecture EES: $resolved"
        }
        continue
    }
    $root = Split-Path -Parent $resolved
    $userlib = Join-Path $root $(if ($architecture -eq '64-bit') { 'Userlib64' } else { 'Userlib' })
    $metadata = Join-Path $root 'EES_Tool_Metadata.json'
    $installations += [pscustomobject]@{
        ees_path = $resolved
        architecture = $architecture
        version = (Get-Item -LiteralPath $resolved).VersionInfo.FileVersion
        userlib_path = $userlib
        userlib_available = Test-Path -LiteralPath $userlib -PathType Container
        metadata_path = $metadata
        metadata_available = Test-Path -LiteralPath $metadata -PathType Leaf
    }
}

if ($installations.Count -eq 0) {
    if ($requiredArchitecture -eq '32-bit') { throw 'No supported 32-bit EES installation was found. Checked C:\EES32\ees.exe.' }
    if ($requiredArchitecture -eq '64-bit') { throw 'No supported 64-bit EES installation was found. Checked C:\EES64\ees64.exe.' }
    throw 'No supported EES installation was found. Checked C:\EES64\ees64.exe and C:\EES32\ees.exe.'
}
@($installations) | ConvertTo-Json -Depth 4
