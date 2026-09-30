# Regression suite for the '&&' / '||' rewriter in
# Microsoft.PowerShell_profile.ps1 (Convert-ChainOperator + the Enter handler).
# Run it after touching that section:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Microsoft.PowerShell_profile.Tests.ps1
# Every case below is either a shape the rewriter must produce, a line it must
# refuse to touch, or a runtime behaviour that has to match sh.

. "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" 6>$null | Out-Null
Clear-Host
$script:pass = 0; $script:fail = 0

function T($name, $expected, $actual) {
    if ("$expected" -eq "$actual") { $script:pass++; Write-Host "  ok   $name" -ForegroundColor DarkGreen }
    else { $script:fail++; Write-Host "  FAIL $name`n       expected: <$expected>`n       actual:   <$actual>" -ForegroundColor Red }
}
function Run($src) {
    $c = Convert-ChainOperator $src
    (Invoke-Expression $c | Out-String).Trim() -replace "`r`n", '|'
}
function Shape($src) { (Convert-ChainOperator $src) -replace "`n", '<NL>' }
function Same($src) { (Convert-ChainOperator $src) -eq $src }
$BT = [string][char]96   # backtick

Write-Host "== left alone ==" -ForegroundColor Cyan
T 'plain line'        'echo hi'                     (Convert-ChainOperator 'echo hi')
T 'empty'             ''                            (Convert-ChainOperator '')
T 'whitespace'        '   '                         (Convert-ChainOperator '   ')
T '&& in "string"'    'echo "a && b"'               (Convert-ChainOperator 'echo "a && b"')
T "&& in 'string'"    "echo 'a || b'"               (Convert-ChainOperator "echo 'a || b'")
T 'lone &'            '& { 1 }'                     (Convert-ChainOperator '& { 1 }')
T 'stop-parsing --%'  'cmd --% /c echo a && b'      (Convert-ChainOperator 'cmd --% /c echo a && b')
T 'trailing &&'       'a &&'                        (Convert-ChainOperator 'a &&')
T 'leading &&'        '&& a'                        (Convert-ChainOperator '&& a')
T 'trailing backtick' "echo one && echo two $BT"    (Convert-ChainOperator "echo one && echo two $BT")
T 'mid backtick'      "echo one $BT && echo two"    (Convert-ChainOperator "echo one $BT && echo two")
T 'paren group'       '(a && b)'                    (Convert-ChainOperator '(a && b)')
T 'nested depths'     '@() | ForEach-Object { a && b } && c' (Convert-ChainOperator '@() | ForEach-Object { a && b } && c')

Write-Host "== rewrite shape ==" -ForegroundColor Cyan
T 'simple &&' '__chainReset; a; $__chain = __chainOk $?; if ($__chain) { b }'  (Convert-ChainOperator 'a && b')
T 'simple ||' '__chainReset; a; $__chain = __chainOk $?; if (-not $__chain) { b }' (Convert-ChainOperator 'a || b')
T 'mixed' '__chainReset; a; $__chain = __chainOk $?; if ($__chain) { __chainReset; b; $__chain = __chainOk $? }; if (-not $__chain) { c }' (Convert-ChainOperator 'a && b || c')
T 'semicolon tail stays out' '__chainReset; a; $__chain = __chainOk $?; if ($__chain) { b }; c' (Convert-ChainOperator 'a && b; c')
T 'two chains, one line' '__chainReset; a; $__chain = __chainOk $?; if ($__chain) { b }; __chainReset; c; $__chain = __chainOk $?; if ($__chain) { d }' (Convert-ChainOperator 'a && b; c && d')
T 'else stays attached' 'if (x) { __chainReset; a; $__chain = __chainOk $?; if ($__chain) { b } } else { c }' (Convert-ChainOperator 'if (x) { a && b } else { c }')

Write-Host "== runtime: basics ==" -ForegroundColor Cyan
T '&& skips on failure'  ''          (Run 'cmd /c "exit 1" && echo NOPE')
T '&& runs on success'   'YES'       (Run 'cmd /c "exit 0" && echo YES')
T '|| runs on failure'   'YES'       (Run 'cmd /c "exit 1" || echo YES')
T '|| skips on success'  ''          (Run 'cmd /c "exit 0" || echo NOPE')
T 'left-assoc (a&&b)||c' 'FALLBACK'  (Run 'cmd /c "exit 0" && cmd /c "exit 1" || echo FALLBACK')
T 'left-assoc (a||b)&&c' 'OK'        (Run 'cmd /c "exit 1" || cmd /c "exit 0" && echo OK')
T 'three-deep &&'        'C'         (Run 'cmd /c "exit 0" && cmd /c "exit 0" && echo C')
T 'break in middle'      ''          (Run 'cmd /c "exit 0" && cmd /c "exit 1" && echo NOPE')
T 'cmdlet failure -> ||' 'RECOVER'   (Run 'Get-Item C:\nope-nope -ErrorAction SilentlyContinue || echo RECOVER')
T 'pipeline as segment'  'piped'     (Run 'Get-Process -Id $PID | Out-Null && echo piped')
T 'quoted || is an arg'  'x || y|done' (Run "echo 'x || y' && echo done")
T 'comment survives'     'one|two'   (Run 'echo one && echo two # trailing')
T 'no scope isolation'   '2'         (Run '$script:q = 1 && $script:q = 2; $script:q')
T 'cd persists'          'C:\Windows' (Run 'Push-Location C:\Windows && $PWD.Path')
Pop-Location

