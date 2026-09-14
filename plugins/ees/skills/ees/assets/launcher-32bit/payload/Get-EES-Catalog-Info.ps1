#Requires -Version 5.1
[CmdletBinding()]
param([string]$EesPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'EES-Catalog.Common.ps1')

$context = Get-EesCatalogContext -RequestedEesPath $EesPath
$catalog = $context.Catalog
$validationPath = Join-Path $PSScriptRoot 'catalog\catalog-validation.json'
$validation = if (Test-Path -LiteralPath $validationPath -PathType Leaf) {
    Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
}
else { $null }

[ordered]@{
    catalog_name = if ($context.HasPackagedCatalog) { $catalog.catalog_name } else { 'Installed EES metadata only' }
    catalog_version = if ($context.HasPackagedCatalog) { $catalog.catalog_version } else { $null }
    catalog_schema_version = if ($context.HasPackagedCatalog) { $catalog.catalog_schema_version } else { $catalog.version }
    source_sha256 = if ($context.HasPackagedCatalog) { $catalog.source.sha256 } else { $null }
    validation_status = if ($validation) { $validation.status } else { 'validation report not packaged' }
    normalized_row_counts = if ($validation) { $validation.row_counts } else { $null }
    documented_routines = if ($context.HasPackagedCatalog) { @($catalog.Routines | Where-Object { $context.PackagedRoutineIds.ContainsKey([string]$_.RoutineID) }).Count } else { 0 }
    installed_metadata_routines = $context.InstalledRoutineCount
    combined_searchable_routines = $context.CatalogRoutineCount
    selected_ees = $context.EesPath
    installed_metadata_path = $context.InstalledMetadataPath
    userlib_path = $context.UserlibPath
} | ConvertTo-Json -Depth 6
