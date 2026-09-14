#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Query,
    [ValidateRange(1, 50)]
    [int]$Limit = 10,
    [string]$EesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'EES-Catalog.Common.ps1')

$context = Get-EesCatalogContext -RequestedEesPath $EesPath
$catalog = $context.Catalog
$queryLower = $Query.Trim().ToLowerInvariant()
$tokens = @($queryLower -split '\s+' | Where-Object { $_.Length -ge 2 } | Select-Object -Unique)
$keywordsByRoutine = @{}
foreach ($item in $catalog.Keywords) {
    if (-not $keywordsByRoutine.ContainsKey($item.RoutineID)) { $keywordsByRoutine[$item.RoutineID] = @() }
    $keywordsByRoutine[$item.RoutineID] += [string]$item.Keyword
}
$categoriesByRoutine = @{}
foreach ($item in $catalog.RoutineCategories) {
    if (-not $categoriesByRoutine.ContainsKey($item.RoutineID)) { $categoriesByRoutine[$item.RoutineID] = @() }
    $categoriesByRoutine[$item.RoutineID] += [string]$item.CategoryID
}
$signaturesByRoutine = @{}
foreach ($item in $catalog.Signatures) {
    if (-not $signaturesByRoutine.ContainsKey($item.RoutineID)) { $signaturesByRoutine[$item.RoutineID] = @() }
    $signaturesByRoutine[$item.RoutineID] += $item
}

$matches = foreach ($routine in $catalog.Routines) {
    $routineId = [string]$routine.RoutineID
    $keywords = if ($keywordsByRoutine.ContainsKey($routineId)) { @($keywordsByRoutine[$routineId]) } else { @() }
    $categories = if ($categoriesByRoutine.ContainsKey($routineId)) { @($categoriesByRoutine[$routineId]) } else { @() }
    $signatures = if ($signaturesByRoutine.ContainsKey($routineId)) { @($signaturesByRoutine[$routineId]) } else { @() }
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
    $canonicalId = ConvertTo-CanonicalRoutineId -RoutineID $routineId
    [pscustomobject]@{
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
        catalog_source = if ($context.PackagedRoutineIds.ContainsKey($routineId)) { 'Engineering Tool Dialog Database22' } else { 'Installed EES metadata supplement' }
        installed_metadata_match = $context.InstalledRoutineIds.ContainsKey($canonicalId)
        professional_only = $routine.isProfessionalOnly
        deprecated = $routine.isDeprecated
        replacement_routine_id = $routine.ReplacementRoutineID
        version_introduced = $routine.VersionIntroduced
        help_reference = $routine.Help
    }
}

$selected = @($matches | Sort-Object @{Expression='score';Descending=$true}, routine_id | Select-Object -First $Limit)
[ordered]@{
    query = $Query
    result_count = $selected.Count
    combined_catalog_routine_count = $context.CatalogRoutineCount
    installed_metadata_routine_count = $context.InstalledRoutineCount
    ees_path = $context.EesPath
    installed_metadata_path = $context.InstalledMetadataPath
    packaged_catalog_path = $context.PackagedCatalogPath
    packaged_catalog_name = if ($context.HasPackagedCatalog) { $catalog.catalog_name } else { $null }
    packaged_catalog_version = if ($context.HasPackagedCatalog) { $catalog.catalog_version } else { $null }
    packaged_catalog_source_sha256 = if ($context.HasPackagedCatalog) { $catalog.source.sha256 } else { $null }
    userlib_path = $context.UserlibPath
    userlib_available = Test-Path -LiteralPath $context.UserlibPath -PathType Container
    note = 'installed_metadata_match means the routine is listed by this EES installation. Some documented libraries are installed but disabled by default; include the returned required_load_directive when present, then compile-test the selected signature.'
    results = $selected
} | ConvertTo-Json -Depth 8
