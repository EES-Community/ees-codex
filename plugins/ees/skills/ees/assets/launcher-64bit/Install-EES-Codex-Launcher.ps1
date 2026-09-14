#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$InstallDirectory,
    [string]$WorkspaceDirectory,
    [string]$EesPath,
    [switch]$SkipTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-EesInstallation {
    param(
        [string]$RequestedPath,
        [ValidateSet('Any', '32-bit', '64-bit')]
        [string]$RequiredArchitecture = 'Any'
    )

    $candidates = if ($RequestedPath) {
        @($RequestedPath)
    }
    elseif ($RequiredArchitecture -eq '32-bit') {
        @('C:\EES32\ees.exe')
    }
    elseif ($RequiredArchitecture -eq '64-bit') {
        @('C:\EES64\ees64.exe')
    }
    else {
        @('C:\EES64\ees64.exe', 'C:\EES32\ees.exe')
    }

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $leaf = [System.IO.Path]::GetFileName($resolved)
        if ($leaf -notin @('ees64.exe', 'ees.exe')) {
            continue
        }
        $root = Split-Path -Parent $resolved
        $architecture = if ($leaf -eq 'ees64.exe') { '64-bit' } else { '32-bit' }
        if ($RequiredArchitecture -ne 'Any' -and $architecture -ne $RequiredArchitecture) {
            if ($RequestedPath) {
                throw "This package requires $RequiredArchitecture EES, but the requested executable is $architecture EES: $resolved"
            }
            continue
        }
        $userlibName = if ($architecture -eq '64-bit') { 'Userlib64' } else { 'Userlib' }
        return [pscustomobject]@{
            EesPath = $resolved
            Architecture = $architecture
            UserlibPath = Join-Path $root $userlibName
            MetadataPath = Join-Path $root 'EES_Tool_Metadata.json'
            ProfilePath = Join-Path $root $(if ($architecture -eq '64-bit') { 'EES.PRF64' } else { 'EES.PRF' })
            Version = (Get-Item -LiteralPath $resolved).VersionInfo.FileVersion
        }
    }

    if ($RequestedPath) {
        throw "EES was not found at the requested path: $RequestedPath"
    }
    if ($RequiredArchitecture -eq '32-bit') {
        throw '32-bit EES was not found at C:\EES32\ees.exe. Install 32-bit EES, or rerun with -EesPath and the complete path to ees.exe.'
    }
    if ($RequiredArchitecture -eq '64-bit') {
        throw '64-bit EES was not found at C:\EES64\ees64.exe. Install 64-bit EES, or rerun with -EesPath and the complete path to ees64.exe.'
    }
    throw 'EES was not found at C:\EES64\ees64.exe or C:\EES32\ees.exe. Install EES, or rerun with -EesPath and its complete path.'
}

function Copy-TemplateWithoutOverwrite {
    param([string]$Source, [string]$Destination)

    foreach ($directory in Get-ChildItem -LiteralPath $Source -Directory -Recurse) {
        $relative = $directory.FullName.Substring($Source.Length).TrimStart('\')
        $target = Join-Path $Destination $relative
        if (-not (Test-Path -LiteralPath $target -PathType Container)) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
        }
    }
    foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse) {
        $relative = $file.FullName.Substring($Source.Length).TrimStart('\')
        $target = Join-Path $Destination $relative
        if (-not (Test-Path -LiteralPath $target)) {
            Copy-Item -LiteralPath $file.FullName -Destination $target
        }
    }
}

function Read-DirectoryChoice {
    param(
        [string]$Label,
        [string]$DefaultPath
    )

    while ($true) {
        $entered = Read-Host "$Label [$DefaultPath]"
        if ([string]::IsNullOrWhiteSpace($entered)) {
            return $DefaultPath
        }
        $trimmed = [Environment]::ExpandEnvironmentVariables($entered.Trim().Trim('"'))
        if ([System.IO.Path]::IsPathRooted($trimmed)) {
            return $trimmed
        }
        Write-Host 'Please enter a complete path beginning with a drive letter, such as C:\Engineering\EES-Workspace, or press Enter to accept the default.' -ForegroundColor Yellow
    }
}

