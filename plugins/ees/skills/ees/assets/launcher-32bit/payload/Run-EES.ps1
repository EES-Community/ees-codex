[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProgramPath,

    [string]$OutputPath,

    [string]$ArtifactManifestPath,

    [string]$WorkspaceRoot = $PSScriptRoot,

    [string]$EesPath,

    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 120,

    [switch]$Force,

    [switch]$KeepRunFiles
)

# EES 12.3.3.2 does not reliably process command-line solves when it is
# started by .NET Core's Process implementation. Codex normally runs PowerShell
# 7, so hand the unchanged request to Windows PowerShell 5.1 before launching
# EES. The call operator preserves each path as a separate argument.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
        throw "Windows PowerShell 5.1 was not found: $windowsPowerShell"
    }

    $handoffArguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-ProgramPath', $ProgramPath,
        '-WorkspaceRoot', $WorkspaceRoot,
        '-TimeoutSeconds', [string]$TimeoutSeconds
    )
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $handoffArguments += @('-OutputPath', $OutputPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($ArtifactManifestPath)) {
        $handoffArguments += @('-ArtifactManifestPath', $ArtifactManifestPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($EesPath)) {
        $handoffArguments += @('-EesPath', $EesPath)
    }
    if ($Force) { $handoffArguments += '-Force' }
    if ($KeepRunFiles) { $handoffArguments += '-KeepRunFiles' }

    & $windowsPowerShell @handoffArguments
    exit $LASTEXITCODE
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$programPolicyPath = Join-Path $PSScriptRoot 'EES-ProgramPolicy.ps1'
if (-not (Test-Path -LiteralPath $programPolicyPath -PathType Leaf)) {
    throw "The launcher program-policy helper is missing: $programPolicyPath"
}
. $programPolicyPath

$runDirectory = $null
$process = $null
$runLock = $null
$eesMessagePath = $null
$eesMessageCapture = $null
$eesMessageReset = $false
$eesMessageSupported = $false
$eesMessageMinimumVersion = '12.358'
$eesMessageMinimumFileVersion = [version]'12.3.5.8'
$resolvedOutput = $null
$artifactManifest = $null
$preparedInputs = @()
$preparedOutputs = @()

function Resolve-EesExecutable {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "EES executable was not found: $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    $candidates = @(
        'C:\EES64\ees64.exe',
        'C:\EES32\ees.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw 'EES was not found. Supply -EesPath with the full path to ees64.exe or ees.exe.'
}

function Get-AbsolutePath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Enter-EesRunLock {
    param([string]$ResolvedEesPath)

    if ([System.IO.Path]::GetFileName($ResolvedEesPath) -ne 'ees.exe') { return $null }

    $mutex = New-Object System.Threading.Mutex($false, 'Local\EES_Codex_Launcher_32bit_Run')
    $lockTaken = $false
    try {
        try { $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(30)) }
        catch [System.Threading.AbandonedMutexException] { $lockTaken = $true }
        if (-not $lockTaken) {
            throw 'Another 32-bit EES Codex run is active. Wait for it to finish and try again.'
        }

        $otherEes = @(Get-Process -Name 'ees' -ErrorAction SilentlyContinue)
        if ($otherEes.Count -gt 0) {
            throw "32-bit EES is already running (process ID(s): $($otherEes.Id -join ', ')). Close it before starting a Codex-controlled run."
        }

        return [pscustomobject]@{
            Mutex = $mutex
            LockTaken = $true
        }
    }
    catch {
        if ($lockTaken) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
        throw
    }
}

function Exit-EesRunLock {
    param([object]$State)
    if (-not $State) { return }

    if ($State.LockTaken) { try { $State.Mutex.ReleaseMutex() } catch {} }
    $State.Mutex.Dispose()
}

