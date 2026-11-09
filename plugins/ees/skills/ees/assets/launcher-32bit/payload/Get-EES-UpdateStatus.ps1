#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,

    [string]$InstalledLauncherVersion,

    [string]$InstalledSkillVersion,

    [string]$ManifestUrl,

    [string]$ManifestPath,

    [string]$CachePath,

    [ValidateRange(0, 720)]
    [int]$CacheHours = 24,

    [ValidateRange(1, 30)]
    [int]$TimeoutSeconds = 3,

    [switch]$ForceRefresh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$defaultManifestUrl = 'https://raw.githubusercontent.com/EES-Community/ees-codex/main/update/latest.json'
$defaultUpdateUrl = 'https://github.com/EES-Community/ees-codex'

function Get-OptionalProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $null
}

function ConvertTo-EesCodexVersion {
    param([Parameter(Mandatory = $true)][string]$Version)

    $match = [regex]::Match(
        $Version.Trim(),
        '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'
    )
    if (-not $match.Success) {
        throw "Unsupported release version: $Version"
    }

    [pscustomobject]@{
        text = $Version.Trim()
        numbers = @(
            [int64]$match.Groups[1].Value,
            [int64]$match.Groups[2].Value,
            [int64]$match.Groups[3].Value
        )
        prerelease = if ($match.Groups[4].Success) { @($match.Groups[4].Value.Split('.')) } else { @() }
    }
}

function Compare-EesCodexVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    $leftVersion = ConvertTo-EesCodexVersion -Version $Left
    $rightVersion = ConvertTo-EesCodexVersion -Version $Right
    for ($index = 0; $index -lt 3; $index++) {
        if ($leftVersion.numbers[$index] -lt $rightVersion.numbers[$index]) { return -1 }
        if ($leftVersion.numbers[$index] -gt $rightVersion.numbers[$index]) { return 1 }
    }

    $leftPrerelease = @($leftVersion.prerelease)
    $rightPrerelease = @($rightVersion.prerelease)
    if ($leftPrerelease.Count -eq 0 -and $rightPrerelease.Count -eq 0) { return 0 }
    if ($leftPrerelease.Count -eq 0) { return 1 }
    if ($rightPrerelease.Count -eq 0) { return -1 }

    $identifierCount = [Math]::Max($leftPrerelease.Count, $rightPrerelease.Count)
    for ($index = 0; $index -lt $identifierCount; $index++) {
        if ($index -ge $leftPrerelease.Count) { return -1 }
        if ($index -ge $rightPrerelease.Count) { return 1 }
        $leftIdentifier = [string]$leftPrerelease[$index]
        $rightIdentifier = [string]$rightPrerelease[$index]
        $leftNumeric = $leftIdentifier -match '^[0-9]+$'
        $rightNumeric = $rightIdentifier -match '^[0-9]+$'
        if ($leftNumeric -and $rightNumeric) {
            $leftNumber = [int64]$leftIdentifier
            $rightNumber = [int64]$rightIdentifier
            if ($leftNumber -lt $rightNumber) { return -1 }
            if ($leftNumber -gt $rightNumber) { return 1 }
            continue
        }
        if ($leftNumeric -and -not $rightNumeric) { return -1 }
        if (-not $leftNumeric -and $rightNumeric) { return 1 }
        $comparison = [StringComparer]::Ordinal.Compare($leftIdentifier, $rightIdentifier)
        if ($comparison -lt 0) { return -1 }
        if ($comparison -gt 0) { return 1 }
    }
    return 0
}

function ConvertTo-ValidatedManifest {
    param([Parameter(Mandatory = $true)][object]$Manifest)

    if ([int](Get-OptionalProperty -Object $Manifest -Name 'schema_version') -ne 1) {
        throw 'The update manifest has an unsupported schema version.'
    }
    $launcherVersion = [string](Get-OptionalProperty -Object $Manifest -Name 'launcher_version')
    $skillVersion = [string](Get-OptionalProperty -Object $Manifest -Name 'skill_version')
    [void](ConvertTo-EesCodexVersion -Version $launcherVersion)
    [void](ConvertTo-EesCodexVersion -Version $skillVersion)

    $updateUrl = [string](Get-OptionalProperty -Object $Manifest -Name 'update_url')
    if ([string]::IsNullOrWhiteSpace($updateUrl)) { $updateUrl = $defaultUpdateUrl }
    $updateUri = $null
    $repositoryPath = $null
    if ([Uri]::TryCreate($updateUrl, [UriKind]::Absolute, [ref]$updateUri)) {
        $repositoryPath = $updateUri.AbsolutePath.TrimEnd('/')
    }
    if (-not [Uri]::TryCreate($updateUrl, [UriKind]::Absolute, [ref]$updateUri) -or
        $updateUri.Scheme -ne 'https' -or
        $updateUri.Host -ne 'github.com' -or
        ($repositoryPath -ne '/EES-Community/ees-codex' -and
            -not $repositoryPath.StartsWith('/EES-Community/ees-codex/', [StringComparison]::OrdinalIgnoreCase))) {
        throw 'The update manifest contains an untrusted update URL.'
    }

    [pscustomobject][ordered]@{
        schema_version = 1
        launcher_version = $launcherVersion
        skill_version = $skillVersion
        update_url = $updateUri.AbsoluteUri
    }
}

