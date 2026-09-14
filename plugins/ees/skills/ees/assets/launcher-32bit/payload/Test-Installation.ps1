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
    $catalogSearch = & (Join-Path $config.install_directory 'Search-EES-Library.ps1') -Query 'compressor constant efficiency' -Limit 10 -EesPath $config.ees_path | ConvertFrom-Json
    if ($catalogSearch.packaged_catalog_version -ne 'Database22' -or $catalogSearch.combined_catalog_routine_count -lt 813) {
        throw 'The Engineering Tool Dialog Database22 catalog was not loaded correctly.'
    }
    $compressor = @($catalogSearch.results | Where-Object { $_.routine_id -eq 'Compressor2_CL' }) | Select-Object -First 1
    if (-not $compressor -or $compressor.required_load_directive -ne '$Load Component Library') {
        throw 'The catalog did not return the expected Compressor2_CL library-load instruction.'
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
        catalog_version = $catalogSearch.packaged_catalog_version
        combined_catalog_routines = $catalogSearch.combined_catalog_routine_count
        library_autoload_result = $libraryAutoloadResult
        profile_autoload_bits_unchanged = if ($config.ees_architecture -eq '32-bit') { $true } else { $null }
    } | ConvertTo-Json
    exit 0
}
catch {
    [ordered]@{ status = 'error'; message = $_.Exception.Message } | ConvertTo-Json
    exit 1
}
