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
    # A chain that was interrupted (Ctrl+C, or a terminating error) never ran
    # its probe, so put the exit code it stashed back before drawing the prompt.
    if ((Test-Path Variable:global:__chainStack) -and
        $null -ne $global:__chainStack -and $global:__chainStack.Count -gt 0) {
        if ($null -eq $global:LASTEXITCODE) {
            $global:LASTEXITCODE = $global:__chainStack[$global:__chainStack.Count - 1]
        }
        $global:__chainStack.Clear()
    }

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

# ---- POSIX command chaining: && and || --------------------------------------
# Windows PowerShell 5.1 has no '&&' / '||' operators - they arrived in
# PowerShell 7 - and they are rejected by the *parser*, so no function or alias
# can add them. What we can do is rewrite the line before it is submitted: the
# Enter handler below turns
#     a && b
# into the 5.1 equivalent
#     __chainReset; a; $__chain = __chainOk $?; if ($__chain) { b }
# chained left to right, exactly like sh.
#
# Only the statement the operator sits in is rewritten, and it is cut at that
# statement's own boundaries. So ';' and newlines keep binding looser than
# '&&' ('a && b; c' always runs c), a newline that merely continues a statement
# (after '|', ',', '=' or an operator) is not mistaken for the end of one, and a
# chain inside a block leaves the block's own 'else' / 'elseif' / 'default'
# clause where it belongs. Splitting uses PowerShell's tokenizer, so '&&' inside
# a string, a comment or a here-string is left alone and a lone '&' is never
# touched. Anything the rewriter is not sure about is submitted verbatim, so a
# typo still gets PowerShell's normal error instead of a mangled command.
#
# Scope: the interactive prompt only. '&&' inside a .ps1 file or in
# 'powershell -Command "..."' is parsed before any of this runs and still
# fails - there, write '; if ($?) { ... }' by hand.

# Status of the segment that just ran. '$?' is the signal, exactly as for
# PowerShell 7's own '&&'. It is overruled by a native exit code in one case
# only: 5.1 sets '$?' to False for a native command whose *error stream* was
# redirected ('git fetch 2>$null') even when it exited 0. Convert-ChainOperator
# therefore passes AllowExitCode only for a segment that redirects its error
# stream and has no pipeline after it - with a pipeline, the failure '$?'
# reports may be a downstream cmdlet's, and an exit code must not speak for it.
# __chainReset stashes $LASTEXITCODE and blanks it so a stale exit code cannot
# be mistaken for this segment's; __chainOk puts the stash back when the segment
# ran no native command. The stash is a stack, so a chain calling a
# function whose own body was rewritten still restores the right value.
# Created up front so reading them is safe under Set-StrictMode.
if (-not (Test-Path Variable:global:__chainStack)) {
    $global:__chainStack = New-Object 'System.Collections.Generic.List[object]'
}
if (-not (Test-Path Variable:global:LASTEXITCODE)) { $global:LASTEXITCODE = $null }

function __chainReset {
    if (-not (Test-Path Variable:global:__chainStack)) {
        $global:__chainStack = New-Object 'System.Collections.Generic.List[object]'
    }
    $global:__chainStack.Add($global:LASTEXITCODE)
    $global:LASTEXITCODE = $null
}

function __chainOk {
    param([bool]$Status, [bool]$AllowExitCode)

    $ok = $Status
    if (-not $ok -and $AllowExitCode -and $null -ne $global:LASTEXITCODE) {
        $ok = ($global:LASTEXITCODE -eq 0)
    }

    # Test the list against $null, never for truth: a one-element list holding
    # 0 or $null is itself falsy, which would drop the saved code on the floor.
    if ($null -ne $global:__chainStack -and $global:__chainStack.Count -gt 0) {
        $n = $global:__chainStack.Count
        if ($null -eq $global:LASTEXITCODE) {
            $global:LASTEXITCODE = $global:__chainStack[$n - 1]
        }
        $global:__chainStack.RemoveAt($n - 1)
    }

    return $ok
}