function Test-PathWithin {
    param(
        [string]$CandidatePath,
        [string]$RootPath
    )

    $candidate = [System.IO.Path]::GetFullPath($CandidatePath).TrimEnd('\')
    $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    return $candidate.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -or
        $candidate.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Reset-EesMessageFile {
    param([string]$ResolvedEesPath)

    $eesDirectory = Split-Path -Parent $ResolvedEesPath
    $messagePath = [System.IO.Path]::GetFullPath((Join-Path $eesDirectory 'EES_Msg.txt'))
    if (Test-Path -LiteralPath $messagePath) {
        if (-not (Test-Path -LiteralPath $messagePath -PathType Leaf)) {
            throw "The EES diagnostic path is not a file: $messagePath"
        }
        try {
            Remove-Item -LiteralPath $messagePath -Force -ErrorAction Stop
        }
        catch {
            throw "The previous EES diagnostic file could not be removed before launch: $messagePath. $($_.Exception.Message)"
        }
    }
    if (Test-Path -LiteralPath $messagePath) {
        throw "The previous EES diagnostic file still exists after deletion: $messagePath"
    }
    return $messagePath
}

function Get-EesFileVersion {
    param([string]$ResolvedEesPath)

    $versionInfo = (Get-Item -LiteralPath $ResolvedEesPath).VersionInfo
    return [version]('{0}.{1}.{2}.{3}' -f $versionInfo.FileMajorPart, $versionInfo.FileMinorPart, $versionInfo.FileBuildPart, $versionInfo.FilePrivatePart)
}

function New-EmptyEesMessageCapture {
    return [pscustomobject]@{
        Present = $false
        Bytes = 0
        Text = $null
        SnapshotPath = $null
        CaptureError = $null
    }
}

function Capture-EesMessageFile {
    param(
        [string]$SourcePath,
        [string]$RunDirectory
    )

    $snapshotPath = Join-Path $RunDirectory 'EES_Msg.txt'
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return [pscustomobject]@{
            Present = $false
            Bytes = 0
            Text = $null
            SnapshotPath = $null
            CaptureError = $null
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
            throw "The EES diagnostic path is not a file: $SourcePath"
        }
        Copy-Item -LiteralPath $SourcePath -Destination $snapshotPath -Force -ErrorAction Stop
        $bytes = (Get-Item -LiteralPath $snapshotPath).Length
        $text = [System.IO.File]::ReadAllText($snapshotPath)
        return [pscustomobject]@{
            Present = ($bytes -gt 0 -and -not [string]::IsNullOrWhiteSpace($text))
            Bytes = $bytes
            Text = $text
            SnapshotPath = $snapshotPath
            CaptureError = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Present = $false
            Bytes = 0
            Text = $null
            SnapshotPath = if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) { $snapshotPath } else { $null }
            CaptureError = $_.Exception.Message
        }
    }
}

function Get-EesMessageSummary {
    param([object]$Capture)

    if ($null -eq $Capture -or -not $Capture.Present) { return $null }
    $summary = ([string]$Capture.Text).Trim()
    if ($summary.Length -gt 4000) {
        return $summary.Substring(0, 4000) + ' ... [see the retained EES_Msg.txt snapshot for the complete message]'
    }
    return $summary
}