try {
    $packageRoot = $PSScriptRoot
    $payload = Join-Path $packageRoot 'payload'
    $workspaceTemplate = Join-Path $packageRoot 'workspace-template'
    $versionFile = Join-Path $packageRoot 'VERSION.txt'
    if (-not (Test-Path -LiteralPath (Join-Path $payload 'Run-EES.ps1') -PathType Leaf)) {
        throw 'The package payload is incomplete. Extract the entire ZIP before running Install.cmd.'
    }

    $manifestPath = Join-Path $packageRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'The package manifest is missing. Extract the entire ZIP before running Install.cmd.'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $requiredArchitecture = if ($manifest.PSObject.Properties.Name -contains 'required_ees_architecture') {
        [string]$manifest.required_ees_architecture
    }
    else { 'Any' }
    if ($requiredArchitecture -notin @('Any', '32-bit', '64-bit')) {
        throw "The package manifest contains an unsupported EES architecture: $requiredArchitecture"
    }
    $installFolderName = if ($manifest.PSObject.Properties.Name -contains 'install_folder_name') {
        [string]$manifest.install_folder_name
    }
    else { 'EES-Codex-Launcher' }
    $workspaceFolderName = if ($manifest.PSObject.Properties.Name -contains 'workspace_folder_name') {
        [string]$manifest.workspace_folder_name
    }
    else { 'EES-Codex-Workspace' }
    $workspaceParent = if ($manifest.PSObject.Properties.Name -contains 'workspace_parent') {
        [string]$manifest.workspace_parent
    }
    else { 'Documents' }
    if ($workspaceParent -notin @('Documents', 'UserProfile')) {
        throw "The package manifest contains an unsupported workspace parent: $workspaceParent"
    }
    $defaultInstallDirectory = Join-Path $env:LOCALAPPDATA $installFolderName
    $defaultWorkspaceParent = if ($workspaceParent -eq 'UserProfile') {
        $env:USERPROFILE
    }
    else {
        [Environment]::GetFolderPath('MyDocuments')
    }
    $defaultWorkspaceDirectory = Join-Path $defaultWorkspaceParent $workspaceFolderName
    if (-not $InstallDirectory -or -not $WorkspaceDirectory) {
        Write-Host ''
        Write-Host 'Choose where the launcher and your writable EES workspace should be stored.' -ForegroundColor Cyan
        Write-Host 'Press Enter at either prompt to accept the path shown in brackets.'
    }
    if (-not $InstallDirectory) {
        $InstallDirectory = Read-DirectoryChoice -Label 'Launcher install directory' -DefaultPath $defaultInstallDirectory
    }
    if (-not $WorkspaceDirectory) {
        $WorkspaceDirectory = Read-DirectoryChoice -Label 'Models and results workspace directory' -DefaultPath $defaultWorkspaceDirectory
    }
    $InstallDirectory = [Environment]::ExpandEnvironmentVariables($InstallDirectory.Trim().Trim('"'))
    $WorkspaceDirectory = [Environment]::ExpandEnvironmentVariables($WorkspaceDirectory.Trim().Trim('"'))
    if (-not [System.IO.Path]::IsPathRooted($InstallDirectory)) {
        throw "InstallDirectory must be a complete path beginning with a drive letter: $InstallDirectory"
    }
    if (-not [System.IO.Path]::IsPathRooted($WorkspaceDirectory)) {
        throw "WorkspaceDirectory must be a complete path beginning with a drive letter: $WorkspaceDirectory"
    }

    $installation = Resolve-EesInstallation -RequestedPath $EesPath -RequiredArchitecture $requiredArchitecture
    $resolvedInstall = [System.IO.Path]::GetFullPath($InstallDirectory)
    $resolvedWorkspace = [System.IO.Path]::GetFullPath($WorkspaceDirectory)
    if ($resolvedInstall.Equals($resolvedWorkspace, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The protected launcher directory and writable workspace must be different directories.'
    }

    New-Item -ItemType Directory -Path $resolvedInstall -Force | Out-Null
    New-Item -ItemType Directory -Path $resolvedWorkspace -Force | Out-Null
    Copy-Item -Path (Join-Path $payload '*') -Destination $resolvedInstall -Recurse -Force
    $obsoleteProfileHelper = Join-Path $resolvedInstall 'Restore-EES-Profile.ps1'
    if (Test-Path -LiteralPath $obsoleteProfileHelper -PathType Leaf) {
        Remove-Item -LiteralPath $obsoleteProfileHelper -Force
    }
    Copy-TemplateWithoutOverwrite -Source $workspaceTemplate -Destination $resolvedWorkspace

    $version = if (Test-Path -LiteralPath $versionFile) { (Get-Content -LiteralPath $versionFile -Raw).Trim() } else { 'development' }
    $config = [ordered]@{
        product = 'EES-Codex-Launcher'
        version = $version
        install_directory = $resolvedInstall
        workspace_root = $resolvedWorkspace
        ees_path = $installation.EesPath
        ees_architecture = $installation.Architecture
        required_architecture = $requiredArchitecture
        ees_version = $installation.Version
        userlib_path = $installation.UserlibPath
        metadata_path = $installation.MetadataPath
        profile_path = $installation.ProfilePath
        catalog_path = Join-Path $resolvedInstall 'catalog\engineering-tool-dialog-catalog.json'
        catalog_version = 'Database22'
        installed_utc = [DateTime]::UtcNow.ToString('o')
    }
    $configJson = $config | ConvertTo-Json
    [System.IO.File]::WriteAllText((Join-Path $resolvedInstall 'config.json'), $configJson, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $resolvedWorkspace 'launcher-config.json'), $configJson, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $resolvedWorkspace '.ees-codex-workspace'), 'EES-Codex-Launcher workspace', (New-Object System.Text.UTF8Encoding($false)))

    Write-Host ''
    Write-Host 'EES Codex Launcher installed successfully.' -ForegroundColor Green
    Write-Host "Launcher:  $resolvedInstall"
    Write-Host "Workspace: $resolvedWorkspace"
    Write-Host "EES:       $($installation.EesPath) ($($installation.Architecture), version $($installation.Version))"
    Write-Host 'Catalog:   Engineering Tool Dialog Database22'

    if (-not $SkipTest) {
        Write-Host ''
        Write-Host 'Running the installation smoke test...'
        $hostExe = if (Test-Path -LiteralPath (Join-Path $PSHOME 'powershell.exe')) {
            Join-Path $PSHOME 'powershell.exe'
        }
        else { Join-Path $PSHOME 'pwsh.exe' }
        $testScript = Join-Path $resolvedInstall 'Test-Installation.ps1'
        $testConfig = Join-Path $resolvedInstall 'config.json'
        $testOutput = & $hostExe -NoProfile -ExecutionPolicy Bypass -File $testScript -ConfigPath $testConfig 2>&1
        $testExitCode = $LASTEXITCODE
        Write-Host ($testOutput -join [Environment]::NewLine)
        if ($testExitCode -ne 0) {
            throw 'The files were installed, but the EES smoke test failed. See the diagnostic output above.'
        }
    }

    Write-Host ''
    Write-Host 'Open this workspace in Codex:' -ForegroundColor Cyan
    Write-Host "  $resolvedWorkspace" -ForegroundColor White
    Write-Host 'In Codex, choose Open folder (or Add project), paste that exact path into the folder picker, and select the folder.'
    Write-Host 'Then continue with START-HERE.md from the extracted package.'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
