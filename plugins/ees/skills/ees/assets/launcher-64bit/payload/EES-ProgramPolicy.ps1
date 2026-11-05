#Requires -Version 5.1

Set-StrictMode -Version Latest

function Get-EesAllowedExtensions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directive
    )

    switch ($Directive.ToUpperInvariant()) {
        'EXPORT' { return @('.txt', '.csv', '.dat', '.tab') }
        'EXPORTTEXT' { return @('.txt', '.csv', '.dat', '.tab') }
        'EXPORTPLOT' { return @('.bmp', '.jpg', '.tif', '.emf', '.wmf', '.gif', '.plt') }
        'SAVELOOKUP' { return @('.lkt', '.lkt64', '.txt', '.csv', '.dat', '.xlsx') }
        'SAVETABLE' { return @('.lkt', '.lkt64', '.txt', '.csv', '.dat', '.tab', '.xlsx') }
        'SAVEVARINFO' { return @('.var') }
        'IMPORT' { return @('.txt', '.csv', '.dat', '.tab') }
        'IMPORTTEXT' { return @('.txt', '.csv', '.dat', '.tab') }
        'OPENLOOKUP' { return @('.lkt', '.lkt64', '.txt', '.csv', '.dat', '.xlsx') }
        default { throw "No file-extension policy is defined for EES directive `$$Directive." }
    }
}

function Assert-EesArtifactExtension {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Directive
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $allowed = @(Get-EesAllowedExtensions -Directive $Directive)
    if ($allowed -notcontains $extension) {
        throw "The $Directive artifact extension '$extension' is not supported. Allowed extensions: $($allowed -join ', ')."
    }
}