function Convert-ChainOperator {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Line
    )

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$errors)
    if (-not $tokens) { return $Line }

    # '--%' (stop-parsing) hands the rest of the line to the executable verbatim
    # - cmd.exe understands '&&' by itself there, so that text is not ours to
    # rewrite.
    if (@($tokens | Where-Object { $_.Text -eq '--%' }).Count -gt 0) { return $Line }

    # Bracket depth in front of every token. A closing bracket is recorded at
    # the depth of the level it closes, so it reads as a boundary for the text
    # inside that level.
    $depth  = 0
    $depths = New-Object 'System.Collections.Generic.List[int]'
    foreach ($t in $tokens) {
        $kind = "$($t.Kind)"
        if ($kind -eq 'RCurly' -or $kind -eq 'RParen') { $depth-- }
        $depths.Add($depth)
        if ('LCurly', 'LParen', 'AtCurly', 'AtParen', 'DollarParen' -contains $kind) { $depth++ }
    }

    # A newline ends a statement only when the token before it can end one.
    # After '|', ',', '=' or an operator PowerShell continues the statement on
    # the next line, and cutting there would splice the rewrite into its middle.
    $endsStatement = {
        param($idx)
        for ($q = $idx - 1; $q -ge 0; $q--) {
            $qk = "$($tokens[$q].Kind)"
            if ($qk -eq 'NewLine' -or $qk -eq 'Comment') { continue }
            if ('Pipe', 'Comma', 'Semi', 'AndAnd', 'OrOr', 'Dot', 'ColonColon', 'LBracket',
                'LParen', 'LCurly', 'AtParen', 'AtCurly', 'DollarParen' -contains $qk) { return $false }
            # '++' and '--' carry the UnaryOperator flag, but in postfix position
            # ('$i++', 'git checkout --') they close a statement like an operand.
            if ($qk -eq 'PlusPlus' -or $qk -eq 'MinusMinus') {
                if ($q -eq 0) { return $false }
                $rk = "$($tokens[$q - 1].Kind)"
                return -not ('Pipe', 'Comma', 'Semi', 'AndAnd', 'OrOr', 'NewLine', 'Dot', 'ColonColon',
                    'LBracket', 'LParen', 'LCurly', 'AtParen', 'AtCurly', 'DollarParen' -contains $rk)
            }
            # A bare command argument ('cd ..', 'git add *', 'git checkout -')
            # arrives as Generic yet keeps the operator flags of the punctuation
            # it resembles. It is an operand, so it does end the statement. A
            # real operator in expression position is never Generic ('-and' is
            # And, '+' is Plus, ',' Comma, '|' Pipe, '.' Dot).
            if ($qk -eq 'Generic') { return $true }
            $flags = $tokens[$q].TokenFlags
            foreach ($f in 'BinaryOperator', 'AssignmentOperator', 'UnaryOperator') {
                if ($flags -band [System.Management.Automation.Language.TokenFlags]::$f) { return $false }
            }
            return $true
        }
        return $false
    }

    # Locate the statement each operator belongs to: from the nearest ';' or
    # statement-ending newline on the left to the nearest one on the right,
    # measured at the operator's own depth, or the enclosing bracket. Operators
    # sharing a statement form one chain.
    $ranges = @{}
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $kind = "$($tokens[$i].Kind)"
        if ($kind -ne 'AndAnd' -and $kind -ne 'OrOr') { continue }
        $d = $depths[$i]

        $start = 0
        for ($j = $i - 1; $j -ge 0; $j--) {
            $k = "$($tokens[$j].Kind)"
            if ($depths[$j] -lt $d -or
                ($depths[$j] -eq $d -and ($k -eq 'Semi' -or
                 ($k -eq 'NewLine' -and (& $endsStatement $j))))) {
                $start = [Math]::Min($tokens[$j].Extent.EndOffset, $Line.Length)
                break
            }
        }

        # The EndOfInput token sits one past the end of the text (the tokenizer
        # appends a virtual newline), so cap every offset at the real length.
        $end = $Line.Length
        for ($j = $i + 1; $j -lt $tokens.Count; $j++) {
            $k = "$($tokens[$j].Kind)"
            if ($k -eq 'EndOfInput') { break }
            if ($depths[$j] -lt $d -or
                ($depths[$j] -eq $d -and ($k -eq 'Semi' -or
                 ($k -eq 'NewLine' -and (& $endsStatement $j))))) {
                $end = [Math]::Min($tokens[$j].Extent.StartOffset, $Line.Length)
                break
            }
        }

        $key = "$start-$end"
        if (-not $ranges.ContainsKey($key)) {
            $ranges[$key] = [pscustomobject]@{ Start = $start; End = $end; Ops = @(); Text = '' }
        }
        $ranges[$key].Ops += $i
    }
    if ($ranges.Count -eq 0) { return $Line }

    $groups = @($ranges.Values | Sort-Object Start)

    # Statements must not nest - a chain inside another chain's statement would
    # need its status probe to live in two places at once. Hand those back.
    for ($g = 1; $g -lt $groups.Count; $g++) {
        if ($groups[$g].Start -lt $groups[$g - 1].End) { return $Line }
    }

    # 'param(...)' has to stay the first statement of its block, so a chain
    # sharing a statement with it is not ours to touch.
    foreach ($grp in $groups) {
        $inParam = @($tokens | Where-Object {
            "$($_.Kind)" -eq 'Param' -and
            $_.Extent.StartOffset -ge $grp.Start -and $_.Extent.StartOffset -lt $grp.End
        }).Count -gt 0
        if ($inParam) { return $Line }
    }

    $comments = @($tokens | Where-Object { "$($_.Kind)" -eq 'Comment' })
    # The exit-code overrule exists for exactly one 5.1 quirk: a native command
    # whose *error stream* is redirected gets '$?' = False even when it exited
    # 0. So it may only apply to a segment that redirects the error stream and
    # has nothing downstream of it - the moment a pipeline follows, the failure
    # '$?' reports may be the downstream cmdlet's, and the exit code must not
    # speak for it.
    $redirs = @($tokens | Where-Object {
        "$($_.Kind)" -eq 'Redirection' -and ($_.Text.StartsWith('2>') -or $_.Text.StartsWith('*>'))
    })
    $pipes = @($tokens | Where-Object { "$($_.Kind)" -eq 'Pipe' })

    foreach ($grp in $groups) {
        # Cut the statement at its operators, keeping each piece's offsets.
        $segs   = New-Object 'System.Collections.Generic.List[string]'
        $bounds = New-Object 'System.Collections.Generic.List[object]'
        $p = $grp.Start
        foreach ($oi in $grp.Ops) {
            $segs.Add($Line.Substring($p, $tokens[$oi].Extent.StartOffset - $p))
            $bounds.Add(@($p, $tokens[$oi].Extent.StartOffset))
            $p = $tokens[$oi].Extent.EndOffset
        }
        $segs.Add($Line.Substring($p, $grp.End - $p))
        $bounds.Add(@($p, $grp.End))

        for ($s = 0; $s -lt $segs.Count; $s++) {
            # A branch holding nothing but a comment is as empty as a blank one
            # ('git add -A && # git commit'), and an empty branch ('a &&' or
            # '&& b') is a typo, not a chain.
            $bare = $segs[$s]
            foreach ($c in $comments) {
                if ($c.Extent.StartOffset -ge $bounds[$s][0] -and $c.Extent.EndOffset -le $bounds[$s][1]) {
                    $bare = $bare.Replace($c.Text, '')
                }
            }
            if ([string]::IsNullOrWhiteSpace($bare)) { return $Line }
            # A segment ending in a line-continuation backtick would escape the
            # separator appended after it and swallow it into the command's
            # arguments - parseable, but silently wrong.
            $ticks = [regex]::Match($segs[$s].Trim(), '`+$')
            if ($ticks.Success -and ($ticks.Length % 2) -eq 1) { return $Line }
        }

        # A trailing '#' comment swallows anything appended after it on the same
        # line, so a statement carrying one is rebuilt with newline separators.
        $hasComment = @($comments | Where-Object {
            $_.Extent.StartOffset -ge $grp.Start -and $_.Extent.EndOffset -le $grp.End
        }).Count -gt 0
        $sep = if ($hasComment) { "`n" } else { '; ' }
        $nl  = if ($hasComment) { "`n" } else { '' }

        # Keep the whitespace that hugged the statement, so a rewrite splices
        # back in as '{ ... }' rather than '{...}'.
        $lead = [regex]::Match($segs[0], '^\s*').Value
        $tail = [regex]::Match($segs[$segs.Count - 1], '\s*$').Value

        $captureFor = {
            param($s)
            $allow = ''
            foreach ($r in $redirs) {
                if ($r.Extent.StartOffset -ge $bounds[$s][0] -and $r.Extent.EndOffset -le $bounds[$s][1]) {
                    $allow = ' $true'
                    break
                }
            }
            foreach ($pipe in $pipes) {
                if ($pipe.Extent.StartOffset -ge $bounds[$s][0] -and $pipe.Extent.EndOffset -le $bounds[$s][1]) {
                    $allow = ''
                    break
                }
            }
            "`$__chain = __chainOk `$?$allow"
        }
        $capture = & $captureFor 0
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append($lead)
        [void]$sb.Append("__chainReset$sep")
        [void]$sb.Append($segs[0].Trim())
        [void]$sb.Append("$sep$capture")
        for ($n = 0; $n -lt $grp.Ops.Count; $n++) {
            $test = if ("$($tokens[$grp.Ops[$n]].Kind)" -eq 'AndAnd') { '$__chain' } else { '-not $__chain' }
            $body = $segs[$n + 1].Trim()
            # The last branch needs no probe - nobody reads its status, and
            # leaving it out keeps $LASTEXITCODE meaningful after the chain.
            if ($n -lt $grp.Ops.Count - 1) {
                $body = "__chainReset$sep$body$sep" + (& $captureFor ($n + 1))
            }
            [void]$sb.Append("$sep" + "if ($test) {$nl ")
            [void]$sb.Append($body)
            [void]$sb.Append("$nl }")
        }
        [void]$sb.Append($tail)
        $grp.Text = $sb.ToString()
    }

    # Splice the rewritten statements back into the untouched rest of the line.
    $out = New-Object System.Text.StringBuilder
    $cursor = 0
    foreach ($grp in $groups) {
        [void]$out.Append($Line.Substring($cursor, $grp.Start - $cursor))
        [void]$out.Append($grp.Text)
        $cursor = $grp.End
    }
    [void]$out.Append($Line.Substring($cursor))
    $result = $out.ToString()

    # Backstop: never hand back something that does not parse. This catches
    # contexts that take a single pipeline only, such as '(a && b)'.
    $rTokens = $null
    $rErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($result, [ref]$rTokens, [ref]$rErrors)
    if ($rErrors.Count -gt 0) { return $Line }

    return $result
}

