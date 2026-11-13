# Guitar Quest - creates a desktop shortcut on Windows.
# The shortcut opens Edge (or Chrome) in "app window" mode: no address bar or tabs, its own icon, and a separate
# browser profile, so progress and stars are kept in %LOCALAPPDATA%\GuitarQuest\browser.
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\create_shortcut.ps1 [-Target <folder>]
param([string]$Target = [Environment]::GetFolderPath('Desktop'))

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$index = Join-Path $project 'index.html'
$icon = Join-Path $project 'img\guitarquest.ico'
if (-not (Test-Path $index)) { throw "index.html not found: $index" }

$candidates = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$browser = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

$wsh = New-Object -ComObject WScript.Shell
$lnk = $wsh.CreateShortcut((Join-Path $Target 'Guitar Quest.lnk'))
if ($browser) {
    $url = ([System.Uri]$index).AbsoluteUri          # spaces become %20
    $profileDir = Join-Path $env:LOCALAPPDATA 'GuitarQuest\browser'
    $lnk.TargetPath = $browser
    $lnk.Arguments = "--app=`"$url`" --user-data-dir=`"$profileDir`" --start-maximized --no-first-run --no-default-browser-check"
} else {
    # No Edge/Chrome found: open index.html in the default browser
    $lnk.TargetPath = $index
}
$lnk.WorkingDirectory = $project
$lnk.IconLocation = "$icon,0"
$lnk.Description = 'Guitar Quest - learn guitar notes, scales and chords'
$lnk.Save()
Write-Host ''
Write-Host "  Shortcut created: $(Join-Path $Target 'Guitar Quest.lnk')" -ForegroundColor Green
