#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-FileSha256Hex {
    param([string]$FilePath)

    $stream = [System.IO.File]::OpenRead($FilePath)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try { $hashBytes = $sha256.ComputeHash($stream) }
        finally { $sha256.Dispose() }
    }
    finally { $stream.Dispose() }
    return ([System.BitConverter]::ToString($hashBytes) -replace '-', '')
}

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

function Get-InstalledMetadataMatch {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,
        [Parameter(Mandatory = $true)]
        [string]$RoutineID
    )

    if (-not $Context.InstalledMetadataReadable) { return $null }
    $canonicalId = ConvertTo-CanonicalRoutineId -RoutineID $RoutineID
    return $Context.InstalledRoutineIds.ContainsKey($canonicalId)
}

function Get-EesSearchableRoutines {
    param([Parameter(Mandatory = $true)][object]$Catalog)

    $knownRoutineIds = @{}
    $routines = @($Catalog.Routines)
    foreach ($routine in $routines) {
        $knownRoutineIds[(ConvertTo-CanonicalRoutineId -RoutineID ([string]$routine.RoutineID))] = $true
    }

    $signatureGroups = @($Catalog.Signatures | Group-Object {
        ConvertTo-CanonicalRoutineId -RoutineID ([string]$_.RoutineID)
    })
    foreach ($group in $signatureGroups) {
        $routineId = [string]$group.Name
        if ($knownRoutineIds.ContainsKey($routineId)) { continue }

        # Preserve discoverability when the canonical metadata contains linked
        # signature/category/parameter rows but no Routines row. No external
        # source is consulted and the packaged JSON is not modified.
        $primary = @($group.Group | Where-Object { $_.IsPrimary } | Select-Object -First 1)
        if ($primary.Count -eq 0) { $primary = @($group.Group | Select-Object -First 1) }
        $primarySignature = $primary[0]
        $syntax = [string]$primarySignature.Syntax
        $description = [string]$primarySignature.Description
        if ([string]::IsNullOrWhiteSpace($description)) {
            $description = 'Calling metadata is present, but the canonical metadata has no Routines row for this entry.'
        }
        $kind = if ($syntax.TrimStart() -match '(?i)^Call\s+') { 'procedure' } else { 'function' }
        $routines += [pscustomobject]@{
            RoutineID = $routineId
            Name = $routineId
            Kind = $kind
            DisplayName = $routineId
            ShortDescription = $description
            LongDescription = $description
            Help = $null
            Picture = $null
            isProfessionalOnly = $null
            isDeprecated = $null
            ReplacementRoutineID = $null
            VersionIntroduced = $null
            CatalogRecordType = 'signature_only'
        }
        $knownRoutineIds[$routineId] = $true
    }
    return $routines
}

function Get-EesCatalogContext {
    param([string]$RequestedEesPath)

    $resolvedEes = Resolve-SelectedEes -RequestedPath $RequestedEesPath
    $eesRoot = Split-Path -Parent $resolvedEes

    # This packaged file is the sole source of searchable routine data. The copy
    # beside EES is inspected only to report installed_metadata_match; its rows
    # are never merged into, substituted for, or allowed to override the catalog.
    $catalogPath = Join-Path $PSScriptRoot 'catalog\EES_Tool_Metadata.json'
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        throw "The packaged EES tool metadata was not found: $catalogPath"
    }
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    foreach ($requiredCollection in @('Routines', 'Categories', 'RoutineCategories', 'Signatures', 'Parameters', 'Keywords')) {
        if ($catalog.PSObject.Properties.Name -notcontains $requiredCollection) {
            throw "The packaged EES tool metadata is missing the required $requiredCollection collection: $catalogPath"
        }
    }

    $catalogFile = Get-Item -LiteralPath $catalogPath
    $catalogHash = Get-FileSha256Hex -FilePath $catalogPath
    $searchableRoutines = @(Get-EesSearchableRoutines -Catalog $catalog)

    $installedMetadataPath = Join-Path $eesRoot 'EES_Tool_Metadata.json'
    $installedMetadataPresent = Test-Path -LiteralPath $installedMetadataPath -PathType Leaf
    $installedMetadataReadable = $false
    $installedMetadataError = $null
    $installedRoutineIds = @{}
    if ($installedMetadataPresent) {
        try {
            $installed = Get-Content -LiteralPath $installedMetadataPath -Raw | ConvertFrom-Json
            if ($installed.PSObject.Properties.Name -notcontains 'Routines') {
                throw 'The Routines collection is missing.'
            }
            foreach ($routine in $installed.Routines) {
                $canonicalId = ConvertTo-CanonicalRoutineId -RoutineID ([string]$routine.RoutineID)
                $installedRoutineIds[$canonicalId] = $true
            }
            $installedMetadataReadable = $true
        }
        catch {
            $installedMetadataError = $_.Exception.Message
        }
    }

    $userlibName = if ([System.IO.Path]::GetFileName($resolvedEes) -eq 'ees64.exe') { 'Userlib64' } else { 'Userlib' }
    [pscustomobject]@{
        EesPath = $resolvedEes
        UserlibPath = Join-Path $eesRoot $userlibName
        Catalog = $catalog
        CatalogPath = $catalogPath
        CatalogSha256 = $catalogHash
        CatalogLastWriteUtc = $catalogFile.LastWriteTimeUtc.ToString('o')
        CatalogRoutineCount = @($catalog.Routines).Count
        SearchableRoutines = $searchableRoutines
        SearchableRoutineCount = $searchableRoutines.Count
        SignatureOnlyRoutineCount = @($searchableRoutines | Where-Object { $_.PSObject.Properties.Name -contains 'CatalogRecordType' -and $_.CatalogRecordType -eq 'signature_only' }).Count
        InstalledMetadataPath = $installedMetadataPath
        InstalledMetadataPresent = $installedMetadataPresent
        InstalledMetadataReadable = $installedMetadataReadable
        InstalledMetadataError = $installedMetadataError
        InstalledRoutineIds = $installedRoutineIds
        InstalledRoutineCount = $installedRoutineIds.Count
    }
}
