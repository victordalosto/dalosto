# =============================================================================
# Windows PowerShell Profile — Unix-like commands
# =============================================================================
# What this is:
#   A PowerShell startup profile that defines Unix-style commands
#   (rm, cp, mv, cat, ls, touch, which, grep, head, tail,
#    export, printenv, env, mkdir-p)
#   so familiar shell muscle memory works in Windows PowerShell.
#
# Where to place this file:
#   Windows PowerShell 5.1 (powershell.exe):
#     %USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
#
# Loaded automatically every time a new PowerShell session starts.
# =============================================================================

# ---- Free names occupied by built-in aliases ----
# rm/cp/mv/cat/ls always: our functions below replace them.
# wget/curl only when the real .exe is on PATH, so users without those
# binaries still keep the built-in Invoke-WebRequest alias.
foreach ($a in 'rm','cp','mv','cat','ls','history') {
    if (Test-Path "Alias:$a") { Remove-Item "Alias:$a" -Force }
}

foreach ($a in 'wget','curl') {
    if ((Test-Path "Alias:$a") -and (Get-Command "$a.exe" -ErrorAction Ignore)) {
        Remove-Item "Alias:$a" -Force
    }
}

# ---- File operations ----

function rm {
    $paths = @()
    $recurse = $false
    $force   = $false
    $verbose = $false
    foreach ($x in $args) {
        switch -Regex ($x) {
            '^--recursive$' { $recurse = $true; continue }
            '^--force$'     { $force   = $true; continue }
            '^--verbose$'   { $verbose = $true; continue }
            '^-[rRfFvV]+$'  {
                if ($x -cmatch '[rR]') { $recurse = $true }
                if ($x -cmatch '[fF]') { $force   = $true }
                if ($x -cmatch '[vV]') { $verbose = $true }
                continue
            }
            default { $paths += $x }
        }
    }
    if ($paths.Count -eq 0) {
        Write-Error "rm: missing operand"
        return
    }
    # Only suppress errors when -f is given (Unix semantics).
    $ea = if ($force) { 'SilentlyContinue' } else { 'Continue' }
    Remove-Item -Path $paths -Recurse:$recurse -Force:$force -Verbose:$verbose -ErrorAction $ea
}

function cp { Copy-Item @args }
function mv { Move-Item @args }
function cat { Get-Content @args }
function ls { Get-ChildItem @args }
function ll { Get-ChildItem -Force @args }
Set-Alias la ll

function touch {
    if ($args.Count -eq 0) { Write-Error "touch: missing operand"; return }
    $now = Get-Date
    foreach ($p in $args) {
        if (Test-Path -LiteralPath $p) {
            (Get-Item -LiteralPath $p).LastWriteTime = $now
        } else {
            $parent = Split-Path -Parent $p
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            New-Item -ItemType File -Path $p | Out-Null
        }
    }
}

function which {
    if ($args.Count -eq 0) { Write-Error "which: missing operand"; return }
    $missing = $false
    foreach ($name in $args) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        # Follow alias chain to the real command.
        while ($cmd -and $cmd.CommandType -eq 'Alias') {
            $cmd = $cmd.ResolvedCommand
        }
        if ($cmd) {
            if ($cmd.Source) { $cmd.Source } else { "$($cmd.Name) ($($cmd.CommandType))" }
        } else {
            Write-Error "which: ${name}: not found"
            $missing = $true
        }
    }
    if ($missing) { $global:LASTEXITCODE = 1 }
}

function grep {
    if ($MyInvocation.ExpectingInput) {
        # Stringify pipeline input so FileInfo/DirectoryInfo objects are
        # matched by name, not by opening and reading their contents.
        $input | ForEach-Object { "$_" } | Select-String @args
    } else {
        Select-String @args
    }
}

function head {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)] $InputObject,
        [Alias('n')][int]$Lines = 10,
        [Parameter(Position=0, ValueFromRemainingArguments=$true)][string[]]$Path
    )
    begin {
        $buf = [System.Collections.Generic.List[object]]::new()
        $fromPipe = $false
    }
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $fromPipe = $true
            if ($buf.Count -lt $Lines) { $buf.Add($InputObject) }
        }
    }
    end {
        if ($fromPipe)   { $buf }
        elseif ($Path)   { Get-Content -Path $Path -TotalCount $Lines }
        else             { Write-Error "head: missing operand" }
    }
}

