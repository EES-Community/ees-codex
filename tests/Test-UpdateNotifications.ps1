#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$pluginManifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'plugins\ees\.codex-plugin\plugin.json') -Raw | ConvertFrom-Json
$expectedVersion = [string]$pluginManifest.version
$skillRoot = Join-Path $repositoryRoot 'plugins\ees\skills\ees'
$skillVersion = (Get-Content -LiteralPath (Join-Path $skillRoot 'VERSION.txt') -Raw).Trim()
$releaseManifestPath = Join-Path $repositoryRoot 'update\latest.json'
$releaseManifest = Get-Content -LiteralPath $releaseManifestPath -Raw | ConvertFrom-Json
$skillHelper = Join-Path $skillRoot 'scripts\Get-EES-UpdateStatus.ps1'
$skillCheck = Join-Path $skillRoot 'scripts\Check-EES-Updates.ps1'
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ees-codex-update-test-' + [Guid]::NewGuid().ToString('N'))
$resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$resolvedScratchRoot = [System.IO.Path]::GetFullPath($scratchRoot)
Assert-True ($resolvedScratchRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) 'Refusing to use an update-test path outside the system temporary directory.'

try {
    New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
    Assert-True ($skillVersion -eq $expectedVersion) 'The skill VERSION.txt is not coordinated with the plugin manifest.'
    Assert-True ([string]$releaseManifest.launcher_version -eq $expectedVersion) 'The release manifest launcher version is not coordinated.'
    Assert-True ([string]$releaseManifest.skill_version -eq $expectedVersion) 'The release manifest skill version is not coordinated.'
    Assert-True ([string]$releaseManifest.update_url -eq 'https://github.com/EES-Community/ees-codex') 'The release manifest update URL is unexpected.'

    $helperPaths = @(
        $skillHelper,
        (Join-Path $skillRoot 'assets\launcher-32bit\payload\Get-EES-UpdateStatus.ps1'),
        (Join-Path $skillRoot 'assets\launcher-64bit\payload\Get-EES-UpdateStatus.ps1')
    )
    $normalizedHelperText = @($helperPaths | ForEach-Object {
        Assert-True (Test-Path -LiteralPath $_ -PathType Leaf) "Update helper is missing: $_"
        (Get-Content -LiteralPath $_ -Raw).Replace("`r`n", "`n")
    })
    Assert-True ($normalizedHelperText[0] -ceq $normalizedHelperText[1] -and
        $normalizedHelperText[0] -ceq $normalizedHelperText[2]) 'The skill, 32-bit launcher, and 64-bit launcher update helpers are not logically identical.'

    foreach ($scriptPath in @($helperPaths + $skillCheck)) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        Assert-True (@($parseErrors).Count -eq 0) "Update script did not parse: $scriptPath"
    }

    $currentCache = Join-Path $scratchRoot 'current-cache.json'
    $current = & $skillHelper `
        -InstalledLauncherVersion $expectedVersion `
        -InstalledSkillVersion $expectedVersion `
        -ManifestPath $releaseManifestPath `
        -CachePath $currentCache `
        -ForceRefresh
    Assert-True ($current.checked -and -not $current.update_available) 'Current launcher and skill versions incorrectly reported an update.'
    Assert-True ($current.launcher.comparison -eq 'current' -and $current.skill.comparison -eq 'current') 'Current versions were not compared as equal.'

    $older = & $skillHelper `
        -InstalledLauncherVersion '0.6.0-beta' `
        -InstalledSkillVersion '0.6.0-beta' `
        -ManifestPath $releaseManifestPath `
        -CachePath (Join-Path $scratchRoot 'older-cache.json') `
        -ForceRefresh
    Assert-True ($older.update_available -and $older.launcher.update_available -and $older.skill.update_available) 'Older coordinated versions did not report an update.'
    Assert-True ([string]$older.message -match 'launcher 0\.6\.0-beta to 0\.7\.0-beta') 'The launcher update message is not readable.'
    Assert-True ([string]$older.message -match 'skill 0\.6\.0-beta to 0\.7\.0-beta') 'The skill update message is not readable.'

    $prerelease = & $skillHelper `
        -InstalledLauncherVersion '0.7.0-alpha.2' `
        -InstalledSkillVersion '0.7.0' `
        -ManifestPath $releaseManifestPath `
        -CachePath (Join-Path $scratchRoot 'prerelease-cache.json') `
        -ForceRefresh
    Assert-True ($prerelease.launcher.update_available) 'Semantic prerelease ordering did not identify alpha as older than beta.'
    Assert-True (-not $prerelease.skill.update_available) 'A stable release incorrectly compared as older than the beta release.'

    $cached = & $skillHelper `
        -InstalledLauncherVersion $expectedVersion `
        -InstalledSkillVersion $expectedVersion `
        -ManifestPath (Join-Path $scratchRoot 'does-not-exist.json') `
        -CachePath $currentCache
    Assert-True ($cached.checked -and $cached.source -eq 'cache') 'A fresh successful check was not reused from cache.'

    $badManifestPath = Join-Path $scratchRoot 'bad-manifest.json'
    [System.IO.File]::WriteAllText(
        $badManifestPath,
        '{"schema_version":1,"launcher_version":"not-a-version","skill_version":"0.7.0-beta","update_url":"https://example.com"}',
        (New-Object System.Text.UTF8Encoding($false))
    )
    $invalid = & $skillHelper `
        -InstalledLauncherVersion $expectedVersion `
        -InstalledSkillVersion $expectedVersion `
        -ManifestPath $badManifestPath `
        -CachePath (Join-Path $scratchRoot 'bad-cache.json') `
        -ForceRefresh
    Assert-True (-not $invalid.checked -and -not $invalid.update_available -and $invalid.reason -eq 'manifest-unavailable') 'An invalid or untrusted manifest was not rejected safely.'

    $untrustedManifestPath = Join-Path $scratchRoot 'untrusted-manifest.json'
    [System.IO.File]::WriteAllText(
        $untrustedManifestPath,
        '{"schema_version":1,"launcher_version":"0.7.0-beta","skill_version":"0.7.0-beta","update_url":"https://github.com/EES-Community/ees-codex-untrusted"}',
        (New-Object System.Text.UTF8Encoding($false))
    )
    $untrusted = & $skillHelper `
        -InstalledLauncherVersion $expectedVersion `
        -InstalledSkillVersion $expectedVersion `
        -ManifestPath $untrustedManifestPath `
        -CachePath (Join-Path $scratchRoot 'untrusted-cache.json') `
        -ForceRefresh
    Assert-True (-not $untrusted.checked -and $untrusted.reason -eq 'manifest-unavailable') 'A lookalike GitHub repository URL was not rejected.'

    $configPath = Join-Path $scratchRoot 'launcher-config.json'
    [System.IO.File]::WriteAllText(
        $configPath,
        ([ordered]@{
            version = '0.6.0-beta'
            update_check_enabled = $true
            update_manifest_url = 'https://raw.githubusercontent.com/EES-Community/ees-codex/main/update/latest.json'
            update_url = 'https://github.com/EES-Community/ees-codex'
            update_check_interval_hours = 24
        } | ConvertTo-Json),
        (New-Object System.Text.UTF8Encoding($false))
    )
    $wrapperResult = & $skillCheck `
        -ConfigPath $configPath `
        -ManifestPath $releaseManifestPath `
        -CachePath (Join-Path $scratchRoot 'wrapper-cache.json') `
        -ForceRefresh
    Assert-True ($wrapperResult.launcher.update_available -and -not $wrapperResult.skill.update_available) 'The skill wrapper did not compare its own version and the configured launcher version independently.'

    $priorDisableValue = $env:EES_CODEX_DISABLE_UPDATE_CHECK
    try {
        $env:EES_CODEX_DISABLE_UPDATE_CHECK = '1'
        $disabled = & $skillHelper -InstalledLauncherVersion '0.6.0-beta' -InstalledSkillVersion '0.6.0-beta' -ManifestPath $releaseManifestPath
        Assert-True ($disabled.disabled -and -not $disabled.checked -and -not $disabled.update_available) 'The documented update-check opt-out was not honored.'
    }
    finally {
        $env:EES_CODEX_DISABLE_UPDATE_CHECK = $priorDisableValue
    }

    foreach ($edition in @('launcher-32bit', 'launcher-64bit')) {
        $runScript = Join-Path $skillRoot "assets\$edition\payload\Run-EES.ps1"
        $runText = Get-Content -LiteralPath $runScript -Raw
        Assert-True ($runText -match 'Get-EES-UpdateStatus\.ps1') "$edition does not invoke the update helper."
        Assert-True ($runText -match 'update_check\s*=\s*\$updateCheck') "$edition does not return structured update status."
    }

    [pscustomobject]@{
        status = 'success'
        release_version = $expectedVersion
        helpers_compared = $helperPaths.Count
        cache_verified = $true
        opt_out_verified = $true
    }
}
finally {
    if (Test-Path -LiteralPath $resolvedScratchRoot -PathType Container) {
        $verifiedScratch = [System.IO.Path]::GetFullPath($resolvedScratchRoot)
        if ($verifiedScratch.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $verifiedScratch -Recurse -Force
        }
    }
}