function New-ComponentStatus {
    param(
        [string]$InstalledVersion,
        [Parameter(Mandatory = $true)][string]$LatestVersion
    )

    $available = $null
    $comparison = 'not-installed-or-unknown'
    if (-not [string]::IsNullOrWhiteSpace($InstalledVersion)) {
        try {
            $available = (Compare-EesCodexVersion -Left $InstalledVersion -Right $LatestVersion) -lt 0
            $comparison = if ($available) { 'older' } elseif ((Compare-EesCodexVersion -Left $InstalledVersion -Right $LatestVersion) -eq 0) { 'current' } else { 'newer' }
        }
        catch {
            $comparison = 'invalid-installed-version'
        }
    }

    [pscustomobject][ordered]@{
        installed_version = if ([string]::IsNullOrWhiteSpace($InstalledVersion)) { $null } else { $InstalledVersion }
        latest_version = $LatestVersion
        update_available = $available
        comparison = $comparison
    }
}

function New-UnavailableStatus {
    param(
        [string]$Reason,
        [bool]$Disabled = $false
    )

    [pscustomobject][ordered]@{
        schema_version = 1
        checked = $false
        disabled = $Disabled
        source = 'unavailable'
        checked_utc = $null
        update_available = $false
        message = $null
        update_url = $defaultUpdateUrl
        reason = $Reason
        launcher = [pscustomobject][ordered]@{
            installed_version = if ([string]::IsNullOrWhiteSpace($InstalledLauncherVersion)) { $null } else { $InstalledLauncherVersion }
            latest_version = $null
            update_available = $null
            comparison = 'not-checked'
        }
        skill = [pscustomobject][ordered]@{
            installed_version = if ([string]::IsNullOrWhiteSpace($InstalledSkillVersion)) { $null } else { $InstalledSkillVersion }
            latest_version = $null
            update_available = $null
            comparison = 'not-checked'
        }
    }
}

if ($env:EES_CODEX_DISABLE_UPDATE_CHECK -eq '1') {
    return New-UnavailableStatus -Reason 'disabled-by-environment' -Disabled $true
}

$config = $null
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    try {
        $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath -ErrorAction Stop).Path
        $config = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        return New-UnavailableStatus -Reason 'launcher-config-unavailable'
    }
}

if ([string]::IsNullOrWhiteSpace($InstalledLauncherVersion) -and $null -ne $config) {
    $InstalledLauncherVersion = [string](Get-OptionalProperty -Object $config -Name 'version')
}
if ($null -ne $config -and (Get-OptionalProperty -Object $config -Name 'update_check_enabled') -eq $false) {
    return New-UnavailableStatus -Reason 'disabled-by-configuration' -Disabled $true
}
if (-not $PSBoundParameters.ContainsKey('ManifestUrl') -and $null -ne $config) {
    $ManifestUrl = [string](Get-OptionalProperty -Object $config -Name 'update_manifest_url')
}
if ([string]::IsNullOrWhiteSpace($ManifestUrl)) { $ManifestUrl = $defaultManifestUrl }
if (-not $PSBoundParameters.ContainsKey('CacheHours') -and $null -ne $config) {
    $configuredCacheHours = Get-OptionalProperty -Object $config -Name 'update_check_interval_hours'
    if ($null -ne $configuredCacheHours) {
        try {
            $candidateCacheHours = [int]$configuredCacheHours
            if ($candidateCacheHours -ge 0 -and $candidateCacheHours -le 720) { $CacheHours = $candidateCacheHours }
        }
        catch { }
    }
}
if ([string]::IsNullOrWhiteSpace($CachePath)) {
    $localApplicationData = [Environment]::GetFolderPath('LocalApplicationData')
    if (-not [string]::IsNullOrWhiteSpace($localApplicationData)) {
        $CachePath = Join-Path $localApplicationData 'EES-Codex-Launcher\update-cache-v1.json'
    }
}

