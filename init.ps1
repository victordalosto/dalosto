# init.ps1 - bootstrap the whole repo: Keys.exe autostart, VSCode config, PowerShell profile + Terminal shortcuts.
# Run from any shell:  powershell -ExecutionPolicy Bypass -File .\init.ps1
# Flags: -DryRun previews without writing. -Force overwrites without comparing/backing up.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$psSrcDir = Join-Path $repoRoot 'WindowsPowerShell'

# Target paths
$profilePath   = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$terminalPath  = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$startupDir    = [Environment]::GetFolderPath('Startup')
$vscodeUserDir = Join-Path $env:APPDATA 'Code\User'

$script:Failures = @()

function Write-Step($label, $msg, $color = 'Gray') {
    Write-Host ("  {0,-5} {1}" -f $label, $msg) -ForegroundColor $color
}

function Write-Section($title) {
    Write-Host "`n[$title]" -ForegroundColor Cyan
}

function Invoke-Step($stepName, [scriptblock]$body) {
    try {
        & $body
    } catch {
        $script:Failures += $stepName
        Write-Step 'FAIL' ("{0}: {1}" -f $stepName, $_.Exception.Message) 'Red'
    }
}

function Ensure-Directory($path) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        Write-Step 'MKDIR' $dir 'DarkGray'
        if (-not $DryRun) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
}

function Backup-File($path) {
    if (-not (Test-Path $path)) { return }
    $backup = "$path.bak"
    Write-Step 'BACK' "$path -> $backup" 'DarkGray'
    if (-not $DryRun) { Copy-Item $path $backup -Force }
}

# Copy a file with hash-skip and backup-on-overwrite. Returns $true if a write happened (or would in DryRun).
function Copy-IfChanged($src, $dest, $label) {
    if (-not (Test-Path $src)) {
        Write-Step 'SKIP' "${label}: source missing ($src)" 'Yellow'
        return $false
    }
    Ensure-Directory $dest
    if ((Test-Path $dest) -and -not $Force) {
        if ((Get-FileHash $src).Hash -eq (Get-FileHash $dest).Hash) {
            Write-Step 'OK' "$label (already up to date)" 'DarkGreen'
            return $false
        }
        Backup-File $dest
    }
    Write-Step 'COPY' "$label -> $dest" 'Green'
    if (-not $DryRun) { Copy-Item $src $dest -Force }
    return $true
}

# --- 1. Keys.exe autostart -------------------------------------------------
# Drop a Startup-folder shortcut pointing at the in-repo Keys.exe so it launches on login.
# Shortcut > copy: updates to the source binary take effect with no redeploy, and the user
# can disable autostart by deleting the .lnk without touching the repo.
function Install-KeysAutostart {
    $src = Join-Path $repoRoot 'Keys.exe'
    if (-not (Test-Path $src)) {
        Write-Step 'SKIP' "Keys.exe not found at $src" 'Yellow'
        return
    }
    if (-not (Test-Path $startupDir)) {
        Write-Step 'SKIP' "Startup folder missing ($startupDir)" 'Yellow'
        return
    }

    $shortcutPath = Join-Path $startupDir 'Keys.lnk'
    $workingDir   = Split-Path -Parent $src

    if ((Test-Path $shortcutPath) -and -not $Force) {
        try {
            $existing = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
            if ($existing.TargetPath -eq $src -and $existing.WorkingDirectory -eq $workingDir) {
                Write-Step 'OK' 'Keys.exe autostart (already configured)' 'DarkGreen'
                return
            }
        } catch {
            # Unreadable shortcut - fall through and recreate.
        }
        Backup-File $shortcutPath
    }

    Write-Step 'LINK' "Keys.exe autostart -> $shortcutPath" 'Green'
    if (-not $DryRun) {
        $shell = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath       = $src
            $shortcut.WorkingDirectory = $workingDir
            $shortcut.Description      = 'AutoHotkey hotkeys (Dalosto dotfiles)'
            $shortcut.WindowStyle      = 7  # minimized
            $shortcut.Save()
        } finally {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        }
    }
}

