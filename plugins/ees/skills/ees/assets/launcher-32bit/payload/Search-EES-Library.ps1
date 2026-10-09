#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Query,
    [ValidateRange(1, 50)]
    [int]$Limit = 10,
    [ValidateSet('Compact', 'Full')]
    [string]$Detail = 'Full',
    [string]$EesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'EES-Catalog.Common.ps1')

if ([string]::IsNullOrWhiteSpace($Query)) {
    throw 'Query must contain at least one non-whitespace character.'
}

$context = Get-EesCatalogContext -RequestedEesPath $EesPath
$catalog = $context.Catalog
$queryLower = $Query.Trim().ToLowerInvariant()
$tokens = @($queryLower -split '\s+' | Where-Object { $_.Length -ge 2 } | Select-Object -Unique)
$keywordsByRoutine = @{}
foreach ($item in $catalog.Keywords) {
    $relationId = ConvertTo-CanonicalRoutineId -RoutineID ([string]$item.RoutineID)
    if (-not $keywordsByRoutine.ContainsKey($relationId)) { $keywordsByRoutine[$relationId] = @() }
    $keywordsByRoutine[$relationId] += [string]$item.Keyword
}
$categoriesByRoutine = @{}
foreach ($item in $catalog.RoutineCategories) {
    $relationId = ConvertTo-CanonicalRoutineId -RoutineID ([string]$item.RoutineID)
    if (-not $categoriesByRoutine.ContainsKey($relationId)) { $categoriesByRoutine[$relationId] = @() }
    $categoriesByRoutine[$relationId] += [string]$item.CategoryID
}
$signaturesByRoutine = @{}
foreach ($item in $catalog.Signatures) {
    $relationId = ConvertTo-CanonicalRoutineId -RoutineID ([string]$item.RoutineID)
    if (-not $signaturesByRoutine.ContainsKey($relationId)) { $signaturesByRoutine[$relationId] = @() }
    $signaturesByRoutine[$relationId] += $item
}

$matches = foreach ($routine in $context.SearchableRoutines) {
    $routineId = [string]$routine.RoutineID
    $relationId = ConvertTo-CanonicalRoutineId -RoutineID $routineId
    $keywords = if ($keywordsByRoutine.ContainsKey($relationId)) { @($keywordsByRoutine[$relationId]) } else { @() }
    $categories = if ($categoriesByRoutine.ContainsKey($relationId)) { @($categoriesByRoutine[$relationId]) } else { @() }
    $signatures = if ($signaturesByRoutine.ContainsKey($relationId)) { @($signaturesByRoutine[$relationId]) } else { @() }
    $nameText = (([string]$routine.Name) + ' ' + ([string]$routine.DisplayName)).ToLowerInvariant()
    $descriptionText = (([string]$routine.ShortDescription) + ' ' + ([string]$routine.LongDescription)).ToLowerInvariant()
    $keywordText = ($keywords -join ' ').ToLowerInvariant()
    $categoryText = ($categories -join ' ').ToLowerInvariant()
    $syntaxText = (($signatures | ForEach-Object { $_.Syntax }) -join ' ').ToLowerInvariant()
    $score = 0
    if ($nameText -eq $queryLower) { $score += 200 }
    if ($nameText.Contains($queryLower)) { $score += 80 }
    if ($keywordText.Contains($queryLower)) { $score += 60 }
    if ($syntaxText.Contains($queryLower)) { $score += 50 }
    if ($categoryText.Contains($queryLower)) { $score += 35 }
    if ($descriptionText.Contains($queryLower)) { $score += 25 }
    foreach ($token in $tokens) {
        if ($nameText.Contains($token)) { $score += 20 }
        if ($keywordText.Contains($token)) { $score += 15 }
        if ($syntaxText.Contains($token)) { $score += 12 }
        if ($categoryText.Contains($token)) { $score += 8 }
        if ($descriptionText.Contains($token)) { $score += 5 }
    }
    if ($score -le 0) { continue }

    $primarySyntax = @($signatures | Where-Object { $_.IsPrimary } | ForEach-Object { [string]$_.Syntax })
    if ($primarySyntax.Count -eq 0) { $primarySyntax = @($signatures | Select-Object -First 1 | ForEach-Object { [string]$_.Syntax }) }
    $installedMetadataMatch = Get-InstalledMetadataMatch -Context $context -RoutineID $routineId

    if ($Detail -eq 'Compact') {
        [pscustomobject][ordered]@{
            score = $score
            routine_id = $routineId
            routine_type = $routine.Kind
            short_description = $routine.ShortDescription
            primary_syntax = @($primarySyntax)
            required_load_directive = Get-EesRequiredLoadDirective -Routine $routine
            installed_metadata_match = $installedMetadataMatch
            deprecated = $routine.isDeprecated
            replacement_routine_id = $routine.ReplacementRoutineID
        }
    }
    else {
        [pscustomobject][ordered]@{
            score = $score
            routine_id = $routineId
            name = $routine.Name
            kind = $routine.Kind
            display_name = $routine.DisplayName
            short_description = $routine.ShortDescription
            categories = @($categories)
            keywords = @($keywords)
            primary_syntax = @($primarySyntax)
            required_load_directive = Get-EesRequiredLoadDirective -Routine $routine
            catalog_source = 'EES_Tool_Metadata.json'
            metadata_record_type = if ($routine.PSObject.Properties.Name -contains 'CatalogRecordType') { $routine.CatalogRecordType } else { 'routine' }
            installed_metadata_match = $installedMetadataMatch
            professional_only = $routine.isProfessionalOnly
            deprecated = $routine.isDeprecated
            replacement_routine_id = $routine.ReplacementRoutineID
            version_introduced = $routine.VersionIntroduced
            help_reference = $routine.Help
        }
    }
}

$ranked = @($matches | Sort-Object @{Expression='score';Descending=$true}, routine_id | Select-Object -First $Limit)
$selected = @()
if ($Detail -eq 'Compact') {
    $selected = @($ranked | Select-Object routine_id, routine_type, short_description, primary_syntax, required_load_directive, installed_metadata_match, deprecated, replacement_routine_id)
}
else { $selected = @($ranked) }
if ($Detail -eq 'Compact') {
    [ordered]@{
        query = $Query
        result_count = $selected.Count
        results = $selected
    } | ConvertTo-Json -Depth 6 -Compress
}
else {
    [ordered]@{
        query = $Query
        result_count = $selected.Count
        catalog_routine_count = $context.CatalogRoutineCount
        searchable_routine_count = $context.SearchableRoutineCount
        signature_only_routine_count = $context.SignatureOnlyRoutineCount
        catalog_path = $context.CatalogPath
        catalog_schema_version = $catalog.version
        catalog_sha256 = $context.CatalogSha256
        catalog_last_write_utc = $context.CatalogLastWriteUtc
        ees_path = $context.EesPath
        installed_metadata_path = $context.InstalledMetadataPath
        installed_metadata_readable = $context.InstalledMetadataReadable
        installed_metadata_routine_count = $context.InstalledRoutineCount
        installed_metadata_error = $context.InstalledMetadataError
        userlib_path = $context.UserlibPath
        userlib_available = Test-Path -LiteralPath $context.UserlibPath -PathType Container
        note = 'EES_Tool_Metadata.json is the sole search source. installed_metadata_match only reports whether the selected EES installation metadata lists the routine; compile-test the selected signature and units.'
        results = $selected
    } | ConvertTo-Json -Depth 8
}
