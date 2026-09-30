# init.ps1 — deploy dotfiles from this directory to their system locations.
# Run from any shell:  powershell -ExecutionPolicy Bypass -File .\init.ps1
# Use -DryRun to preview without writing. Use -Force to overwrite without prompting.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$profilePath  = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$terminalPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'

function Write-Step($label, $msg, $color = 'Gray') {
    Write-Host ("  {0,-5} {1}" -f $label, $msg) -ForegroundColor $color
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

# Copy the PowerShell profile verbatim.
function Deploy-PowerShellProfile {
    $src = Join-Path $here 'Microsoft.PowerShell_profile.ps1'
    if (-not (Test-Path $src)) {
        Write-Step 'SKIP' "PowerShell profile: source missing ($src)" 'Yellow'
        return
    }

    Ensure-Directory $profilePath

    if ((Test-Path $profilePath) -and -not $Force) {
        if ((Get-FileHash $src).Hash -eq (Get-FileHash $profilePath).Hash) {
            Write-Step 'OK' 'PowerShell profile (already up to date)' 'DarkGreen'
            return
        }
        Backup-File $profilePath
    }

    Write-Step 'COPY' "PowerShell profile -> $profilePath" 'Green'
    if (-not $DryRun) { Copy-Item $src $profilePath -Force }
}

# Merge shortcut.json's `actions` and `keybindings` into Windows Terminal's settings.json.
# Match `actions` by `id`, `keybindings` by `keys` — existing entries with the same key get replaced.
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
    $src = Join-Path $here 'shortcut.json'
    if (-not (Test-Path $src)) {
        Write-Step 'SKIP' "Terminal shortcuts: source missing ($src)" 'Yellow'
        return
    }
    if (-not (Test-Path $terminalPath)) {
        Write-Step 'SKIP' "Terminal settings.json not found at $terminalPath (open Windows Terminal once to create it)" 'Yellow'
        return
    }

    $shortcut = Get-Content $src           -Raw | ConvertFrom-Json
    $settings = Get-Content $terminalPath  -Raw | ConvertFrom-Json

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
        $currentJson = Get-Content $terminalPath -Raw
        # Compare normalized content — both serialized through ConvertTo-Json for fair comparison.
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

if ($DryRun) { Write-Host "DRY RUN — no files will be written.`n" -ForegroundColor Cyan }
Write-Host "Deploying dotfiles from: $here`n"

Deploy-PowerShellProfile
Deploy-TerminalShortcuts

Write-Host "`nDone." -ForegroundColor Cyan
if (-not $DryRun) {
    Write-Host "Restart Windows Terminal and reload your PowerShell session to apply changes."
}