# ---- Git Bash drive paths: /c/... -------------------------------------------
# Git Bash spells drive paths '/c/work/...', and so do commands copied from it
# (Claude Code's shell tool is Git Bash). PowerShell and native programs read
# that as '\c\work\...' on the current drive, so the Enter handler below
# rewrites the drive the way Git Bash does before starting a Windows program:
#     git -C /c/work/repo status   ->   git -C C:/work/repo status
#
# Only an argument (or the command itself) that starts with the path is
# rewritten - bare, quoted or after '--option=' - so '/c/' in the middle of a
# string, or in an expression such as "$p -replace '/c/', ...", is left alone.
# The letter must be followed by '/': a bare '/c' is how 'cmd /c', 'icacls /c'
# and other Windows switches are spelled, so it stays. Like the chain rewrite,
# this covers the interactive prompt only.
function Convert-GitBashPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Line
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$errors)

    $words = $ast.FindAll({
        param($node)
        $node.Parent -is [System.Management.Automation.Language.CommandAst] -and (
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -or
            $node -is [System.Management.Automation.Language.CommandParameterAst])
    }, $true)

    foreach ($word in $words) {
        $m = [regex]::Match($word.Extent.Text, '^[''"]?(?:-[\w.-]+=[''"]?)?/(?<drive>[a-zA-Z])/')
        if (-not $m.Success) { continue }
        # '/c' and 'C:' have the same length, so the offsets of the words still
        # to visit stay valid.
        $at   = $word.Extent.StartOffset + $m.Groups['drive'].Index - 1
        $Line = $Line.Remove($at, 2).Insert($at, $m.Groups['drive'].Value.ToUpperInvariant() + ':')
    }
    return $Line
}

