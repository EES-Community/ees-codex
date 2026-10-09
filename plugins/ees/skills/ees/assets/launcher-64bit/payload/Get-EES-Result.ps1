#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,
    [string[]]$Variable = @(),
    [string[]]$Pattern = @(),
    [ValidateSet('Compact', 'Full')]
    [string]$Detail = 'Full'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-ResultError {
    param(
        [string]$Code,
        [string]$Message,
        [object[]]$MissingVariables = @(),
        [object[]]$UnmatchedPatterns = @(),
        [object[]]$ParseWarnings = @(),
        [object[]]$DuplicateNames = @()
    )

    $payload = [ordered]@{
        status = 'error'
        code = $Code
        message = $Message
        missing_variables = @($MissingVariables)
        unmatched_patterns = @($UnmatchedPatterns)
        parse_warnings = @($ParseWarnings)
        duplicate_names = @($DuplicateNames)
    }
    throw ($payload | ConvertTo-Json -Depth 6 -Compress)
}

function Get-NormalizedSelections {
    param(
        [string[]]$Values,
        [string]$Label
    )

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Values)) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            New-ResultError -Code 'invalid_selector' -Message "$Label selectors must not be empty or whitespace."
        }
        $trimmed = $value.Trim()
        if ($seen.Add($trimmed)) { $normalized.Add($trimmed) }
    }
    return @($normalized)
}

function Get-Sha256Hex {
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

$configPath = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    New-ResultError -Code 'configuration_missing' -Message "Launcher configuration was not found: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if (-not ($config.PSObject.Properties.Name -contains 'workspace_root') -or
    [string]::IsNullOrWhiteSpace([string]$config.workspace_root)) {
    New-ResultError -Code 'configuration_invalid' -Message 'Launcher configuration does not contain a usable workspace_root.'
}

$workspaceRoot = [System.IO.Path]::GetFullPath([string]$config.workspace_root).TrimEnd('\', '/')
$requestedPath = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
$candidatePath = if ([System.IO.Path]::IsPathRooted($requestedPath)) {
    [System.IO.Path]::GetFullPath($requestedPath)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $requestedPath))
}