Write-Host "== runtime: findings from review ==" -ForegroundColor Cyan
T 'F1 ; tail unconditional'    'c'   (Run 'cmd /c "exit 1" && echo b; echo c')
T 'F1 two independent chains'  'c|d' (Run 'cmd /c "exit 1" && echo b; echo c && echo d')
T 'F2 else runs (false)'       'no'  (Run 'if ($false) { echo yes && echo more } else { echo no }')
T 'F2 if runs (true)'          'yes|more' (Run 'if ($true) { echo yes && echo more } else { echo no }')
T 'F2 elseif keeps branch'     'z'   (Run 'if ($false) { echo x && echo y } elseif ($true) { echo z }')
T 'F3 switch default kept'     'd'   (Run 'switch (2) { 1 { echo a && echo b } default { echo d } }')
T 'F3 switch clause runs'      'a|b' (Run 'switch (1) { 1 { echo a && echo b } default { echo d } }')
T 'F5 newline ends the chain'  'c'   (Run "cmd /c `"exit 1`" && echo b`necho c")
T 'F7 redirected stderr'       'NEXT' (Run 'cmd /c "echo oops 1>&2 & exit 0" 2>$null && echo NEXT')
T 'F7 redirect, real failure'  'GONE' (Run 'cmd /c "echo oops 1>&2 & exit 4" 2>$null || echo GONE')

Write-Host "== runtime: `$LASTEXITCODE ==" -ForegroundColor Cyan
T 'exit code kept on skip'  '7' (Run 'cmd /c "exit 7" || $LASTEXITCODE')
T 'exit code of last seg'   '3' (Run 'cmd /c "exit 0" && cmd /c "exit 3"; $LASTEXITCODE')
$global:LASTEXITCODE = $null
cmd /c "exit 9" | Out-Null
T 'cmdlet chain keeps old code' 'ok|9' (Run 'Test-Path C:\ | Out-Null && echo ok; $LASTEXITCODE')
T 'subexpression chain'     'x' (Run 'echo $(cmd /c "exit 0" && echo x)')

Write-Host "== compound statements keep their trailing clause ==" -ForegroundColor Cyan
T 'do..while runs twice'   'a|b|a|b' (Run '$n = 0; do { echo a && echo b; $n++ } while ($n -lt 2)')
T 'do..until'              'a|b'     (Run '$n = 0; do { echo a && echo b; $n++ } until ($n -ge 1)')
T 'try/catch/finally'      'a|b|fin' (Run 'try { echo a && echo b } catch { echo caught } finally { echo fin }')
T 'catch branch reached'   'caught|also|fin' (Run 'try { throw "x" } catch { echo caught && echo also } finally { echo fin }')
T 'while loop'             'a|b'     (Run '$n = 0; while ($n -lt 1) { echo a && echo b; $n++ }')
T 'for loop with ; in ()'  'a|b'     (Run 'for ($i = 0; $i -lt 1; $i++) { echo a && echo b }')
T 'hashtable ; stays put'  'ok'      (Run '$h = @{ a = 1; b = 2 } && echo ok')
T 'hashtable count'        '2'       (Run '$h = @{ a = 1; b = 2 } && $h.Count')
T 'array subexpression'    '1|2|x'   (Run 'echo @(1, 2) && echo x')
T 'scriptblock argument'   'in|out'  (Run '1 | ForEach-Object { echo in } && echo out')
T 'chain after block'      'ok'      (Run 'if ($true) { $null } && echo ok')
T 'nested two levels'      'deep|d2' (Run 'if ($true) { if ($true) { echo deep && echo d2 } }')

Write-Host "== these must be left alone ==" -ForegroundColor Cyan
T 'literal --% arg'  'foo --% && bar'      (Shape 'foo --% && bar')
T 'chain in chain'   'a && (b) && $(c && d)' (Shape 'a && (b) && $(c && d)')

Write-Host "== re-running a rewritten line is stable ==" -ForegroundColor Cyan
$once  = Convert-ChainOperator 'cmd /c "exit 0" && echo hi'
$twice = Convert-ChainOperator $once
T 'idempotent' $once $twice
T 'rerun works' 'hi' ((Invoke-Expression $twice | Out-String).Trim())

# PowerShell itself reports $? = False for 'native-fail | cmdlet', so the chain
# stops. That is what PowerShell 7's native && does too; bash would differ.
Write-Host "== pipeline status source ==" -ForegroundColor Cyan
T 'failing native in pipeline stops' '' (Run 'cmd /c "exit 1" | Out-String | Out-Null && echo NOPE')
T 'ok native in pipeline continues' 'RAN' (Run 'cmd /c "exit 0" | Out-String | Out-Null && echo RAN')

Write-Host "== R1/R7 newline after '|' is a continuation, not a boundary ==" -ForegroundColor Cyan
T 'multi-line pipeline'  'HELLO|done' (Run "Write-Output hello |`nForEach-Object { `$_.ToUpper() } && Write-Output done")
T 'chain then pipe'      'a|B'        (Run "Write-Output a && Write-Output b |`nForEach-Object { `$_.ToUpper() }")
T 'multi-line with ||'   'none'       (Run "cmd /c `"exit 1`" |`nOut-Null || Write-Output none")
T 'inside a block'       'HELLO|done' (Run "if (`$true) {`n Write-Output hello |`n ForEach-Object { `$_.ToUpper() } && Write-Output done`n}")

Write-Host "== R2 ',' and '=' continuations ==" -ForegroundColor Cyan
T 'assignment split'  'x|5'     (Run "`$script:aa =`n5 && Write-Output x; `$script:aa")
T 'comma split'       'a|b|x'   (Run "Write-Output a,`nb && Write-Output x")

Write-Host "== a real newline still ends a statement ==" -ForegroundColor Cyan
T 'plain newline'     'c'       (Run "cmd /c `"exit 1`" && Write-Output b`nWrite-Output c")
T 'newline after }'   'z'       (Run "if (`$false) { Write-Output q }`ncmd /c `"exit 0`" && Write-Output z")

Write-Host "== R3 param blocks are left alone ==" -ForegroundColor Cyan
T 'scriptblock param' $true (Same '$s = { param($p) cmd /c "exit 0" && Write-Output "got:$p" }; & $s HELLO')
T 'function param'    $true (Same 'function f { param($x = 1) git a && git b }')

Write-Host "== R4 a native command inside a function does not decide the chain ==" -ForegroundColor Cyan
function Get-Br { $b = cmd /c "exit 1"; if (-not $b) { $b = 'HEAD' }; Write-Output $b }
T 'wrapper function recovers' 'HEAD|CHAIN-RAN' (Run 'Get-Br && Write-Output CHAIN-RAN')

Write-Host "== R5 nested chains keep the outer exit code ==" -ForegroundColor Cyan
Invoke-Expression "function Note { $(Convert-ChainOperator 'Write-Output a && Write-Output b') }"
cmd /c "exit 7"
T 'nested chain' 'a|b|CHAIN-RAN|7' (Run 'Note && Write-Output CHAIN-RAN; $LASTEXITCODE')

Write-Host "== R6 prompt puts back a stranded exit code ==" -ForegroundColor Cyan
$global:LASTEXITCODE = $null
$global:__chainStack = New-Object 'System.Collections.Generic.List[object]'
$global:__chainStack.Add(42)
$null = prompt 6>$null
T 'stranded value restored' '42' "$global:LASTEXITCODE"
T 'stack drained'           '0'  "$($global:__chainStack.Count)"

Write-Host "== R8 a comment-only branch is an empty branch ==" -ForegroundColor Cyan
T 'commented-out rhs'  $true (Same 'Get-Item a.txt && # Get-Item b.txt')
T 'real comment still ok' 'one|two' (Run 'Write-Output one && Write-Output two # note')


Write-Host "== V1 postfix ++ / -- do end a statement ==" -ForegroundColor Cyan
T 'newline after ++'  'TAIL' (Run "cmd /c `"exit 1`" && `$global:i++`nWrite-Output TAIL")
T 'newline after --'  'TAIL' (Run "cmd /c `"exit 1`" && `$global:n--`nWrite-Output TAIL")
T 'newline after bare --' 'TAIL' (Run "cmd /c `"exit 1`" && cmd /c `"exit 0`" --`nWrite-Output TAIL")
T '++ still runs on success' 'TAIL' (Run "cmd /c `"exit 0`" && `$global:i++`nWrite-Output TAIL")

Write-Host "== V2 '.' and '::' continue a statement ==" -ForegroundColor Cyan
T 'member access split' 'x|3' (Run "`$global:sx = `"abc`".`nLength && Write-Output x; `$global:sx")
T 'static member split' 'x|2147483647' (Run "`$global:vv = [int]::`nMaxValue && Write-Output x; `$global:vv")

Write-Host "== V3 a successful native does not rescue a failed cmdlet ==" -ForegroundColor Cyan
T 'cmdlet failure stops &&' '' (Run 'cmd /c "echo nope-nope" | Get-Item -ErrorAction SilentlyContinue && Write-Output RAN-ANYWAY')
T 'cmdlet failure fires ||' 'RECOVER' (Run 'cmd /c "echo nope-nope" | Get-Item -ErrorAction SilentlyContinue || Write-Output RECOVER')
T 'redirect rescue still works' 'NEXT' (Run 'cmd /c "echo oops 1>&2 & exit 0" 2>$null && Write-Output NEXT')
T 'redirect real failure' 'GONE' (Run 'cmd /c "echo oops 1>&2 & exit 4" 2>$null || Write-Output GONE')

Write-Host "== V4 exit code 0 survives a cmdlet-only chain ==" -ForegroundColor Cyan
cmd /c "exit 0"
T 'zero preserved' 'ok|0' (Run 'Test-Path C:\ | Out-Null && Write-Output ok; $LASTEXITCODE')
T 'stack drained'  '0'    "$($global:__chainStack.Count)"

Write-Host "== V5 prompt restores any stranded value ==" -ForegroundColor Cyan
foreach ($v in 42, 0, 1) {
    $global:LASTEXITCODE = $null
    $global:__chainStack.Clear()
    $global:__chainStack.Add($v)
    $null = prompt 6>$null
    T "stranded $v restored" "$v" "$global:LASTEXITCODE"
    T "stack drained after $v" '0' "$($global:__chainStack.Count)"
}

Write-Host "== V7 Set-StrictMode does not break the prompt ==" -ForegroundColor Cyan
$strict = powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-StrictMode -Version Latest; . '$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1' *>`$null; try { `$null = prompt 6>`$null; `$null = Convert-ChainOperator 'a && b'; 'CLEAN' } catch { 'THREW: ' + `$_ }" 2>&1
T 'strict mode clean' 'CLEAN' ("$strict".Trim())

Write-Host "== W1 a bare argument ends the statement ==" -ForegroundColor Cyan
Push-Location C:\Windows
T "trailing .. (cd ..)"   'TAIL' (Run "cmd /c `"exit 1`" && cd ..`nWrite-Output TAIL")
T 'trailing * (git add *)' 'TAIL' (Run "cmd /c `"exit 1`" && Write-Output *`nWrite-Output TAIL")
T 'trailing - (checkout -)' 'TAIL' (Run "cmd /c `"exit 1`" && Write-Output -`nWrite-Output TAIL")
T 'second chain stays free' 'A|B' (Run "cmd /c `"exit 1`" && cd ..`nWrite-Output A && Write-Output B")
T 'inside a block'        'TAIL' (Run "if (`$true) {`n cmd /c `"exit 1`" && cd ..`n Write-Output TAIL`n}")
Pop-Location
T 'real operator still continues' 'x|5' (Run "`$global:zz = 2 +`n3 && Write-Output x; `$global:zz")

Write-Host "== W2/W3 the redirect rescue does not cover a downstream cmdlet ==" -ForegroundColor Cyan
$tmp = Join-Path $env:TEMP 'chain-w2'
T 'pipeline after redirect stops &&' '' (Run "cmd /c `"echo x`" 2>`$null | Get-Item -ErrorAction SilentlyContinue && Write-Output NOPE")
T 'pipeline after redirect fires ||' 'RECOVER' (Run "cmd /c `"echo x`" 2>`$null | Get-Item -ErrorAction SilentlyContinue || Write-Output RECOVER")
T 'single redirect still rescued'    'NEXT' (Run 'cmd /c "echo oops 1>&2 & exit 0" 2>$null && Write-Output NEXT')
T 'single redirect real failure'     'GONE' (Run 'cmd /c "echo oops 1>&2 & exit 4" 2>$null || Write-Output GONE')
# The rescue is opt-in per segment; assert on the emitted contract, because the
# runtime result of an exotic shape is PowerShell's own business.
function Rescued($src) { (Convert-ChainOperator $src) -like '*__chainOk $? $true*' }
T 'error redirect opts in'       $true  (Rescued 'git fetch 2>$null && git merge')
T 'stdout redirect does not'     $false (Rescued 'cmd /c "x" > out.txt && Write-Output y')
T 'redirect + pipeline does not' $false (Rescued 'git fetch 2>$null | Set-Content x && Write-Output y')
T 'plain segment does not'       $false (Rescued 'git fetch && git merge')
Write-Host ""
Write-Host "$script:pass passed, $script:fail failed" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail) { exit 1 }