# --- 2. VSCode user settings ----------------------------------------------
# Only deploy when VSCode is installed (its user dir exists). Otherwise skip silently -
# this script also runs on machines that don't have VSCode.
function Deploy-VSCodeConfig {
    $srcDir = Join-Path $repoRoot 'vscode'
    if (-not (Test-Path $srcDir)) {
        Write-Step 'SKIP' "VSCode source dir missing ($srcDir)" 'Yellow'
        return
    }
    if (-not (Test-Path $vscodeUserDir)) {
        Write-Step 'SKIP' "VSCode not installed (no $vscodeUserDir)" 'Yellow'
        return
    }

    foreach ($name in @('settings.json', 'keybindings.json')) {
        Invoke-Step "VSCode/$name" {
            Copy-IfChanged (Join-Path $srcDir $name) (Join-Path $vscodeUserDir $name) "VSCode $name" | Out-Null
        }
    }
}

# --- 3. PowerShell profile -------------------------------------------------
function Deploy-PowerShellProfile {
    Copy-IfChanged (Join-Path $psSrcDir 'Microsoft.PowerShell_profile.ps1') $profilePath 'PowerShell profile' | Out-Null
}

# --- 4. Windows Terminal shortcuts ----------------------------------------
# Merge shortcut.json's `actions` and `keybindings` into Windows Terminal's settings.json.
# Match `actions` by `id`, `keybindings` by `keys` - existing entries with the same key get replaced.
function Merge-Array($existing, $incoming, $matchProperty) {
    $existing = @($existing)
    foreach ($item in $incoming) {
        $key = $item.$matchProperty
        $existing = @($existing | Where-Object { $_.$matchProperty -ne $key })
        $existing += $item
    }
    return ,$existing
}

function Deploy-TerminalShortcuts {
    $src = Join-Path $psSrcDir 'shortcut.json'
    if (-not (Test-Path $src)) {
        Write-Step 'SKIP' "Terminal shortcuts: source missing ($src)" 'Yellow'
        return
    }
    if (-not (Test-Path $terminalPath)) {
        Write-Step 'SKIP' "Terminal settings.json not found at $terminalPath (open Windows Terminal once to create it)" 'Yellow'
        return
    }

    $shortcut = Get-Content $src          -Raw | ConvertFrom-Json
    $settings = Get-Content $terminalPath -Raw | ConvertFrom-Json

    if ($shortcut.PSObject.Properties['actions']) {
        $merged = Merge-Array $settings.actions $shortcut.actions 'id'
        $settings | Add-Member -NotePropertyName 'actions' -NotePropertyValue $merged -Force
    }
    if ($shortcut.PSObject.Properties['keybindings']) {
        $merged = Merge-Array $settings.keybindings $shortcut.keybindings 'keys'
        $settings | Add-Member -NotePropertyName 'keybindings' -NotePropertyValue $merged -Force
    }

    $newJson = $settings | ConvertTo-Json -Depth 100

    if (-not $Force) {
        # Compare normalized content - both serialized through ConvertTo-Json for fair comparison.
        $currentNormalized = (Get-Content $terminalPath -Raw | ConvertFrom-Json) | ConvertTo-Json -Depth 100
        if ($currentNormalized -eq $newJson) {
            Write-Step 'OK' 'Terminal shortcuts (already merged)' 'DarkGreen'
            return
        }
        Backup-File $terminalPath
    }

    Write-Step 'MERGE' "Terminal shortcuts -> $terminalPath" 'Green'
    if (-not $DryRun) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($terminalPath, $newJson, $utf8NoBom)
    }
}

# --- Main ------------------------------------------------------------------
if ($DryRun) { Write-Host "DRY RUN - no files will be written.`n" -ForegroundColor Cyan }
Write-Host "Bootstrapping from: $repoRoot"

Write-Section 'Keys.exe autostart'
Invoke-Step 'Keys autostart'      { Install-KeysAutostart }

Write-Section 'VSCode'
Invoke-Step 'VSCode config'       { Deploy-VSCodeConfig }

Write-Section 'PowerShell'
Invoke-Step 'PowerShell profile'  { Deploy-PowerShellProfile }
Invoke-Step 'Terminal shortcuts'  { Deploy-TerminalShortcuts }

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host ("Done with {0} failure(s): {1}" -f $script:Failures.Count, ($script:Failures -join ', ')) -ForegroundColor Red
    exit 1
}
Write-Host 'Done.' -ForegroundColor Cyan
if (-not $DryRun) {
    Write-Host 'Restart Windows Terminal and reload your PowerShell session to apply changes.'
}
