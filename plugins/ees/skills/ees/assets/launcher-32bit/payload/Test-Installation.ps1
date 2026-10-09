#Requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Launcher configuration was not found: $ConfigPath"
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $program = Join-Path $config.workspace_root 'examples\heat_exchanger.txt'
    $resultDirectory = Join-Path $config.workspace_root 'results'
    New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
    $output = Join-Path $resultDirectory 'installation_test.txt'
    $launcher = Join-Path $config.install_directory 'Run-EES.ps1'
    $profileAutoloadBitsBefore = if ($config.ees_architecture -eq '32-bit') {
        if (-not (Test-Path -LiteralPath $config.profile_path -PathType Leaf)) {
            throw "The 32-bit EES preference file was not found: $($config.profile_path)"
        }
        $profileBytes = [System.IO.File]::ReadAllBytes($config.profile_path)
        if ($profileBytes.Length -le 0x3D) {
            throw "The 32-bit EES preference file is too short to inspect its library-autoload setting: $($config.profile_path)"
        }
        ([int]$profileBytes[0x3D] -band 0x1F)
    }
    else { $null }
    $hostExe = if (Test-Path -LiteralPath (Join-Path $PSHOME 'powershell.exe')) {
        Join-Path $PSHOME 'powershell.exe'
    }
    else { Join-Path $PSHOME 'pwsh.exe' }

    $launcherOutput = & $hostExe -NoProfile -ExecutionPolicy Bypass -File $launcher `
        -WorkspaceRoot $config.workspace_root `
        -ProgramPath $program `
        -OutputPath $output `
        -EesPath $config.ees_path `
        -TimeoutSeconds 90 `
        -Force 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Launcher returned exit code $LASTEXITCODE. $($launcherOutput -join [Environment]::NewLine)"
    }
    $resultText = Get-Content -LiteralPath $output -Raw
    if ($resultText -notmatch '(?m)^Q_dot\s+2\.00000000E\+02\s+\[kW\]') {
        throw "EES ran, but the expected Q_dot = 200 kW result was not found in $output"
    }
    if ([string]$config.version -ne [string]$config.coordinated_plugin_version -or
        $config.launcher_api_level -ne 2 -or
        @($config.capabilities.catalog_detail_modes) -notcontains 'Compact' -or
        @($config.capabilities.result_detail_modes) -notcontains 'Compact' -or
        @($config.capabilities.result_selectors) -notcontains 'Pattern') {
        throw 'The launcher configuration does not advertise the expected API level and compact catalog/result capabilities.'
    }
    $resultHelper = Join-Path $config.install_directory 'Get-EES-Result.ps1'
    $compactResult = & $resultHelper `
        -Path $output `
        -Variable 'Q_dot' `
        -Pattern 'T_*' `
        -Detail Compact | ConvertFrom-Json
    if ($compactResult.status -ne 'success' -or
        $compactResult.result_count -ne 3 -or
        @($compactResult.results | Where-Object {
            $_.variable_name -eq 'Q_dot' -and $_.raw_value -eq '2.00000000E+02' -and $_.units -eq '[kW]'
        }).Count -ne 1) {
        throw 'Compact result extraction did not preserve the expected water-heating output and units.'
    }
    $fullResult = & $resultHelper -Path $output -Detail Full | ConvertFrom-Json
    if ($fullResult.status -ne 'success' -or
        $fullResult.result_count -ne 4 -or
        [string]::IsNullOrWhiteSpace([string]$fullResult.file_sha256)) {
        throw 'Full result extraction did not return all installation-test values and file diagnostics.'
    }
    $missingSelectionRejected = $false
    try {
        & $resultHelper -Path $output -Variable 'not_exported' -Detail Compact | Out-Null
    }
    catch {
        $missingSelectionRejected = $_.Exception.Message -match 'selection_incomplete'
    }
    if (-not $missingSelectionRejected) {
        throw 'Compact result extraction did not reject a missing requested variable.'
    }
    $catalogInfo = & (Join-Path $config.install_directory 'Get-EES-Catalog-Info.ps1') -EesPath $config.ees_path | ConvertFrom-Json
    if ($catalogInfo.catalog_name -ne 'EES_Tool_Metadata.json' -or
        $catalogInfo.catalog_schema_version -ne 1 -or
        $catalogInfo.catalog_sha256 -ne 'A87F0FD43C68E514C824BA57BD69643D78BC10889137F3D21B086A8BCC8C40C4' -or
        $catalogInfo.row_counts.routines -ne 813 -or
        $catalogInfo.searchable_routines -ne 814 -or
        $catalogInfo.signature_only_routines -ne 1 -or
        $catalogInfo.row_counts.signatures -ne 1184 -or
        $catalogInfo.row_counts.parameters -ne 7524) {
        throw 'The current packaged EES_Tool_Metadata.json catalog was not loaded correctly.'
    }
    $catalogSearch = & (Join-Path $config.install_directory 'Search-EES-Library.ps1') -Query 'compressor constant efficiency' -Limit 3 -Detail Compact -EesPath $config.ees_path | ConvertFrom-Json
    $compressor = @($catalogSearch.results | Where-Object { $_.routine_id -eq 'Compressor2_CL' }) | Select-Object -First 1
    if (-not $compressor -or $compressor.required_load_directive -ne '$Load Component Library') {
        throw 'The catalog did not return the expected Compressor2_CL library-load instruction.'
    }
    $expectedCompactFields = @('routine_id', 'routine_type', 'short_description', 'primary_syntax', 'required_load_directive', 'installed_metadata_match', 'deprecated', 'replacement_routine_id')
    $actualCompactFields = @($compressor.PSObject.Properties.Name)
    if (@(Compare-Object -ReferenceObject $expectedCompactFields -DifferenceObject $actualCompactFields).Count -ne 0) {
        throw 'Compact catalog search returned an unexpected field set.'
    }
    $whitespaceQueryRejected = $false
    try {
        & (Join-Path $config.install_directory 'Search-EES-Library.ps1') -Query '   ' -Limit 3 -Detail Compact -EesPath $config.ees_path | Out-Null
    }
    catch { $whitespaceQueryRejected = $true }
    if (-not $whitespaceQueryRejected) {
        throw 'Catalog search accepted a whitespace-only query.'
    }
    $compactRoutineDetail = & (Join-Path $config.install_directory 'Get-EES-Routine.ps1') -RoutineID 'Compressor2_CL' -Detail Compact -EesPath $config.ees_path | ConvertFrom-Json
    $actualCompactRoutineFields = @($compactRoutineDetail.routine.PSObject.Properties.Name)
    if (@(Compare-Object -ReferenceObject $expectedCompactFields -DifferenceObject $actualCompactRoutineFields).Count -ne 0) {
        throw 'Compact routine detail returned an unexpected field set.'
    }
    $routineDetail = & (Join-Path $config.install_directory 'Get-EES-Routine.ps1') -RoutineID 'Compressor2_CL' -Detail Full -EesPath $config.ees_path | ConvertFrom-Json
    if ($routineDetail.catalog_sha256 -ne $catalogInfo.catalog_sha256 -or
        @($routineDetail.routine.signatures).Count -ne 2 -or
        @($routineDetail.routine.signatures[0].parameters).Count -ne 9) {
        throw 'Full routine detail did not return the expected current Compressor2_CL signatures and parameters.'
    }
    $notchDetail = & (Join-Path $config.install_directory 'Get-EES-Routine.ps1') -RoutineID 'Notch_Sensitivity' -Detail Full -EesPath $config.ees_path | ConvertFrom-Json
    if (@($notchDetail.routine.signatures).Count -ne 3 -or
        @($notchDetail.routine.signatures | Where-Object { @($_.parameters).Count -ne 5 }).Count -ne 0) {
        throw 'Shared Notch_Sensitivity parameters were not resolved for all three signatures.'
    }
    $gearDetail = & (Join-Path $config.install_directory 'Get-EES-Routine.ps1') -RoutineID 'gear_Lewis_factor' -Detail Full -EesPath $config.ees_path | ConvertFrom-Json
    if (@($gearDetail.routine.signatures).Count -ne 2 -or
        @($gearDetail.routine.signatures | Where-Object { @($_.parameters).Count -ne 3 }).Count -ne 0) {
        throw 'Shared gear_Lewis_factor parameters were not resolved for both signatures.'
    }
    $impingingDetail = & (Join-Path $config.install_directory 'Get-EES-Routine.ps1') -RoutineID 'Impinging_Jet_SRN_ND' -Detail Full -EesPath $config.ees_path | ConvertFrom-Json
    if (@($impingingDetail.routine.categories | Where-Object { $_.category_id -in @('Imp. Jets Nondimensional Char.', 'Impinging Jets') }).Count -ne 2) {
        throw 'Canonical routine-ID normalization did not preserve both Impinging_Jet_SRN_ND categories.'
    }
    $ammoniaDetail = & (Join-Path $config.install_directory 'Get-EES-Routine.ps1') -RoutineID "FoulingFactor('Ammonia liquid oil bearing')" -Detail Full -EesPath $config.ees_path | ConvertFrom-Json
    if ($ammoniaDetail.routine.metadata_record_type -ne 'signature_only' -or
        @($ammoniaDetail.routine.signatures).Count -ne 1 -or
        @($ammoniaDetail.routine.signatures[0].parameters).Count -ne 1) {
        throw 'The signature-only ammonia fouling-factor entry was not preserved as a searchable routine view.'
    }

    $libraryAutoloadResult = $null
    if ($config.ees_architecture -eq '32-bit') {
        $libraryProgram = Join-Path $config.workspace_root 'tests\ai_autoload_all_libraries_smoke.txt'
        $libraryAutoloadResult = Join-Path $resultDirectory 'ai_library_autoload_test.txt'
        $libraryOutput = & $hostExe -NoProfile -ExecutionPolicy Bypass -File $launcher `
            -WorkspaceRoot $config.workspace_root `
            -ProgramPath $libraryProgram `
            -OutputPath $libraryAutoloadResult `
            -EesPath $config.ees_path `
            -TimeoutSeconds 90 `
            -Force 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "The /AI all-library test returned exit code $LASTEXITCODE. $($libraryOutput -join [Environment]::NewLine)"
        }
        $libraryText = Get-Content -LiteralPath $libraryAutoloadResult -Raw
        $expectedPatterns = @(
            '(?m)^W_dot\s+7\.44977990E\+00',
            '(?m)^A_section\s+2\.00000000E-02',
            '(?m)^cp_NASA\s+3\.06801442E\+01',
            '(?m)^k_mercury\s+9\.18886755E\+00',
            '(?m)^f_blackbody\s+9\.13832954E-01'
        )
        foreach ($pattern in $expectedPatterns) {
            if ($libraryText -notmatch $pattern) {
                throw "The /AI all-library test did not produce an expected result matching: $pattern"
            }
        }

        $profileBytesAfter = [System.IO.File]::ReadAllBytes($config.profile_path)
        $profileAutoloadBitsAfter = ([int]$profileBytesAfter[0x3D] -band 0x1F)
        if ($profileAutoloadBitsAfter -ne $profileAutoloadBitsBefore) {
            throw 'The /AI launch unexpectedly changed the persistent EES.PRF library-autoload bits.'
        }
        $profileRoot = Split-Path -Parent $config.profile_path
        if ((Test-Path -LiteralPath (Join-Path $profileRoot 'EES.PRF.ees-codex-backup')) -or
            (Test-Path -LiteralPath (Join-Path $profileRoot 'EES.PRF.ees-codex-backup.json'))) {
            throw 'An obsolete EES profile backup or recovery record exists after the installation tests.'
        }
    }

    [ordered]@{
        status = 'success'
        message = 'The launcher solved the EES smoke test and verified /AI autoload for Component, Mechanical Design, NASA, Incompressible, and Heat Transfer routines without changing the persistent autoload setting.'
        ees_path = $config.ees_path
        workspace_root = $config.workspace_root
        result_path = $output
        launcher_version = $config.version
        coordinated_plugin_version = $config.coordinated_plugin_version
        launcher_api_level = $config.launcher_api_level
        compact_result_extraction = $true
        catalog_name = $catalogInfo.catalog_name
        catalog_schema_version = $catalogInfo.catalog_schema_version
        catalog_sha256 = $catalogInfo.catalog_sha256
        catalog_routines = $catalogInfo.row_counts.routines
        searchable_routines = $catalogInfo.searchable_routines
        library_autoload_result = $libraryAutoloadResult
        profile_autoload_bits_unchanged = if ($config.ees_architecture -eq '32-bit') { $true } else { $null }
    } | ConvertTo-Json
    exit 0
}
catch {
    [ordered]@{ status = 'error'; message = $_.Exception.Message } | ConvertTo-Json
    exit 1
}
