#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-StructuredError {
    param([scriptblock]$Action)
    try {
        & $Action | Out-Null
    }
    catch {
        return ($_.Exception.Message | ConvertFrom-Json)
    }
    throw 'Expected the helper call to fail, but it succeeded.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$pluginManifestPath = Join-Path $repositoryRoot 'plugins\ees\.codex-plugin\plugin.json'
$pluginManifest = Get-Content -LiteralPath $pluginManifestPath -Raw | ConvertFrom-Json
$expectedVersion = [string]$pluginManifest.version
Assert-True ($expectedVersion -eq '0.5.1-beta') 'The plugin manifest does not have the expected coordinated release version.'

$editions = @('launcher-32bit', 'launcher-64bit')
$helperHashes = New-Object System.Collections.Generic.List[string]
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
$capabilityResolver = Join-Path $repositoryRoot 'plugins\ees\skills\ees\scripts\Resolve-EES-LauncherCapabilities.ps1'
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ees-codex-release-test-' + [Guid]::NewGuid().ToString('N'))
$resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$resolvedScratchRoot = [System.IO.Path]::GetFullPath($scratchRoot)
Assert-True ($resolvedScratchRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) 'Refusing to use a scratch path outside the system temporary directory.'

try {
    foreach ($edition in $editions) {
        $assetRoot = Join-Path $repositoryRoot ('plugins\ees\skills\ees\assets\' + $edition)
        $manifest = Get-Content -LiteralPath (Join-Path $assetRoot 'manifest.json') -Raw | ConvertFrom-Json
        $versionText = (Get-Content -LiteralPath (Join-Path $assetRoot 'VERSION.txt') -Raw).Trim()
        Assert-True ([string]$manifest.version -eq $expectedVersion) "$edition manifest version is not coordinated with the plugin."
        Assert-True ([string]$manifest.coordinated_plugin_version -eq $expectedVersion) "$edition does not declare the coordinated plugin version."
        Assert-True ($versionText -eq $expectedVersion) "$edition VERSION.txt is not coordinated with the plugin."
        Assert-True ([int]$manifest.launcher_api_level -eq 3) "$edition does not declare launcher API level 3."
        Assert-True ([string]$manifest.ees_message_capture_minimum_ees_version -eq '12.358') "$edition does not declare EES 12.358 as the EES_Msg.txt feature threshold."
        Assert-True ([string]$manifest.ees_message_capture_minimum_file_version -eq '12.3.5.8') "$edition does not declare the corresponding EES_Msg.txt file-version threshold."
        Assert-True (@($manifest.capabilities.catalog_detail_modes) -contains 'Compact') "$edition lacks compact catalog capability."
        Assert-True (@($manifest.capabilities.result_detail_modes) -contains 'Compact') "$edition lacks compact result capability."
        Assert-True (@($manifest.capabilities.result_selectors) -contains 'Pattern') "$edition lacks pattern result selection."
        Assert-True ($manifest.capabilities.ees_message_capture -eq $true) "$edition lacks EES_Msg.txt capture capability."

        $hashManifestPath = Join-Path $assetRoot 'SHA256SUMS.txt'
        $listedPackagePaths = New-Object System.Collections.Generic.List[string]
        foreach ($hashLine in Get-Content -LiteralPath $hashManifestPath) {
            if ([string]::IsNullOrWhiteSpace($hashLine)) { continue }
            $hashMatch = [regex]::Match($hashLine, '^([0-9a-fA-F]{64})  (.+)$')
            Assert-True ($hashMatch.Success) "$edition contains a malformed SHA256SUMS.txt line: $hashLine"
            $relativePath = $hashMatch.Groups[2].Value
            $listedPackagePaths.Add($relativePath)
            $packageFile = Join-Path $assetRoot ($relativePath -replace '/', '\')
            Assert-True (Test-Path -LiteralPath $packageFile -PathType Leaf) "$edition hash manifest references a missing file: $relativePath"
            $actualHash = (Get-FileHash -LiteralPath $packageFile -Algorithm SHA256).Hash
            Assert-True ($actualHash -eq $hashMatch.Groups[1].Value) "$edition hash mismatch: $relativePath"
        }
        $actualPackagePaths = @(Get-ChildItem -LiteralPath $assetRoot -File -Recurse | Where-Object {
            $_.FullName -ne $hashManifestPath
        } | ForEach-Object {
            $_.FullName.Substring($assetRoot.Length + 1).Replace('\', '/')
        } | Sort-Object)
        $coverageDifference = @(Compare-Object -ReferenceObject @($actualPackagePaths) -DifferenceObject @($listedPackagePaths | Sort-Object))
        Assert-True ($coverageDifference.Count -eq 0) "$edition SHA256SUMS.txt does not cover every packaged file exactly once."

        $helperSource = Join-Path $assetRoot 'payload\Get-EES-Result.ps1'
        $helperHashes.Add((Get-FileHash -LiteralPath $helperSource -Algorithm SHA256).Hash)
        $routineHelperSource = Join-Path $assetRoot 'payload\Get-EES-Routine.ps1'
        $routineTokens = $null
        $routineParseErrors = $null
        $routineAst = [System.Management.Automation.Language.Parser]::ParseFile($routineHelperSource, [ref]$routineTokens, [ref]$routineParseErrors)
        Assert-True (@($routineParseErrors).Count -eq 0) "$edition routine helper did not parse."
        $routineExitStatements = @($routineAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.ExitStatementAst]
        }, $true))
        Assert-True ($routineExitStatements.Count -eq 0) "$edition routine helper can terminate its calling PowerShell host."
        $runtimeRoot = Join-Path $scratchRoot $edition
        $workspaceRoot = Join-Path $runtimeRoot 'workspace'
        $resultRoot = Join-Path $workspaceRoot 'results'
        $installRoot = Join-Path $runtimeRoot 'installed'
        New-Item -ItemType Directory -Path $resultRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        Copy-Item -LiteralPath $helperSource -Destination (Join-Path $installRoot 'Get-EES-Result.ps1')
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'water-heating-result.txt') -Destination $resultRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'cycle-result.txt') -Destination $resultRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'malformed-result.txt') -Destination $resultRoot
        $config = [ordered]@{
            version = $expectedVersion
            launcher_api_level = 3
            install_directory = $installRoot
            workspace_root = $workspaceRoot
            ees_message_capture_enabled_at_install = $true
            ees_message_capture_minimum_file_version = '12.3.5.8'
            capabilities = [ordered]@{
                catalog_detail_modes = @('Compact', 'Full')
                result_detail_modes = @('Compact', 'Full')
                result_selectors = @('Variable', 'Pattern')
                ees_message_capture = $true
            }
        }
        [System.IO.File]::WriteAllText(
            (Join-Path $installRoot 'config.json'),
            ($config | ConvertTo-Json),
            (New-Object System.Text.UTF8Encoding($false))
        )

        $helper = Join-Path $installRoot 'Get-EES-Result.ps1'
        $resolvedCapabilities = & $capabilityResolver -ConfigPath (Join-Path $installRoot 'config.json') | ConvertFrom-Json
        Assert-True ($resolvedCapabilities.use_compact_catalog) "$edition ignored its declared compact catalog capability."
        Assert-True ($resolvedCapabilities.use_compact_results) "$edition ignored its declared compact result capability."
        Assert-True ($resolvedCapabilities.use_ees_message_capture) "$edition ignored its declared EES_Msg.txt capture capability."
        Assert-True ($resolvedCapabilities.ees_message_capture_capable) "$edition did not report that its launcher implements EES_Msg.txt capture."
        Assert-True ($resolvedCapabilities.catalog_detection_source -eq 'declared') "$edition did not prefer declared capabilities."

        $config.ees_message_capture_enabled_at_install = $false
        [System.IO.File]::WriteAllText(
            (Join-Path $installRoot 'config.json'),
            ($config | ConvertTo-Json -Depth 5),
            (New-Object System.Text.UTF8Encoding($false))
        )
        $olderEesCapabilities = & $capabilityResolver -ConfigPath (Join-Path $installRoot 'config.json') | ConvertFrom-Json
        Assert-True ($olderEesCapabilities.ees_message_capture_capable) "$edition lost its launcher diagnostic capability when the selected EES version disabled it."
        Assert-True (-not $olderEesCapabilities.use_ees_message_capture) "$edition enabled EES_Msg.txt capture for an unsupported EES version."
        Assert-True (-not $olderEesCapabilities.update_recommended) "$edition recommended a launcher update when only the selected EES version disabled diagnostics."
        $config.ees_message_capture_enabled_at_install = $true
        [System.IO.File]::WriteAllText(
            (Join-Path $installRoot 'config.json'),
            ($config | ConvertTo-Json -Depth 5),
            (New-Object System.Text.UTF8Encoding($false))
        )
        $waterPath = Join-Path $resultRoot 'water-heating-result.txt'
        $water = & $helper -Path $waterPath -Variable 'q_DOT' -Pattern '*_resid' -Detail Compact | ConvertFrom-Json
        Assert-True ($water.status -eq 'success') "$edition compact water result did not succeed."
        Assert-True ($water.result_count -eq 2) "$edition compact water result returned the wrong count."
        $heatTransfer = @($water.results | Where-Object { $_.variable_name -eq 'Q_dot' })[0]
        Assert-True ($heatTransfer.raw_value -eq '1.67267460E+02') "$edition changed the raw water-heating value."
        Assert-True ($heatTransfer.units -eq '[kW]') "$edition changed the water-heating units."

        $cyclePath = Join-Path $resultRoot 'cycle-result.txt'
        $cycleCompactJson = & $helper -Path $cyclePath -Variable 'Wdot_net','eta_th','TIT_margin' -Pattern '*_resid' -Detail Compact
        $cycleCompact = $cycleCompactJson | ConvertFrom-Json
        Assert-True ($cycleCompact.status -eq 'success') "$edition compact cycle result did not succeed."
        Assert-True (@($cycleCompact.results | Where-Object { $_.variable_name -eq 'cycle_energy_resid' }).Count -eq 1) "$edition wildcard selection omitted a required cycle residual."
        $cycleFull = & $helper -Path $cyclePath -Detail Full | ConvertFrom-Json
        Assert-True ($cycleFull.result_count -ge 80) "$edition full cycle result did not retain the representative export."
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$cycleFull.file_sha256)) "$edition full result omitted file diagnostics."
        $fullCharacters = (Get-Content -LiteralPath $cyclePath -Raw).Length
        $reduction = 1.0 - ([double]$cycleCompactJson.Length / [double]$fullCharacters)
        Assert-True ($reduction -ge 0.60) "$edition compact result reduction was below 60 percent: $([math]::Round($reduction * 100, 1)) percent."

        $missing = Get-StructuredError { & $helper -Path $waterPath -Variable 'not_exported' -Detail Compact }
        Assert-True ($missing.code -eq 'selection_incomplete') "$edition missing-variable failure was not explicit."
        Assert-True (@($missing.missing_variables) -contains 'not_exported') "$edition missing-variable payload omitted the requested name."

        $malformed = Get-StructuredError { & $helper -Path (Join-Path $resultRoot 'malformed-result.txt') -Variable 'Q_dot' -Detail Compact }
        Assert-True ($malformed.code -eq 'result_parse_failed') "$edition malformed input did not fail parsing."
        Assert-True (@($malformed.parse_warnings).Count -eq 2) "$edition malformed input did not report both parse warnings."
        Assert-True (@($malformed.duplicate_names).Count -eq 1) "$edition duplicate variable was not reported."

        $outsidePath = Join-Path $runtimeRoot 'outside.txt'
        [System.IO.File]::WriteAllText($outsidePath, "x`t1.00000000E+00", (New-Object System.Text.UTF8Encoding($false)))
        $outside = Get-StructuredError { & $helper -Path $outsidePath -Variable 'x' -Detail Compact }
        Assert-True ($outside.code -eq 'outside_workspace') "$edition read a result outside the configured workspace."

        [pscustomobject]@{
            edition = $edition
            full_characters = $fullCharacters
            compact_characters = $cycleCompactJson.Length
            reduction_percent = [math]::Round($reduction * 100, 1)
        }
    }

    Assert-True (@($helperHashes | Select-Object -Unique).Count -eq 1) 'The 32-bit and 64-bit result helpers are not identical.'

    foreach ($legacyVersion in @('0.4.0-beta', '0.4.1-beta')) {
        $legacyRoot = Join-Path $scratchRoot ('legacy-' + $legacyVersion)
        New-Item -ItemType Directory -Path $legacyRoot -Force | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $legacyRoot 'Search-EES-Library.ps1'),
            "param([string]`$Query,[int]`$Limit)",
            (New-Object System.Text.UTF8Encoding($false))
        )
        [System.IO.File]::WriteAllText(
            (Join-Path $legacyRoot 'Get-EES-Routine.ps1'),
            "param([string]`$RoutineID)",
            (New-Object System.Text.UTF8Encoding($false))
        )
        $legacyConfig = [ordered]@{
            version = $legacyVersion
            install_directory = $legacyRoot
            capabilities = if ($legacyVersion -eq '0.4.1-beta') {
                [ordered]@{ catalog_detail_modes = @('Unexpected'); result_detail_modes = @('Unexpected') }
            }
            else { $null }
        }
        $legacyConfigPath = Join-Path $legacyRoot 'config.json'
        [System.IO.File]::WriteAllText($legacyConfigPath, ($legacyConfig | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
        $legacy = & $capabilityResolver -ConfigPath $legacyConfigPath | ConvertFrom-Json
        Assert-True (-not $legacy.use_compact_catalog) "$legacyVersion incorrectly enabled compact catalog mode."
        Assert-True (-not $legacy.use_compact_results) "$legacyVersion incorrectly enabled compact result mode."
        Assert-True ($legacy.use_legacy_catalog_fallback) "$legacyVersion did not select the controlled catalog fallback."
        Assert-True ($legacy.use_raw_result_fallback) "$legacyVersion did not select raw-result fallback."
        Assert-True ($legacy.update_recommended) "$legacyVersion did not recommend the coordinated update."
    }

    $inspectedRoot = Join-Path $scratchRoot 'inspected-0.4.2'
    New-Item -ItemType Directory -Path $inspectedRoot -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $inspectedRoot 'Search-EES-Library.ps1'), "param([string]`$Query,[int]`$Limit,[string]`$Detail)", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $inspectedRoot 'Get-EES-Routine.ps1'), "param([string]`$RoutineID,[string]`$Detail)", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $inspectedRoot 'Get-EES-Result.ps1'), "param([string]`$Path,[string[]]`$Variable,[string[]]`$Pattern,[string]`$Detail)", (New-Object System.Text.UTF8Encoding($false)))
    $inspectedConfigPath = Join-Path $inspectedRoot 'config.json'
    [System.IO.File]::WriteAllText($inspectedConfigPath, ([ordered]@{ version = '0.4.2-beta'; install_directory = $inspectedRoot } | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
    $inspected = & $capabilityResolver -ConfigPath $inspectedConfigPath | ConvertFrom-Json
    Assert-True ($inspected.use_compact_catalog) 'A pre-declaration launcher with compact parameters was not detected.'
    Assert-True ($inspected.use_compact_results) 'A pre-declaration launcher with the result helper was not detected.'
    Assert-True ($inspected.catalog_detection_source -eq 'inspected') 'Parameter detection did not report its source.'
    Assert-True ($inspected.update_recommended) 'A launcher without declared EES_Msg.txt capture did not recommend an update.'
}
finally {
    if (Test-Path -LiteralPath $resolvedScratchRoot -PathType Container) {
        $verifiedScratch = [System.IO.Path]::GetFullPath($resolvedScratchRoot)
        if ($verifiedScratch.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $verifiedScratch -Recurse -Force
        }
    }
}

[pscustomobject]@{
    status = 'success'
    release_version = $expectedVersion
    editions_tested = $editions.Count
    launcher_api_level = 3
}