function Assert-EesProgramPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [bool]$PrimaryOutputDeclared = $false,

        [string[]]$InputBindingNames = @(),

        [string[]]$OutputBindingNames = @()
    )

    $namePattern = '^[A-Z][A-Z0-9_]*$'
    $inputNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $outputNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($name in @($InputBindingNames)) {
        if ([string]::IsNullOrWhiteSpace($name) -or $name -cnotmatch $namePattern) {
            throw "Input binding names must use uppercase letters, digits, and underscores and start with a letter: '$name'."
        }
        if ($name -eq 'OUTPUT_FILE' -or -not $inputNames.Add($name)) {
            throw "Duplicate or reserved input binding name: $name."
        }
    }
    foreach ($name in @($OutputBindingNames)) {
        if ([string]::IsNullOrWhiteSpace($name) -or $name -cnotmatch $namePattern) {
            throw "Output binding names must use uppercase letters, digits, and underscores and start with a letter: '$name'."
        }
        if ($name -eq 'OUTPUT_FILE' -or $inputNames.Contains($name) -or -not $outputNames.Add($name)) {
            throw "Duplicate or reserved output binding name: $name."
        }
    }

    $allowedLoads = @(
        '$Load Component Library',
        '$Load Mechanical',
        '$Load NASA',
        '$Load Incompressible'
    )
    $blockedDirectives = @(
        'RUNMACROAFTER',
        'RUNMACROBEFORE',
        'PYTHON',
        'INCLUDE',
        'DEFAULTDIRECTORY',
        'LATEXPDF',
        'INPUT'
    )
    $outputDirectives = @('EXPORT', 'EXPORTTEXT', 'EXPORTPLOT', 'SAVELOOKUP', 'SAVETABLE', 'SAVEVARINFO')
    $inputDirectives = @('IMPORT', 'IMPORTTEXT', 'OPENLOOKUP')
    $inputUses = New-Object System.Collections.Generic.List[object]
    $outputUses = New-Object System.Collections.Generic.List[object]
    $primaryUses = New-Object System.Collections.Generic.List[object]
    $usedNames = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::OrdinalIgnoreCase)
    $lines = @($Text -split "`r?`n")

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]
        $directiveMatch = [regex]::Match($line, '^\s*\$(?<name>[A-Za-z][A-Za-z0-9_]*)\b')
        $placeholderMatches = @([regex]::Matches($line, '\{\{(?<name>[^{}]+)\}\}'))

        foreach ($placeholderMatch in $placeholderMatches) {
            $placeholderName = [string]$placeholderMatch.Groups['name'].Value
            if ($placeholderName -cnotmatch $namePattern) {
                throw "Invalid artifact placeholder {{$placeholderName}} on line $($index + 1). Placeholder names must be uppercase."
            }
        }

        if (-not $directiveMatch.Success) {
            if ($placeholderMatches.Count -gt 0) {
                throw "Artifact placeholders may appear only on supported EES input or output directives (line $($index + 1))."
            }
            continue
        }

        $directive = $directiveMatch.Groups['name'].Value.ToUpperInvariant()
        if ($blockedDirectives -contains $directive) {
            throw "Blocked EES directive `$$directive on line $($index + 1). It can execute code, change file resolution, include unvalidated content, or require interactive input."
        }

        if ($directive -eq 'LOAD') {
            $normalizedLoad = [regex]::Replace($line.Trim(), '\s+', ' ')
            if ($allowedLoads -notcontains $normalizedLoad) {
                throw "Blocked library directive $normalizedLoad. Allowed values are: $($allowedLoads -join ', ')."
            }
        }

        $isOutputDirective = $outputDirectives -contains $directive
        $isInputDirective = $inputDirectives -contains $directive
        if (-not $isOutputDirective -and -not $isInputDirective) {
            if ($placeholderMatches.Count -gt 0) {
                throw "Artifact placeholders are not supported on `$$directive (line $($index + 1))."
            }
            continue
        }

        if ($placeholderMatches.Count -ne 1) {
            throw "`$$directive on line $($index + 1) must contain exactly one validated artifact placeholder."
        }
        $bindingName = [string]$placeholderMatches[0].Groups['name'].Value
        $quotedPlaceholder = "'\s*\{\{$([regex]::Escape($bindingName))\}\}\s*'"
        $directivePattern = [regex]::Escape('$' + $directive)
        $filePositionPattern = switch ($directive) {
            { $_ -in @('EXPORT', 'EXPORTTEXT') } {
                "^\s*$directivePattern(?:\s+/[^\s']+)*\s+$quotedPlaceholder(?:\s|$)"
                break
            }
            { $_ -in @('IMPORT', 'IMPORTTEXT', 'EXPORTPLOT', 'OPENLOOKUP', 'SAVEVARINFO') } {
                "^\s*$directivePattern\s+$quotedPlaceholder(?:\s|$)"
                break
            }
            { $_ -in @('SAVELOOKUP', 'SAVETABLE') } {
                "^\s*$directivePattern\s+(?:'[^']+'|[^\s']+)\s+$quotedPlaceholder(?:\s|$)"
                break
            }
        }
        if (-not [regex]::IsMatch($line, $filePositionPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            throw "The {{$bindingName}} placeholder on line $($index + 1) must be the complete single-quoted filename argument for `$$directive."
        }
        if ($line.Contains('?')) {
            throw "Interactive file selection is blocked on `$$directive line $($index + 1). Use only the declared artifact placeholder."
        }
        if ($directive -eq 'OPENLOOKUP' -and $line -match '(?i)/FORMAT\s*=') {
            throw '$OpenLookup /FORMAT names a second file and is not supported by the validated one-file binding.'
        }
        if ($usedNames.ContainsKey($bindingName)) {
            $usedNames[$bindingName]++
        }
        else {
            $usedNames.Add($bindingName, 1)
        }

        $use = [pscustomobject][ordered]@{
            name = $bindingName
            directive = $directive
            line_number = $index + 1
        }

        if ($isOutputDirective) {
            if ($bindingName -eq 'OUTPUT_FILE') {
                if ($directive -notin @('EXPORT', 'EXPORTTEXT')) {
                    throw '{{OUTPUT_FILE}} may be used only with $Export or $ExportText.'
                }
                $primaryUses.Add($use)
            }
            elseif (-not $outputNames.Contains($bindingName)) {
                throw "Output placeholder {{$bindingName}} on line $($index + 1) is not declared in the artifact manifest."
            }
            $outputUses.Add($use)
        }
        else {
            if (-not $inputNames.Contains($bindingName)) {
                throw "Input placeholder {{$bindingName}} on line $($index + 1) is not declared in the artifact manifest."
            }
            $inputUses.Add($use)
        }
    }

    foreach ($name in $inputNames) {
        if (-not $usedNames.ContainsKey($name) -or $usedNames[$name] -ne 1) {
            throw "Input binding $name must appear exactly once in the EES program."
        }
    }
    foreach ($name in $outputNames) {
        if (-not $usedNames.ContainsKey($name) -or $usedNames[$name] -ne 1) {
            throw "Output binding $name must appear exactly once in the EES program."
        }
    }

    if (-not $PrimaryOutputDeclared -or $primaryUses.Count -ne 1) {
        throw 'The launcher requires OutputPath and exactly one {{OUTPUT_FILE}} placeholder on $Export or $ExportText.'
    }

    return [pscustomobject][ordered]@{
        mode = 'Solve'
        primary_output_use = if ($primaryUses.Count -eq 1) { $primaryUses[0] } else { $null }
        input_uses = @($inputUses | ForEach-Object { $_ })
        output_uses = @($outputUses | Where-Object { $_.name -ne 'OUTPUT_FILE' } | ForEach-Object { $_ })
    }
}