function tail {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)] $InputObject,
        [Alias('n')][int]$Lines = 10,
        [Parameter(Position=0, ValueFromRemainingArguments=$true)][string[]]$Path
    )
    begin {
        $buf = [System.Collections.Generic.List[object]]::new()
        $fromPipe = $false
    }
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $fromPipe = $true
            $buf.Add($InputObject)
        }
    }
    end {
        if ($fromPipe)   { $buf | Select-Object -Last $Lines }
        elseif ($Path)   { Get-Content -Path $Path -Tail $Lines }
        else             { Write-Error "tail: missing operand" }
    }
}

function printenv {
    if ($args.Count -eq 0) {
        Get-ChildItem env: | ForEach-Object { "$($_.Name)=$($_.Value)" }
        return
    }
    $missing = $false
    foreach ($name in $args) {
        $item = Get-Item -LiteralPath "env:$name" -ErrorAction SilentlyContinue
        if ($item) { $item.Value } else { $missing = $true }
    }
    if ($missing) { $global:LASTEXITCODE = 1 }
}

function env {
    if ($args.Count -ne 0) {
        Write-Error "env: running commands with a modified environment is not supported; use `$env:VAR = ... ; cmd"
        return
    }
    Get-ChildItem env: | ForEach-Object { "$($_.Name)=$($_.Value)" }
}

function export {
    if ($args.Count -eq 0) {
        Write-Error "export: missing operand (KEY=VALUE)"
        return
    }
    foreach ($kv in $args) {
        if ($kv -notmatch '^([^=\s]+)=(.*)$') {
            Write-Error "export: '$kv' is not in KEY=VALUE form"
            continue
        }
        $k = $Matches[1]
        $v = $Matches[2]
        # Strip one layer of matching surrounding quotes, like sh does.
        if ($v.Length -ge 2 -and
            (($v.StartsWith('"') -and $v.EndsWith('"')) -or
             ($v.StartsWith("'") -and $v.EndsWith("'")))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        Set-Item -Path "env:$k" -Value $v
    }
}

function mkdir-p {
    if ($args.Count -eq 0) { Write-Error "mkdir-p: missing operand"; return }
    foreach ($p in $args) {
        if (-not (Test-Path -LiteralPath $p)) {
            New-Item -ItemType Directory -Path $p -Force | Out-Null
        }
    }
}

# Show persistent shell history (PSReadLine file), not just the current session.
function history {
    $path = (Get-PSReadLineOption).HistorySavePath
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return }
    $i = 1
    Get-Content -LiteralPath $path | ForEach-Object {
        '{0,5}  {1}' -f $i, $_
        $i++
    }
}


# ---- Prompt & colors (Ubuntu-style) ----
# Replaces the default 'PS C:\...>' prompt with 'user@host:~/path$ '
# and colors typed input via PSReadLine.

function prompt {
    $p = $PWD.Path
    if ($HOME -and $p.StartsWith($HOME)) {
        $p = '~' + $p.Substring($HOME.Length)
    }
    $p = $p -replace '\\', '/'

    $esc       = [char]27
    $lavender  = "$esc[38;2;200;162;255m"
    $reset     = "$esc[0m"

    Write-Host "$lavender$p$reset" -NoNewline
    Write-Host ' ' -NoNewline -ForegroundColor White
    return ' '
}

# Input coloring (what you type) — Ubuntu-ish palette
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -Colors @{
        Command   = 'Green'
        Parameter = 'Cyan'
        String    = 'Yellow'
        Variable  = 'Cyan'
        Operator  = 'White'
        Number    = 'Magenta'
        Keyword   = 'Magenta'
        Comment   = 'DarkGray'
    }
}

# Default color for command output
$Host.UI.RawUI.ForegroundColor = 'White'

# ---- Window title ----
$Host.UI.RawUI.WindowTitle = 'Terminal'

# ---- Startup greeting ----
# Clears the default 'Windows PowerShell / Copyright ...' banner and replaces
# it with a localized Portuguese date/time line.
Clear-Host
$ci  = [System.Globalization.CultureInfo]::new('pt-BR')
$now = Get-Date
$day = ($ci.DateTimeFormat.GetDayName($now.DayOfWeek)) -replace '-', ' '
$day = $day.Substring(0,1).ToUpper() + $day.Substring(1)
$mon = $ci.DateTimeFormat.GetMonthName($now.Month)
Write-Host (" {0}, {1} de {2} de {3}.  {4:HH:mm}h" -f $day, $now.Day, $mon, $now.Year, $now) -ForegroundColor Yellow
Write-Host ''