function Resolve-EesArtifactManifest {
    param(
        [string]$ManifestPath,
        [string]$ResolvedWorkspace,
        [bool]$AllowReplace
    )

    $empty = [pscustomobject][ordered]@{
        path = $null
        inputs = @()
        outputs = @()
    }
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) { return $empty }

    $resolvedManifest = Get-AbsolutePath $ManifestPath
    if (-not (Test-PathWithin -CandidatePath $resolvedManifest -RootPath $ResolvedWorkspace)) {
        throw "ArtifactManifestPath must be inside WorkspaceRoot ($ResolvedWorkspace): $resolvedManifest"
    }
    if (-not (Test-Path -LiteralPath $resolvedManifest -PathType Leaf)) {
        throw "Artifact manifest was not found: $resolvedManifest"
    }
    if (-not [System.IO.Path]::GetExtension($resolvedManifest).Equals('.json', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'ArtifactManifestPath must have a .json extension.'
    }

    try { $document = Get-Content -LiteralPath $resolvedManifest -Raw | ConvertFrom-Json }
    catch { throw "Artifact manifest is not valid JSON: $($_.Exception.Message)" }
    if ($null -eq $document -or
        -not ($document.PSObject.Properties.Name -contains 'version') -or
        [int]$document.version -ne 1) {
        throw 'Artifact manifest must declare version 1.'
    }
    if (-not ($document.PSObject.Properties.Name -contains 'inputs') -or
        -not ($document.PSObject.Properties.Name -contains 'outputs')) {
        throw 'Artifact manifest must contain inputs and outputs arrays, which may be empty.'
    }

    $resolvedInputs = New-Object System.Collections.Generic.List[object]
    $resolvedOutputs = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($document.inputs)) {
        if ($null -eq $item -or
            -not ($item.PSObject.Properties.Name -contains 'name') -or
            -not ($item.PSObject.Properties.Name -contains 'path')) {
            throw 'Every artifact-manifest input must contain name and path properties.'
        }
        $name = [string]$item.name
        $pathText = [string]$item.path
        if ([string]::IsNullOrWhiteSpace($pathText)) { throw "Input binding $name has an empty path." }
        $candidate = if ([System.IO.Path]::IsPathRooted($pathText)) {
            [System.IO.Path]::GetFullPath($pathText)
        }
        else { [System.IO.Path]::GetFullPath((Join-Path $ResolvedWorkspace $pathText)) }
        if (-not (Test-PathWithin -CandidatePath $candidate -RootPath $ResolvedWorkspace)) {
            throw "Input binding $name must remain inside WorkspaceRoot: $candidate"
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Input binding $name was not found: $candidate"
        }
        $resolvedInputs.Add([pscustomobject][ordered]@{ name = $name; path = $candidate })
    }
    foreach ($item in @($document.outputs)) {
        if ($null -eq $item -or
            -not ($item.PSObject.Properties.Name -contains 'name') -or
            -not ($item.PSObject.Properties.Name -contains 'path')) {
            throw 'Every artifact-manifest output must contain name and path properties.'
        }
        $name = [string]$item.name
        $pathText = [string]$item.path
        if ([string]::IsNullOrWhiteSpace($pathText)) { throw "Output binding $name has an empty path." }
        $candidate = if ([System.IO.Path]::IsPathRooted($pathText)) {
            [System.IO.Path]::GetFullPath($pathText)
        }
        else { [System.IO.Path]::GetFullPath((Join-Path $ResolvedWorkspace $pathText)) }
        if (-not (Test-PathWithin -CandidatePath $candidate -RootPath $ResolvedWorkspace)) {
            throw "Output binding $name must remain inside WorkspaceRoot: $candidate"
        }
        if ($candidate.Contains("'")) {
            throw "Output binding $name cannot contain a single quote because it is inserted into an EES string literal: $candidate"
        }
        if (Test-Path -LiteralPath $candidate) {
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                throw "Artifact output must name a file, not an existing directory: $candidate"
            }
            if (-not $AllowReplace) {
                throw "Artifact output already exists: $candidate. Choose a new path or use -Force."
            }
        }
        $resolvedOutputs.Add([pscustomobject][ordered]@{ name = $name; path = $candidate })
    }

    return [pscustomobject][ordered]@{
        path = $resolvedManifest
        inputs = @($resolvedInputs | ForEach-Object { $_ })
        outputs = @($resolvedOutputs | ForEach-Object { $_ })
    }
}

function Get-ProcessWindowText {
    param([int]$ProcessId)

    if (-not ('EesHarness.NativeWindows' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace EesHarness {
    public static class NativeWindows {
        private delegate bool EnumWindowProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowProc callback, IntPtr extraData);

        [DllImport("user32.dll")]
        private static extern bool EnumChildWindows(IntPtr parent, EnumWindowProc callback, IntPtr extraData);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

        private static void AddText(IntPtr hWnd, List<string> result) {
            var buffer = new StringBuilder(4096);
            if (GetWindowText(hWnd, buffer, buffer.Capacity) > 0) {
                var value = buffer.ToString().Trim();
                if (value.Length > 0 && !result.Contains(value)) result.Add(value);
            }
        }

        public static string[] GetTextForProcess(int requestedProcessId) {
            var result = new List<string>();
            EnumWindows(delegate(IntPtr hWnd, IntPtr ignored) {
                uint actualProcessId;
                GetWindowThreadProcessId(hWnd, out actualProcessId);
                if (actualProcessId == (uint)requestedProcessId) {
                    AddText(hWnd, result);
                    EnumChildWindows(hWnd, delegate(IntPtr child, IntPtr childIgnored) {
                        AddText(child, result);
                        return true;
                    }, IntPtr.Zero);
                }
                return true;
            }, IntPtr.Zero);
            return result.ToArray();
        }
    }
}
'@
    }

    $captured = New-Object 'System.Collections.Generic.List[string]'
    foreach ($value in [EesHarness.NativeWindows]::GetTextForProcess($ProcessId)) {
        if (-not $captured.Contains($value)) {
            $captured.Add($value)
        }
    }

    try {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
            $ProcessId
        )
        $elements = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            $condition
        )
        for ($index = 0; $index -lt $elements.Count; $index++) {
            try {
                $value = $elements.Item($index).Current.Name.Trim()
                if ($value -and -not $captured.Contains($value)) {
                    $captured.Add($value)
                }
            }
            catch {
                # An element can disappear while EES is being inspected.
            }
        }
    }
    catch {
        # Win32 text collected above is still useful if UI Automation is unavailable.
    }

    return @($captured.ToArray())
}

