# run.ps1 - Windows launcher for tack harness POSIX shell scripts.
#
# Locates Git for Windows bash.exe (auto-installs Git for Windows via winget
# when missing), normalizes path arguments (backslash -> slash), then runs
# <name>.sh located in this directory. Exit code is passed through.
# On macOS/Linux use sh directly; this launcher is Windows-only.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File run.ps1 <script-name> [args...]
# Examples:
#   powershell -ExecutionPolicy Bypass -File run.ps1 init-tack D:/Code/AI/my-space
#   powershell -ExecutionPolicy Bypass -File "$root\harness\script\run.ps1" scan-routes list "$root/harness"
#   powershell -ExecutionPolicy Bypass -File "$root\harness\script\run.ps1" resolve "$root/harness" "<keyword>"
#
# Note: path arguments must use forward slashes (D:/Code/AI/test), not backslashes.
# Keep this file ASCII-only: Windows PowerShell 5.1 parses BOM-less .ps1 as the
# system ANSI codepage, so non-ASCII characters may break parsing.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Script,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArgs
)

$ErrorActionPreference = 'Stop'

# Locate Git for Windows bash.exe: PATH -> common install dirs -> registry
function Find-Bash {
    $cmd = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }

    foreach ($k in @('HKLM:\SOFTWARE\GitForWindows', 'HKCU:\SOFTWARE\GitForWindows', 'HKLM:\SOFTWARE\WOW6432Node\GitForWindows')) {
        $props = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if ($props -and $props.InstallPath) {
            $p = Join-Path $props.InstallPath 'bin\bash.exe'
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    return $null
}

# Normalize an argument: backslash -> forward slash (Git Bash accepts D:/foo)
function Normalize-Arg([string]$a) {
    if ([string]::IsNullOrEmpty($a)) { return $a }
    return $a -replace '\\', '/'
}

# Install Git for Windows via winget; only invoked when bash.exe is absent.
# The Git.Git installer is machine-wide and may trigger a UAC prompt.
# On headless / non-elevated sessions winget fails; we then point the user at
# the manual download instead of leaving them with no guidance.
function Install-GitForWindows {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        [Console]::Error.WriteLine("Error: Git for Windows was not found and winget is unavailable.")
        [Console]::Error.WriteLine("Please install Git for Windows manually: https://git-scm.com/download/win")
        exit 127
    }

    Write-Host "Git for Windows not found. Installing via winget (Git.Git); a UAC prompt may appear..."
    & winget.exe install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        [Console]::Error.WriteLine("Error: winget failed to install Git for Windows (exit code $code).")
        [Console]::Error.WriteLine("Please install it manually: https://git-scm.com/download/win")
        exit 127
    }

    # The installer updates the persistent (machine/user) PATH; refresh it for
    # the current process so Find-Bash can locate bash.exe without a restart.
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

$bash = Find-Bash
if (-not $bash) {
    Install-GitForWindows
    $bash = Find-Bash
    if (-not $bash) {
        [Console]::Error.WriteLine("Error: Git for Windows was installed but bash.exe is still not on PATH.")
        [Console]::Error.WriteLine("Restart the terminal and retry, or install Git for Windows manually: https://git-scm.com/download/win")
        exit 127
    }
}

if (-not $Script.EndsWith('.sh')) { $Script = "$Script.sh" }
$scriptPath = Join-Path $PSScriptRoot $Script
if (-not (Test-Path -LiteralPath $scriptPath)) {
    [Console]::Error.WriteLine("Error: script not found: $scriptPath")
    exit 127
}

# Force UTF-8 for native command I/O to avoid mojibake with non-ASCII arguments
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding } catch { }
$OutputEncoding = New-Object System.Text.UTF8Encoding
$env:LANG = 'C.UTF-8'
$env:LC_ALL = 'C.UTF-8'

$invokeArgs = @((Normalize-Arg $scriptPath))
foreach ($a in $ScriptArgs) { $invokeArgs += (Normalize-Arg $a) }

& $bash @invokeArgs
exit $LASTEXITCODE