if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
    New-ResultError -Code 'result_not_found' -Message "EES result file was not found: $candidatePath"
}
$resolvedPath = (Resolve-Path -LiteralPath $candidatePath).Path
$workspacePrefix = $workspaceRoot + [System.IO.Path]::DirectorySeparatorChar
if (-not $resolvedPath.StartsWith($workspacePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    New-ResultError -Code 'outside_workspace' -Message "Result files must be inside the configured workspace: $workspaceRoot"
}
if (-not [System.IO.Path]::GetExtension($resolvedPath).Equals('.txt', [System.StringComparison]::OrdinalIgnoreCase)) {
    New-ResultError -Code 'unsupported_file_type' -Message 'Get-EES-Result.ps1 reads only EES text exports with a .txt extension.'
}

$requestedVariables = @(Get-NormalizedSelections -Values $Variable -Label 'Variable')
$requestedPatterns = @(Get-NormalizedSelections -Values $Pattern -Label 'Pattern')
if ($Detail -eq 'Compact' -and $requestedVariables.Count -eq 0 -and $requestedPatterns.Count -eq 0) {
    New-ResultError -Code 'selector_required' -Message 'Compact mode requires at least one -Variable or -Pattern selector.'
}

$lines = [System.IO.File]::ReadAllLines($resolvedPath)
$records = New-Object System.Collections.Generic.List[object]
$parseWarnings = New-Object System.Collections.Generic.List[object]
$numericPattern = '[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?'

for ($index = 0; $index -lt $lines.Length; $index++) {
    $line = [string]$lines[$index]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $tabIndex = $line.IndexOf("`t")
    if ($tabIndex -lt 1) {
        $parseWarnings.Add([ordered]@{
            line_number = $index + 1
            code = 'missing_tab_separator'
            message = 'Expected a variable name followed by a tab-delimited value.'
        })
        continue
    }

    $name = $line.Substring(0, $tabIndex).Trim()
    $valueText = $line.Substring($tabIndex + 1)
    if ([string]::IsNullOrWhiteSpace($name)) {
        $parseWarnings.Add([ordered]@{
            line_number = $index + 1
            code = 'missing_variable_name'
            message = 'The exported line has no variable name.'
        })
        continue
    }

    $match = [System.Text.RegularExpressions.Regex]::Match(
        $valueText,
        '^\s*(?<number>' + $numericPattern + ')\s*(?<units>\[[^\r\n]*\])?\s*$',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if (-not $match.Success) {
        $parseWarnings.Add([ordered]@{
            line_number = $index + 1
            variable_name = $name
            code = 'unsupported_value'
            message = 'Expected a finite numeric value in decimal or scientific notation, optionally followed by bracketed units.'
        })
        continue
    }

    $units = if ($match.Groups['units'].Success) { $match.Groups['units'].Value } else { $null }
    $records.Add([pscustomobject][ordered]@{
        variable_name = $name
        raw_value = $match.Groups['number'].Value
        units = $units
    })
}

$duplicateNames = @($records | Group-Object { $_.variable_name.ToUpperInvariant() } | Where-Object { $_.Count -gt 1 } | ForEach-Object {
    [ordered]@{
        variable_name = [string]$_.Group[0].variable_name
        count = $_.Count
    }
})

if ($parseWarnings.Count -gt 0 -or $duplicateNames.Count -gt 0) {
    New-ResultError `
        -Code 'result_parse_failed' `
        -Message 'The EES result contains malformed, unsupported, or duplicate entries. Inspect the diagnostics or read the raw export.' `
        -ParseWarnings @($parseWarnings | ForEach-Object { $_ }) `
        -DuplicateNames $duplicateNames
}

if ($Detail -eq 'Full') {
    $file = Get-Item -LiteralPath $resolvedPath
    [ordered]@{
        status = 'success'
        detail = 'Full'
        source_path = $resolvedPath
        workspace_root = $workspaceRoot
        file_size_bytes = $file.Length
        file_last_write_utc = $file.LastWriteTimeUtc.ToString('o')
        file_sha256 = Get-Sha256Hex -FilePath $resolvedPath
        line_count = $lines.Length
        result_count = $records.Count
        parse_warnings = @()
        duplicate_names = @()
        results = @($records | ForEach-Object { $_ })
    } | ConvertTo-Json -Depth 6
    return
}

$missingVariables = New-Object System.Collections.Generic.List[string]
$unmatchedPatterns = New-Object System.Collections.Generic.List[string]
$selectedNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($requestedVariable in $requestedVariables) {
    $matches = @($records | Where-Object { $_.variable_name.Equals($requestedVariable, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($matches.Count -eq 0) { $missingVariables.Add($requestedVariable) }
    else { [void]$selectedNames.Add([string]$matches[0].variable_name) }
}
foreach ($requestedPattern in $requestedPatterns) {
    $matches = @($records | Where-Object { $_.variable_name -like $requestedPattern })
    if ($matches.Count -eq 0) { $unmatchedPatterns.Add($requestedPattern) }
    else {
        foreach ($matchedRecord in $matches) { [void]$selectedNames.Add([string]$matchedRecord.variable_name) }
    }
}

$selectedRecords = @($records | Where-Object { $selectedNames.Contains([string]$_.variable_name) })
$response = [ordered]@{
    status = if ($missingVariables.Count -eq 0 -and $unmatchedPatterns.Count -eq 0) { 'success' } else { 'error' }
    detail = 'Compact'
    result_count = $selectedRecords.Count
    missing_variables = @($missingVariables)
    unmatched_patterns = @($unmatchedPatterns)
    parse_warnings = @()
    results = $selectedRecords
}

if ($response.status -eq 'error') {
    New-ResultError `
        -Code 'selection_incomplete' `
        -Message 'One or more requested EES result selections were not found.' `
        -MissingVariables @($missingVariables | ForEach-Object { $_ }) `
        -UnmatchedPatterns @($unmatchedPatterns | ForEach-Object { $_ })
}

$response | ConvertTo-Json -Depth 6 -Compress
