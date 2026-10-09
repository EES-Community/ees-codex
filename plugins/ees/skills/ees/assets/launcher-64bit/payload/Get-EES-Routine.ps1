#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RoutineID,
    [ValidateSet('Compact', 'Full')]
    [string]$Detail = 'Full',
    [string]$EesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'EES-Catalog.Common.ps1')

$context = Get-EesCatalogContext -RequestedEesPath $EesPath
$catalog = $context.Catalog
$requestedCanonical = ConvertTo-CanonicalRoutineId -RoutineID $RoutineID
$routine = @($context.SearchableRoutines | Where-Object {
    (ConvertTo-CanonicalRoutineId -RoutineID ([string]$_.RoutineID)).Equals($requestedCanonical, [System.StringComparison]::OrdinalIgnoreCase) -or
    ([string]$_.Name).Equals($RoutineID, [System.StringComparison]::OrdinalIgnoreCase)
}) | Select-Object -First 1
if (-not $routine) { throw "Routine was not found in EES_Tool_Metadata.json: $RoutineID" }

$id = [string]$routine.RoutineID
$routineSignatures = @($catalog.Signatures | Where-Object {
    (ConvertTo-CanonicalRoutineId -RoutineID ([string]$_.RoutineID)).Equals($requestedCanonical, [System.StringComparison]::OrdinalIgnoreCase)
})
$primarySyntax = @($routineSignatures | Where-Object { $_.IsPrimary } | ForEach-Object { [string]$_.Syntax })
if ($primarySyntax.Count -eq 0) { $primarySyntax = @($routineSignatures | Select-Object -First 1 | ForEach-Object { [string]$_.Syntax }) }
$installedMetadataMatch = Get-InstalledMetadataMatch -Context $context -RoutineID $id

$compactRoutine = [ordered]@{
    routine_id = $id
    routine_type = $routine.Kind
    short_description = $routine.ShortDescription
    primary_syntax = @($primarySyntax)
    required_load_directive = Get-EesRequiredLoadDirective -Routine $routine
    installed_metadata_match = $installedMetadataMatch
    deprecated = $routine.isDeprecated
    replacement_routine_id = $routine.ReplacementRoutineID
}

if ($Detail -eq 'Compact') {
    [ordered]@{ routine = $compactRoutine } | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

$keywords = @($catalog.Keywords | Where-Object {
    (ConvertTo-CanonicalRoutineId -RoutineID ([string]$_.RoutineID)).Equals($requestedCanonical, [System.StringComparison]::OrdinalIgnoreCase)
} | ForEach-Object { [string]$_.Keyword })
$categories = @($catalog.RoutineCategories | Where-Object {
    (ConvertTo-CanonicalRoutineId -RoutineID ([string]$_.RoutineID)).Equals($requestedCanonical, [System.StringComparison]::OrdinalIgnoreCase)
} | ForEach-Object {
    [ordered]@{ category_id = $_.CategoryID; is_primary = $_.isPrimary }
})
$signatures = foreach ($signature in $routineSignatures) {
    $parameterRows = @($catalog.Parameters | Where-Object {
        ([string]$_.SignatureID).Equals([string]$signature.SignatureID, [System.StringComparison]::OrdinalIgnoreCase)
    })
    $sharedParameterSource = $null
    if ($parameterRows.Count -eq 0) {
        $parameterRows = @($catalog.Parameters | Where-Object {
            (ConvertTo-CanonicalRoutineId -RoutineID ([string]$_.RoutineID)).Equals($requestedCanonical, [System.StringComparison]::OrdinalIgnoreCase) -and
            ([string]$_.SignatureID).Equals([string]$_.RoutineID, [System.StringComparison]::OrdinalIgnoreCase)
        })
        if ($parameterRows.Count -gt 0) { $sharedParameterSource = [string]$parameterRows[0].SignatureID }
    }
    $parameters = @($parameterRows | Sort-Object ParameterOrder | ForEach-Object {
        [ordered]@{
            order = $_.ParameterOrder
            name = $_.ParameterName
            direction = $_.Direction
            data_type = $_.DataType
            unit_type_code = $_.UnitType
            required = $_.Required
            description = $_.Description
        }
    })
    $signatureResult = [ordered]@{
        signature_id = $signature.SignatureID
        syntax = $signature.Syntax
        description = $signature.Description
        is_primary = $signature.IsPrimary
        parameters = $parameters
    }
    if ($sharedParameterSource) { $signatureResult['shared_parameter_source_signature_id'] = $sharedParameterSource }
    $signatureResult
}

[ordered]@{
    ees_path = $context.EesPath
    catalog_path = $context.CatalogPath
    catalog_schema_version = $catalog.version
    catalog_sha256 = $context.CatalogSha256
    catalog_last_write_utc = $context.CatalogLastWriteUtc
    installed_metadata_path = $context.InstalledMetadataPath
    installed_metadata_readable = $context.InstalledMetadataReadable
    installed_metadata_error = $context.InstalledMetadataError
    routine = [ordered]@{
        routine_id = $id
        name = $routine.Name
        kind = $routine.Kind
        display_name = $routine.DisplayName
        short_description = $routine.ShortDescription
        long_description = $routine.LongDescription
        categories = $categories
        keywords = $keywords
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
        picture_reference = $routine.Picture
        signatures = @($signatures)
    }
    note = 'EES_Tool_Metadata.json is the sole routine-detail source. Numeric unit_type_code values require confirmation from routine documentation or a compile test.'
} | ConvertTo-Json -Depth 10
