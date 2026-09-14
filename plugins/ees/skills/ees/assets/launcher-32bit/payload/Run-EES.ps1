[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProgramPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$WorkspaceRoot = $PSScriptRoot,

    [string]$EesPath,

    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 120,

    [switch]$Force,

    [switch]$KeepRunFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runDirectory = $null
$process = $null
$runLock = $null

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

function Assert-SafeProgram {
    param([string]$Text)

    $placeholder = '{{OUTPUT_FILE}}'
    $placeholderCount = ([regex]::Matches($Text, [regex]::Escape($placeholder))).Count
    if ($placeholderCount -ne 1) {
        throw "The program must contain exactly one $placeholder placeholder; found $placeholderCount."
    }

    $exportLines = @($Text -split "`r?`n" | Where-Object { $_ -match '(?i)^\s*\$(Export|ExportText)\b' })
    if ($exportLines.Count -ne 1 -or $exportLines[0] -notlike "*$placeholder*") {
        throw 'The program must contain exactly one $Export or $ExportText directive, and that line must use {{OUTPUT_FILE}}.'
    }

    $loadLines = @($Text -split "`r?`n" | Where-Object { $_ -match '(?i)^\s*\$Load\b' })
    $allowedLoads = @(
        '$Load Component Library',
        '$Load Mechanical',
        '$Load NASA',
        '$Load Incompressible'
    )
    foreach ($loadLine in $loadLines) {
        $normalizedLoad = ([regex]::Replace($loadLine.Trim(), '\s+', ' '))
        if (-not ($allowedLoads -contains $normalizedLoad)) {
            throw "Blocked library directive $normalizedLoad. Allowed values are: $($allowedLoads -join ', ')."
        }
    }

    $blocked = '(?im)^\s*\$(RunMacroAfter|RunMacroBefore|Python|Include|OpenLookup|SaveLookup|SaveTable|SaveVarInfo|ExportPlot|Reference|Import|ImportText)\b'
    $match = [regex]::Match($Text, $blocked)
    if ($match.Success) {
        throw "Blocked external-action directive $($match.Value.Trim()). The safe launcher permits one generated program and one result file only."
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

    $resolvedOutput = Get-AbsolutePath $OutputPath
    if (-not (Test-PathWithin -CandidatePath $resolvedOutput -RootPath $resolvedWorkspace)) {
        throw "OutputPath must be inside WorkspaceRoot ($resolvedWorkspace): $resolvedOutput"
    }
    if ([System.IO.Path]::GetExtension($resolvedOutput) -eq '') {
        throw 'OutputPath must have an extension supported by the EES export directive, such as .txt or .csv.'
    }
    if ($resolvedOutput.Contains("'")) {
        throw "OutputPath cannot contain a single quote because it is inserted into an EES string literal: $resolvedOutput"
    }
    if ((Test-Path -LiteralPath $resolvedOutput) -and -not $Force) {
        throw "Output already exists: $resolvedOutput. Choose a new path or use -Force."
    }

    $outputParent = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
        New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    }

    $programText = [System.IO.File]::ReadAllText($resolvedProgram)
    Assert-SafeProgram -Text $programText

    $runId = [guid]::NewGuid().ToString('N')
    $runRoot = Join-Path $resolvedWorkspace '.ees-runs'
    if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $runRoot | Out-Null
    }
    $runDirectory = Join-Path $runRoot $runId
    New-Item -ItemType Directory -Path $runDirectory | Out-Null

    $stagedProgram = Join-Path $runDirectory 'program.txt'
    $stagedOutput = Join-Path $runDirectory ('result' + [System.IO.Path]::GetExtension($resolvedOutput))
    $renderedProgram = $programText.Replace('{{OUTPUT_FILE}}', $stagedOutput)
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
    $runLock = Enter-EesRunLock -ResolvedEesPath $resolvedEes
    $startTime = [DateTimeOffset]::Now
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $resolvedEes
    $startInfo.Arguments = ('"{0}" /solve /nosplash /AI' -f $stagedProgram.Replace('"', '\"'))
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $process = [System.Diagnostics.Process]::Start($startInfo)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $windowText = @(Get-ProcessWindowText -ProcessId $process.Id)
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(5000) | Out-Null
        $detail = if ($windowText.Count -gt 0) { $windowText -join ' | ' } else { 'No dialog text was available.' }
        throw "EES did not finish within $TimeoutSeconds seconds. This usually indicates a modal compile/solve error. EES window text: $detail"
    }

    Exit-EesRunLock -State $runLock
    $runLock = $null

    if (-not (Test-Path -LiteralPath $stagedOutput -PathType Leaf)) {
        throw "EES exited with code $($process.ExitCode) but did not create the expected result file."
    }
    if ((Get-Item -LiteralPath $stagedOutput).Length -eq 0) {
        throw 'EES created an empty result file.'
    }

    Move-Item -LiteralPath $stagedOutput -Destination $resolvedOutput -Force:$Force
    $endTime = [DateTimeOffset]::Now

    if (-not $KeepRunFiles) {
        Remove-Item -LiteralPath $stagedProgram -Force
        Remove-Item -LiteralPath $runDirectory -Force
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
        output_path = $resolvedOutput
        elapsed_seconds = [math]::Round(($endTime - $startTime).TotalSeconds, 3)
        output_bytes = (Get-Item -LiteralPath $resolvedOutput).Length
        run_directory = if ($KeepRunFiles) { $runDirectory } else { $null }
    } | ConvertTo-Json
    exit 0
}
catch {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    [pscustomobject]@{
        status = 'error'
        message = $_.Exception.Message
        run_directory = $runDirectory
    } | ConvertTo-Json
    exit 1
}
finally {
    if ($runLock) {
        Exit-EesRunLock -State $runLock
        $runLock = $null
    }
}
