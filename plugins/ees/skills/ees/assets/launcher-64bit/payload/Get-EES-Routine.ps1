#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RoutineID,
    [string]$EesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'EES-Catalog.Common.ps1')

$context = Get-EesCatalogContext -RequestedEesPath $EesPath
$catalog = $context.Catalog
$requestedCanonical = ConvertTo-CanonicalRoutineId -RoutineID $RoutineID
$routine = @($catalog.Routines | Where-Object {
    (ConvertTo-CanonicalRoutineId -RoutineID ([string]$_.RoutineID)).Equals($requestedCanonical, [System.StringComparison]::OrdinalIgnoreCase) -or
    ([string]$_.Name).Equals($RoutineID, [System.StringComparison]::OrdinalIgnoreCase)
}) | Select-Object -First 1
if (-not $routine) { throw "Routine was not found in the combined EES catalog: $RoutineID" }

$id = [string]$routine.RoutineID
$keywords = @($catalog.Keywords | Where-Object { ([string]$_.RoutineID).Equals($id, [System.StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { [string]$_.Keyword })
$categories = @($catalog.RoutineCategories | Where-Object { ([string]$_.RoutineID).Equals($id, [System.StringComparison]::OrdinalIgnoreCase) } | ForEach-Object {
    [ordered]@{ category_id = $_.CategoryID; is_primary = $_.isPrimary }
})
$unitTypeDimensions = @{}
if ($catalog.PSObject.Properties.Name -contains 'UnitTypes') {
    foreach ($unit in $catalog.UnitTypes) { $unitTypeDimensions[[string]$unit.UnitType] = [string]$unit.Dimension }
}
$signatures = foreach ($signature in @($catalog.Signatures | Where-Object { ([string]$_.RoutineID).Equals($id, [System.StringComparison]::OrdinalIgnoreCase) })) {
    $parameters = @($catalog.Parameters | Where-Object { ([string]$_.SignatureID).Equals([string]$signature.SignatureID, [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object ParameterOrder | ForEach-Object {
        [ordered]@{
            order = $_.ParameterOrder
            name = $_.ParameterName
            direction = $_.Direction
            data_type = $_.DataType
            unit_type_code = $_.UnitType
            unit_type_dimension = if ($unitTypeDimensions.ContainsKey([string]$_.UnitType)) { $unitTypeDimensions[[string]$_.UnitType] } else { $null }
            required = $_.Required
            description = $_.Description
        }
    })
    [ordered]@{
        signature_id = $signature.SignatureID
        syntax = $signature.Syntax
        description = $signature.Description
        is_primary = $signature.IsPrimary
        parameters = $parameters
    }
}

$canonicalId = ConvertTo-CanonicalRoutineId -RoutineID $id
[ordered]@{
    ees_path = $context.EesPath
    installed_metadata_path = $context.InstalledMetadataPath
    packaged_catalog_path = $context.PackagedCatalogPath
    routine = [ordered]@{
        routine_id = $id
        name = $routine.Name
        kind = $routine.Kind
        display_name = $routine.DisplayName
        short_description = $routine.ShortDescription
        long_description = $routine.LongDescription
        categories = $categories
        keywords = $keywords
        required_load_directive = Get-EesRequiredLoadDirective -Routine $routine
        catalog_source = if ($context.PackagedRoutineIds.ContainsKey($id)) { 'Engineering Tool Dialog Database22' } else { 'Installed EES metadata supplement' }
        installed_metadata_match = $context.InstalledRoutineIds.ContainsKey($canonicalId)
        professional_only = $routine.isProfessionalOnly
        deprecated = $routine.isDeprecated
        replacement_routine_id = $routine.ReplacementRoutineID
        version_introduced = $routine.VersionIntroduced
        help_reference = $routine.Help
        picture_reference = $routine.Picture
        signatures = @($signatures)
    }
    note = 'Unit type descriptions come from Database22. Add required_load_directive when present, then verify applicability, availability, and units with a small EES compile test.'
} | ConvertTo-Json -Depth 10
