#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DeclaredModes {
    param(
        [object]$Capabilities,
        [string]$PropertyName
    )

    if ($null -eq $Capabilities -or -not ($Capabilities.PSObject.Properties.Name -contains $PropertyName)) {
        return $null
    }
    $modes = @($Capabilities.$PropertyName)
    if ($modes.Count -eq 0 -or @($modes | Where-Object { $_ -notin @('Compact', 'Full') }).Count -gt 0) {
        return $null
    }
    return @($modes | Select-Object -Unique)
}

function Test-HelperParameters {
    param(
        [string]$HelperPath,
        [string[]]$RequiredParameters
    )

    if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf)) { return $false }
    try { $command = Get-Command -Name $HelperPath -ErrorAction Stop }
    catch { return $false }
    foreach ($parameterName in $RequiredParameters) {
        if (-not $command.Parameters.ContainsKey($parameterName)) { return $false }
    }
    return $true
}

$resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath -ErrorAction Stop).Path
$config = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json
if (-not ($config.PSObject.Properties.Name -contains 'install_directory') -or
    [string]::IsNullOrWhiteSpace([string]$config.install_directory)) {
    throw 'Launcher configuration does not contain a usable install_directory.'
}
$installDirectory = [System.IO.Path]::GetFullPath([string]$config.install_directory)
$capabilities = if ($config.PSObject.Properties.Name -contains 'capabilities') { $config.capabilities } else { $null }

$catalogModes = @(Get-DeclaredModes -Capabilities $capabilities -PropertyName 'catalog_detail_modes' | Where-Object { $null -ne $_ })
$catalogSource = 'declared'
if ($catalogModes.Count -eq 0) {
    $catalogSource = 'inspected'
    $searchHelper = Join-Path $installDirectory 'Search-EES-Library.ps1'
    $routineHelper = Join-Path $installDirectory 'Get-EES-Routine.ps1'
    if ((Test-HelperParameters -HelperPath $searchHelper -RequiredParameters @('Query', 'Limit', 'Detail')) -and
        (Test-HelperParameters -HelperPath $routineHelper -RequiredParameters @('RoutineID', 'Detail'))) {
        $catalogModes = @('Compact', 'Full')
    }
    else {
        $catalogSource = 'legacy'
        $catalogModes = @('Full')
    }
}

$resultModes = @(Get-DeclaredModes -Capabilities $capabilities -PropertyName 'result_detail_modes' | Where-Object { $null -ne $_ })
$resultSource = 'declared'
if ($resultModes.Count -eq 0) {
    $resultSource = 'inspected'
    $resultHelper = Join-Path $installDirectory 'Get-EES-Result.ps1'
    if (Test-HelperParameters -HelperPath $resultHelper -RequiredParameters @('Path', 'Variable', 'Pattern', 'Detail')) {
        $resultModes = @('Compact', 'Full')
    }
    else {
        $resultSource = 'legacy'
        $resultModes = @()
    }
}

$catalogCompact = $catalogModes -contains 'Compact'
$resultCompact = $resultModes -contains 'Compact'
[ordered]@{
    launcher_version = if ($config.PSObject.Properties.Name -contains 'version') { [string]$config.version } else { $null }
    launcher_api_level = if ($config.PSObject.Properties.Name -contains 'launcher_api_level') { $config.launcher_api_level } else { $null }
    catalog_detail_modes = @($catalogModes)
    result_detail_modes = @($resultModes)
    catalog_detection_source = $catalogSource
    result_detection_source = $resultSource
    use_compact_catalog = $catalogCompact
    use_compact_results = $resultCompact
    use_legacy_catalog_fallback = -not $catalogCompact
    use_raw_result_fallback = -not $resultCompact
    update_recommended = -not ($catalogCompact -and $resultCompact)
} | ConvertTo-Json -Depth 5 -Compress
