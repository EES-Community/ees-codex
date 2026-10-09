#Requires -Version 5.1
[CmdletBinding()]
param([string]$EesPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'EES-Catalog.Common.ps1')

$context = Get-EesCatalogContext -RequestedEesPath $EesPath
$catalog = $context.Catalog

[ordered]@{
    catalog_name = 'EES_Tool_Metadata.json'
    catalog_path = $context.CatalogPath
    catalog_schema_version = $catalog.version
    catalog_sha256 = $context.CatalogSha256
    catalog_last_write_utc = $context.CatalogLastWriteUtc
    row_counts = [ordered]@{
        routines = @($catalog.Routines).Count
        categories = @($catalog.Categories).Count
        routine_categories = @($catalog.RoutineCategories).Count
        signatures = @($catalog.Signatures).Count
        parameters = @($catalog.Parameters).Count
        keywords = @($catalog.Keywords).Count
    }
    searchable_routines = $context.SearchableRoutineCount
    signature_only_routines = $context.SignatureOnlyRoutineCount
    selected_ees = $context.EesPath
    installed_metadata_path = $context.InstalledMetadataPath
    installed_metadata_present = $context.InstalledMetadataPresent
    installed_metadata_readable = $context.InstalledMetadataReadable
    installed_metadata_routines = $context.InstalledRoutineCount
    installed_metadata_error = $context.InstalledMetadataError
    userlib_path = $context.UserlibPath
    note = 'The packaged EES_Tool_Metadata.json is the sole catalog source. The selected installation metadata is compared only for installed_metadata_match and is never merged.'
} | ConvertTo-Json -Depth 6
