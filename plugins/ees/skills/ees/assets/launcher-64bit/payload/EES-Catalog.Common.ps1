#Requires -Version 5.1
Set-StrictMode -Version Latest

function Resolve-SelectedEes {
    param([string]$RequestedPath)

    $requiredArchitecture = 'Any'
    $configPath = Join-Path $PSScriptRoot 'config.json'
    $configured = $null
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $configured = [string]$config.ees_path
        if ($config.PSObject.Properties.Name -contains 'required_architecture') {
            $requiredArchitecture = [string]$config.required_architecture
        }
    }

    if ($RequestedPath) { $candidates = @($RequestedPath) }
    elseif ($requiredArchitecture -eq '32-bit') { $candidates = @($configured, 'C:\EES32\ees.exe') }
    elseif ($requiredArchitecture -eq '64-bit') { $candidates = @($configured, 'C:\EES64\ees64.exe') }
    else {
        if ($configured) { $candidates = @($configured, 'C:\EES64\ees64.exe', 'C:\EES32\ees.exe') }
        else { $candidates = @('C:\EES64\ees64.exe', 'C:\EES32\ees.exe') }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
            $leaf = [System.IO.Path]::GetFileName($resolved)
            if ($leaf -notin @('ees64.exe', 'ees.exe')) { continue }
            $actualArchitecture = if ($leaf -eq 'ees.exe') { '32-bit' } else { '64-bit' }
            if ($requiredArchitecture -in @('32-bit', '64-bit') -and $actualArchitecture -ne $requiredArchitecture) {
                if ($RequestedPath) {
                    throw "This installed catalog requires $requiredArchitecture EES and cannot inspect $actualArchitecture EES: $resolved"
                }
                continue
            }
            return $resolved
        }
    }
    if ($requiredArchitecture -eq '32-bit') { throw 'No supported 32-bit EES executable was found.' }
    if ($requiredArchitecture -eq '64-bit') { throw 'No supported 64-bit EES executable was found.' }
    throw 'No supported EES executable was found.'
}

function ConvertTo-CanonicalRoutineId {
    param([string]$RoutineID)
    if ($RoutineID -eq 'Call Impinging_Jet_SRN_ND') { return 'Impinging_Jet_SRN_ND' }
    return $RoutineID
}

function Get-EesRequiredLoadDirective {
    param([object]$Routine)
    $help = [string]$Routine.Help
    if ($help -match '(?i)^\\Component Library\\') { return '$Load Component Library' }
    if ($help -match '(?i)^\\Mechanical Design\\') { return '$Load Mechanical' }
    if ($help -match '(?i)^\\NASA\\') { return '$Load NASA' }
    if ($help -match '(?i)^\\Incompressible\\') { return '$Load Incompressible' }
    return $null
}

function Get-EesCatalogContext {
    param([string]$RequestedEesPath)

    $resolvedEes = Resolve-SelectedEes -RequestedPath $RequestedEesPath
    $eesRoot = Split-Path -Parent $resolvedEes
    $installedMetadataPath = Join-Path $eesRoot 'EES_Tool_Metadata.json'
    if (-not (Test-Path -LiteralPath $installedMetadataPath -PathType Leaf)) {
        throw "EES library metadata was not found: $installedMetadataPath"
    }
    $installed = Get-Content -LiteralPath $installedMetadataPath -Raw | ConvertFrom-Json
    $packagedCatalogPath = Join-Path $PSScriptRoot 'catalog\engineering-tool-dialog-catalog.json'
    $hasPackagedCatalog = Test-Path -LiteralPath $packagedCatalogPath -PathType Leaf
    $catalog = if ($hasPackagedCatalog) {
        Get-Content -LiteralPath $packagedCatalogPath -Raw | ConvertFrom-Json
    }
    else { $installed }

    $installedRoutineIds = @{}
    foreach ($routine in $installed.Routines) {
        $installedRoutineIds[(ConvertTo-CanonicalRoutineId -RoutineID ([string]$routine.RoutineID))] = $true
    }
    $packagedRoutineIds = @{}
    foreach ($routine in $catalog.Routines) { $packagedRoutineIds[[string]$routine.RoutineID] = $true }

    if ($hasPackagedCatalog) {
        $missingInstalledRoutines = @($installed.Routines | Where-Object {
            $canonical = ConvertTo-CanonicalRoutineId -RoutineID ([string]$_.RoutineID)
            -not $packagedRoutineIds.ContainsKey($canonical)
        })
        if ($missingInstalledRoutines.Count -gt 0) {
            $missingIds = @{}
            foreach ($routine in $missingInstalledRoutines) { $missingIds[[string]$routine.RoutineID] = $true }
            $catalog.Routines = @($catalog.Routines) + $missingInstalledRoutines
            $catalog.RoutineCategories = @($catalog.RoutineCategories) + @($installed.RoutineCategories | Where-Object { $missingIds.ContainsKey([string]$_.RoutineID) })
            $catalog.Keywords = @($catalog.Keywords) + @($installed.Keywords | Where-Object { $missingIds.ContainsKey([string]$_.RoutineID) })
            $catalog.Signatures = @($catalog.Signatures) + @($installed.Signatures | Where-Object { $missingIds.ContainsKey([string]$_.RoutineID) })
            $catalog.Parameters = @($catalog.Parameters) + @($installed.Parameters | Where-Object { $missingIds.ContainsKey([string]$_.RoutineID) })
        }
    }

    $userlibName = if ([System.IO.Path]::GetFileName($resolvedEes) -eq 'ees64.exe') { 'Userlib64' } else { 'Userlib' }
    [pscustomobject]@{
        EesPath = $resolvedEes
        InstalledMetadataPath = $installedMetadataPath
        UserlibPath = Join-Path $eesRoot $userlibName
        Catalog = $catalog
        PackagedCatalogPath = if ($hasPackagedCatalog) { $packagedCatalogPath } else { $null }
        HasPackagedCatalog = $hasPackagedCatalog
        InstalledRoutineIds = $installedRoutineIds
        PackagedRoutineIds = $packagedRoutineIds
        InstalledRoutineCount = @($installed.Routines).Count
        CatalogRoutineCount = @($catalog.Routines).Count
    }
}