# Enter: rewrite chain operators and Git Bash paths, then submit as usual.
# The rewrite is applied to the visible buffer, so what runs is what you see
# (and what lands in history). Anything that fails to convert is submitted
# untouched.
if ('Microsoft.PowerShell.PSConsoleReadLine' -as [type]) {
    Set-PSReadLineKeyHandler -Chord Enter `
        -BriefDescription 'AcceptLineWithBashSyntax' `
        -Description "Rewrite '&&', '||' and Git Bash paths (/c/...) into Windows PowerShell syntax, then accept the line" `
        -ScriptBlock {
            $line   = $null
            $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            try {
                $rewritten = $line
                if ($rewritten -match '&&|\|\|')   { $rewritten = Convert-ChainOperator $rewritten }
                if ($rewritten -match '/[a-zA-Z]/') { $rewritten = Convert-GitBashPath $rewritten }
                if ($rewritten -cne $line) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $rewritten)
                }
            } catch {
                # Never let a rewrite bug break the Enter key.
            }
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
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

# ---- Claude Code: default to "ultracode" mode ----
# Ultracode = xhigh effort + standing dynamic-workflow orchestration. It is
# session-scoped: Claude Code ignores "ultracode" from persisted settings.json
# by design, so it cannot be made a permanent default there. The supported way
# to turn it on at launch is --settings, so we shadow `claude` to inject it.
#   Run a normal (non-ultracode) session instead: claude.exe ...
function claude {
    & "$env:USERPROFILE\.local\bin\claude.exe" --settings "$env:USERPROFILE\.claude\ultracode.settings.json" @args
}