try {
    if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
        throw "WorkspaceRoot was not found: $WorkspaceRoot"
    }
    $resolvedWorkspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path

    if (-not (Test-Path -LiteralPath $ProgramPath -PathType Leaf)) {
        throw "EES text program was not found: $ProgramPath"
    }

    $resolvedProgram = (Resolve-Path -LiteralPath $ProgramPath).Path
    if (-not (Test-PathWithin -CandidatePath $resolvedProgram -RootPath $resolvedWorkspace)) {
        throw "ProgramPath must be inside WorkspaceRoot ($resolvedWorkspace): $resolvedProgram"
    }
    if ([System.IO.Path]::GetExtension($resolvedProgram) -ne '.txt') {
        throw 'The input program must have a .txt extension so EES treats it as equation text.'
    }

    if ($resolvedWorkspace.Contains("'")) {
        throw "WorkspaceRoot cannot contain a single quote because staged paths are inserted into EES string literals: $resolvedWorkspace"
    }
    $hasPrimaryOutput = -not [string]::IsNullOrWhiteSpace($OutputPath)
    if ($hasPrimaryOutput) {
        $resolvedOutput = Get-AbsolutePath $OutputPath
        if (-not (Test-PathWithin -CandidatePath $resolvedOutput -RootPath $resolvedWorkspace)) {
            throw "OutputPath must be inside WorkspaceRoot ($resolvedWorkspace): $resolvedOutput"
        }
        if ($resolvedOutput.Contains("'")) {
            throw "OutputPath cannot contain a single quote because it is inserted into an EES string literal: $resolvedOutput"
        }
        if (Test-Path -LiteralPath $resolvedOutput) {
            if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
                throw "OutputPath must name a file, not an existing directory: $resolvedOutput"
            }
            if (-not $Force) {
                throw "Output already exists: $resolvedOutput. Choose a new path or use -Force."
            }
        }
    }

    $artifactManifest = Resolve-EesArtifactManifest `
        -ManifestPath $ArtifactManifestPath `
        -ResolvedWorkspace $resolvedWorkspace `
        -AllowReplace ([bool]$Force)
    $programText = [System.IO.File]::ReadAllText($resolvedProgram)
    $programPolicy = Assert-EesProgramPolicy `
        -Text $programText `
        -PrimaryOutputDeclared $hasPrimaryOutput `
        -InputBindingNames @($artifactManifest.inputs | ForEach-Object { $_.name }) `
        -OutputBindingNames @($artifactManifest.outputs | ForEach-Object { $_.name })

    if ($hasPrimaryOutput) {
        Assert-EesArtifactExtension -Path $resolvedOutput -Directive $programPolicy.primary_output_use.directive
    }
    $protectedPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    [void]$protectedPaths.Add($resolvedProgram)
    if ($artifactManifest.path) { [void]$protectedPaths.Add([string]$artifactManifest.path) }
    foreach ($inputBinding in @($artifactManifest.inputs)) { [void]$protectedPaths.Add([string]$inputBinding.path) }
    $outputDestinations = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ($hasPrimaryOutput) {
        if ($protectedPaths.Contains($resolvedOutput)) { throw "OutputPath cannot replace the program, manifest, or a declared input: $resolvedOutput" }
        [void]$outputDestinations.Add($resolvedOutput)
    }
    foreach ($outputBinding in @($artifactManifest.outputs)) {
        $use = @($programPolicy.output_uses | Where-Object { $_.name -eq $outputBinding.name })[0]
        Assert-EesArtifactExtension -Path $outputBinding.path -Directive $use.directive
        if ($protectedPaths.Contains([string]$outputBinding.path)) {
            throw "Output binding $($outputBinding.name) cannot replace the program, manifest, or a declared input: $($outputBinding.path)"
        }
        if (-not $outputDestinations.Add([string]$outputBinding.path)) {
            throw "Multiple outputs resolve to the same destination: $($outputBinding.path)"
        }
    }
    foreach ($inputBinding in @($artifactManifest.inputs)) {
        $use = @($programPolicy.input_uses | Where-Object { $_.name -eq $inputBinding.name })[0]
        Assert-EesArtifactExtension -Path $inputBinding.path -Directive $use.directive
    }

    $runId = [guid]::NewGuid().ToString('N')
    $runRoot = Join-Path $resolvedWorkspace '.ees-runs'
    if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $runRoot | Out-Null
    }
    $runDirectory = Join-Path $runRoot $runId
    New-Item -ItemType Directory -Path $runDirectory | Out-Null

    $stagedProgram = Join-Path $runDirectory 'program.txt'
    $stagedOutput = $null
    $renderedProgram = $programText
    if ($null -ne $programPolicy.primary_output_use) {
        $primaryExtension = if ($hasPrimaryOutput) { [System.IO.Path]::GetExtension($resolvedOutput) } else { '.txt' }
        $stagedOutput = Join-Path $runDirectory ('result' + $primaryExtension)
        $renderedProgram = $renderedProgram.Replace('{{OUTPUT_FILE}}', $stagedOutput)
    }

    $inputStageRoot = Join-Path $runDirectory 'inputs'
    if (@($artifactManifest.inputs).Count -gt 0) { New-Item -ItemType Directory -Path $inputStageRoot | Out-Null }
    $preparedInputs = @($artifactManifest.inputs | ForEach-Object {
        $binding = $_
        $use = @($programPolicy.input_uses | Where-Object { $_.name -eq $binding.name })[0]
        $stagedPath = Join-Path $inputStageRoot ($binding.name + [System.IO.Path]::GetExtension($binding.path))
        Copy-Item -LiteralPath $binding.path -Destination $stagedPath
        $renderedProgram = $renderedProgram.Replace(('{{' + $binding.name + '}}'), $stagedPath)
        [pscustomobject][ordered]@{
            name = $binding.name
            directive = $use.directive
            source_path = $binding.path
            staged_path = $stagedPath
        }
    })

    $outputStageRoot = Join-Path $runDirectory 'outputs'
    if (@($artifactManifest.outputs).Count -gt 0) { New-Item -ItemType Directory -Path $outputStageRoot | Out-Null }
    $preparedOutputs = @($artifactManifest.outputs | ForEach-Object {
        $binding = $_
        $use = @($programPolicy.output_uses | Where-Object { $_.name -eq $binding.name })[0]
        $stagedPath = Join-Path $outputStageRoot ($binding.name + [System.IO.Path]::GetExtension($binding.path))
        $renderedProgram = $renderedProgram.Replace(('{{' + $binding.name + '}}'), $stagedPath)
        [pscustomobject][ordered]@{
            name = $binding.name
            directive = $use.directive
            output_path = $binding.path
            staged_path = $stagedPath
        }
    })
    if ([regex]::IsMatch($renderedProgram, '\{\{[^{}]+\}\}')) {
        throw 'The rendered EES program still contains an unresolved artifact placeholder.'
    }
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($stagedProgram, $renderedProgram, $utf8WithoutBom)

    $resolvedEes = Resolve-EesExecutable $EesPath
    $eesLeafName = [System.IO.Path]::GetFileName($resolvedEes)
    if ($eesLeafName -notin @('ees64.exe', 'ees.exe')) {
        throw "EesPath must name ees64.exe or ees.exe: $resolvedEes"
    }
    $launcherConfigPath = Join-Path $PSScriptRoot 'config.json'
    if (Test-Path -LiteralPath $launcherConfigPath -PathType Leaf) {
        $launcherConfig = Get-Content -LiteralPath $launcherConfigPath -Raw | ConvertFrom-Json
        if ($launcherConfig.PSObject.Properties.Name -contains 'required_architecture') {
            $requiredArchitecture = [string]$launcherConfig.required_architecture
            $actualArchitecture = if ($eesLeafName -eq 'ees.exe') { '32-bit' } else { '64-bit' }
            if ($requiredArchitecture -in @('32-bit', '64-bit') -and $actualArchitecture -ne $requiredArchitecture) {
                throw "This installed launcher requires $requiredArchitecture EES and cannot run $actualArchitecture EES: $resolvedEes"
            }
        }
    }
    if (Test-PathWithin -CandidatePath $resolvedEes -RootPath $resolvedWorkspace) {
        throw "EesPath must be outside the writable workspace: $resolvedEes"
    }
    $eesMessageSupported = (Get-EesFileVersion -ResolvedEesPath $resolvedEes) -ge $eesMessageMinimumFileVersion
    $runLock = Enter-EesRunLock -ResolvedEesPath $resolvedEes
    if ($eesMessageSupported) {
        $eesMessagePath = Reset-EesMessageFile -ResolvedEesPath $resolvedEes
        $eesMessageReset = $true
    }
    $startTime = [DateTimeOffset]::Now
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $resolvedEes
    $startInfo.Arguments = ('"{0}" /solve /nosplash /AI' -f $stagedProgram.Replace('"', '\"'))
    # EES 12.3.3.2 can exit without solving when started as a hidden,
    # non-shell process. Match a normal Start-Process launch, which preserves
    # the command-line solve/export behavior across current EES releases.
    $startInfo.UseShellExecute = $true
    $startInfo.CreateNoWindow = $false
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal

    $process = [System.Diagnostics.Process]::Start($startInfo)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $windowText = @(Get-ProcessWindowText -ProcessId $process.Id)
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(5000) | Out-Null
        $eesMessageCapture = if ($eesMessageSupported) {
            Capture-EesMessageFile -SourcePath $eesMessagePath -RunDirectory $runDirectory
        }
        else { New-EmptyEesMessageCapture }
        if ($eesMessageSupported -and $eesMessageCapture.CaptureError) {
            throw "EES did not finish within $TimeoutSeconds seconds, and EES_Msg.txt could not be captured: $($eesMessageCapture.CaptureError)"
        }
        $messageSummary = Get-EesMessageSummary -Capture $eesMessageCapture
        $detail = if ($messageSummary) {
            "EES_Msg.txt: $messageSummary"
        }
        elseif ($windowText.Count -gt 0) {
            'EES window text: ' + ($windowText -join ' | ')
        }
        elseif (-not $eesMessageSupported) {
            "EES_Msg.txt capture requires EES $eesMessageMinimumVersion or newer, and no accessible window text was available."
        }
        else {
            'No fresh EES_Msg.txt message or accessible window text was available.'
        }
        throw "EES did not finish within $TimeoutSeconds seconds. $detail"
    }

    $eesMessageCapture = if ($eesMessageSupported) {
        Capture-EesMessageFile -SourcePath $eesMessagePath -RunDirectory $runDirectory
    }
    else { New-EmptyEesMessageCapture }
    if ($eesMessageSupported -and $eesMessageCapture.CaptureError) {
        throw "EES finished, but EES_Msg.txt could not be captured: $($eesMessageCapture.CaptureError)"
    }
    Exit-EesRunLock -State $runLock
    $runLock = $null

    $artifactResults = New-Object System.Collections.Generic.List[object]
    $outputBytes = 0
    $expectedFiles = @([pscustomobject][ordered]@{
            name = 'OUTPUT_FILE'
            directive = $programPolicy.primary_output_use.directive
            staged_path = $stagedOutput
            output_path = $resolvedOutput
            primary = $true
    }) + @($preparedOutputs | ForEach-Object {
            [pscustomobject][ordered]@{
                name = $_.name
                directive = $_.directive
                staged_path = $_.staged_path
                output_path = $_.output_path
                primary = $false
            }
    })
    $messageSummary = Get-EesMessageSummary -Capture $eesMessageCapture
    $missingDetail = if ($messageSummary) {
            " EES_Msg.txt: $messageSummary"
    }
    elseif (-not $eesMessageSupported) {
            " EES_Msg.txt capture requires EES $eesMessageMinimumVersion or newer."
    }
    else { ' No fresh EES_Msg.txt message was written.' }

    foreach ($expected in $expectedFiles) {
            if (-not (Test-Path -LiteralPath $expected.staged_path -PathType Leaf)) {
                throw "EES exited with code $($process.ExitCode) but did not create artifact $($expected.name).$missingDetail"
            }
            if ((Get-Item -LiteralPath $expected.staged_path).Length -eq 0) {
                throw "EES created an empty artifact for $($expected.name).$missingDetail"
            }
    }
    foreach ($expected in $expectedFiles) {
            $parent = Split-Path -Parent $expected.output_path
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Move-Item -LiteralPath $expected.staged_path -Destination $expected.output_path -Force:$Force
            $bytes = (Get-Item -LiteralPath $expected.output_path).Length
            if ($expected.primary) {
                $outputBytes = $bytes
            }
            else {
                $artifactResults.Add([pscustomobject][ordered]@{
                    name = $expected.name
                    directive = $expected.directive
                    path = $expected.output_path
                    bytes = $bytes
                })
            }
    }
    $endTime = [DateTimeOffset]::Now

    $retainRunDirectory = $KeepRunFiles -or $eesMessageCapture.Present
    if (-not $retainRunDirectory) {
        $verifiedRunDirectory = [System.IO.Path]::GetFullPath($runDirectory)
        if (-not (Test-PathWithin -CandidatePath $verifiedRunDirectory -RootPath $runRoot)) {
            throw "Refusing to remove an unexpected run directory: $verifiedRunDirectory"
        }
        Remove-Item -LiteralPath $verifiedRunDirectory -Recurse -Force
        $remaining = @(Get-ChildItem -LiteralPath $runRoot -Force)
        if ($remaining.Count -eq 0) {
            Remove-Item -LiteralPath $runRoot -Force
        }
    }

    [pscustomobject]@{
        status = 'success'
        ees_path = $resolvedEes
        workspace_root = $resolvedWorkspace
        program_path = $resolvedProgram
        mode = 'Solve'
        output_path = $resolvedOutput
        elapsed_seconds = [math]::Round(($endTime - $startTime).TotalSeconds, 3)
        output_bytes = $outputBytes
        artifact_manifest_path = $artifactManifest.path
        input_artifacts = @($preparedInputs | ForEach-Object {
            [pscustomobject][ordered]@{ name = $_.name; directive = $_.directive; path = $_.source_path }
        })
        output_artifacts = @($artifactResults | ForEach-Object { $_ })
        run_directory = if ($retainRunDirectory) { $runDirectory } else { $null }
        ees_message_supported = $eesMessageSupported
        ees_message_minimum_ees_version = $eesMessageMinimumVersion
        ees_message_path = $eesMessagePath
        ees_message_present = [bool]$eesMessageCapture.Present
        ees_message_bytes = [long]$eesMessageCapture.Bytes
        ees_message = if ($eesMessageCapture.Present) { $eesMessageCapture.Text } else { $null }
        ees_message_snapshot = if ($retainRunDirectory) { $eesMessageCapture.SnapshotPath } else { $null }
    } | ConvertTo-Json -Depth 6
    exit 0
}
catch {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(5000) | Out-Null
    }
    if ($eesMessageReset -and $eesMessagePath -and $runDirectory -and $null -eq $eesMessageCapture) {
        $eesMessageCapture = Capture-EesMessageFile -SourcePath $eesMessagePath -RunDirectory $runDirectory
    }
    [pscustomobject]@{
        status = 'error'
        message = $_.Exception.Message
        mode = 'Solve'
        run_directory = $runDirectory
        ees_message_supported = $eesMessageSupported
        ees_message_minimum_ees_version = $eesMessageMinimumVersion
        ees_message_path = $eesMessagePath
        ees_message_present = if ($null -ne $eesMessageCapture) { [bool]$eesMessageCapture.Present } else { $false }
        ees_message_bytes = if ($null -ne $eesMessageCapture) { [long]$eesMessageCapture.Bytes } else { 0 }
        ees_message = if ($null -ne $eesMessageCapture -and $eesMessageCapture.Present) { $eesMessageCapture.Text } else { $null }
        ees_message_snapshot = if ($null -ne $eesMessageCapture) { $eesMessageCapture.SnapshotPath } else { $null }
        ees_message_capture_error = if ($null -ne $eesMessageCapture) { $eesMessageCapture.CaptureError } else { $null }
    } | ConvertTo-Json -Depth 6
    exit 1
}
finally {
    if ($runLock) {
        Exit-EesRunLock -State $runLock
        $runLock = $null
    }
}