$now = [DateTimeOffset]::UtcNow
$manifest = $null
$cachedManifest = $null
$cachedCheckedUtc = $null
if (-not [string]::IsNullOrWhiteSpace($CachePath) -and (Test-Path -LiteralPath $CachePath -PathType Leaf)) {
    try {
        $cache = Get-Content -LiteralPath $CachePath -Raw | ConvertFrom-Json
        $cachedCheckedUtc = [DateTimeOffset]::Parse([string](Get-OptionalProperty -Object $cache -Name 'checked_utc'))
        $cachedManifest = ConvertTo-ValidatedManifest -Manifest (Get-OptionalProperty -Object $cache -Name 'manifest')
        $cacheAgeHours = ($now - $cachedCheckedUtc).TotalHours
        if (-not $ForceRefresh -and $cacheAgeHours -ge 0 -and $cacheAgeHours -le $CacheHours) {
            $manifest = $cachedManifest
            $checkedUtc = $cachedCheckedUtc
            $source = 'cache'
        }
    }
    catch {
        $cachedManifest = $null
        $cachedCheckedUtc = $null
    }
}

if ($null -eq $manifest) {
    try {
        if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
            $rawManifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json
            $source = 'file'
        }
        else {
            $manifestUri = $null
            if (-not [Uri]::TryCreate($ManifestUrl, [UriKind]::Absolute, [ref]$manifestUri) -or
                $manifestUri.Scheme -ne 'https' -or
                $manifestUri.Host -ne 'raw.githubusercontent.com' -or
                -not $manifestUri.AbsolutePath.StartsWith('/EES-Community/ees-codex/', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'The update-manifest URL is not an approved EES-Community GitHub URL.'
            }
            $response = Invoke-WebRequest -Uri $manifestUri.AbsoluteUri -UseBasicParsing -TimeoutSec $TimeoutSeconds -Headers @{ 'User-Agent' = 'EES-Codex-Launcher-Update-Check' }
            $rawManifest = ([string]$response.Content) | ConvertFrom-Json
            $source = 'network'
        }
        $manifest = ConvertTo-ValidatedManifest -Manifest $rawManifest
        $checkedUtc = $now

        if (-not [string]::IsNullOrWhiteSpace($CachePath)) {
            try {
                $cacheDirectory = Split-Path -Parent $CachePath
                if (-not (Test-Path -LiteralPath $cacheDirectory -PathType Container)) {
                    New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
                }
                $cacheEnvelope = [ordered]@{
                    checked_utc = $checkedUtc.ToString('o')
                    manifest = $manifest
                }
                [System.IO.File]::WriteAllText(
                    $CachePath,
                    ($cacheEnvelope | ConvertTo-Json -Depth 5),
                    (New-Object System.Text.UTF8Encoding($false))
                )
            }
            catch {
                # A cache-write failure must never prevent an EES run.
            }
        }
    }
    catch {
        if ($null -ne $cachedManifest) {
            $manifest = $cachedManifest
            $checkedUtc = $cachedCheckedUtc
            $source = 'stale-cache'
        }
        else {
            return New-UnavailableStatus -Reason 'manifest-unavailable'
        }
    }
}

$launcherStatus = New-ComponentStatus -InstalledVersion $InstalledLauncherVersion -LatestVersion $manifest.launcher_version
$skillStatus = New-ComponentStatus -InstalledVersion $InstalledSkillVersion -LatestVersion $manifest.skill_version
$updateAvailable = ($launcherStatus.update_available -eq $true) -or ($skillStatus.update_available -eq $true)
$message = $null
if ($updateAvailable) {
    $updates = New-Object System.Collections.Generic.List[string]
    if ($launcherStatus.update_available -eq $true) {
        $updates.Add("launcher $($launcherStatus.installed_version) to $($launcherStatus.latest_version)")
    }
    if ($skillStatus.update_available -eq $true) {
        $updates.Add("skill $($skillStatus.installed_version) to $($skillStatus.latest_version)")
    }
    $message = "A newer EES Codex release is available ($($updates -join '; ')). You may want to update it from $($manifest.update_url)"
}

[pscustomobject][ordered]@{
    schema_version = 1
    checked = $true
    disabled = $false
    source = $source
    checked_utc = $checkedUtc.ToString('o')
    update_available = [bool]$updateAvailable
    message = $message
    update_url = $manifest.update_url
    reason = $null
    launcher = $launcherStatus
    skill = $skillStatus
}
