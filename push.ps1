#Requires -Version 5.1
<#
.SYNOPSIS
    Wine Manager – One-Click Git Push (Entwickler-Seite)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step { param($msg) Write-Host "`n[*] $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!]  $msg" -ForegroundColor Yellow }
function Exit-WithError {
    param($msg)
    Write-Host "`n[FEHLER] $msg" -ForegroundColor Red
    Write-Host "`nFenster schliessen mit einer beliebigen Taste..." -ForegroundColor Red
    exit 1
}

Clear-Host
Write-Host "  Wine Manager – Git Push`n" -ForegroundColor Cyan

Write-Step "Prüfe Git-Repository..."
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Exit-WithError "Git nicht gefunden."
}
if (-not (Test-Path (Join-Path $ProjectRoot ".git"))) {
    Exit-WithError "Kein Git-Repository in $ProjectRoot gefunden."
}
Push-Location $ProjectRoot

try {
    Write-Step "Aktueller Git-Status:"
    git status --short
    $statusOutput = git status --porcelain

    if ([string]::IsNullOrWhiteSpace($statusOutput)) {
        Write-Warn "Keine lokalen Änderungen vorhanden."
        $pushAnyway = Read-Host "`n  Trotzdem pushen? [j/N]"
        if ($pushAnyway -notin @("j", "J", "y", "Y")) {
            Write-Host "Abgebrochen." -ForegroundColor Yellow
            exit 0
        }
    } else {
        Write-Step "Commit-Nachricht eingeben:"
        $commitMsg = Read-Host "  Nachricht"
        if ([string]::IsNullOrWhiteSpace($commitMsg)) {
            Exit-WithError "Leere Commit-Nachricht. Abgebrochen."
        }

        Write-Step "Commit erstellen..."
        git add -A
        git commit -m $commitMsg
        if ($LASTEXITCODE -ne 0) { Exit-WithError "git commit fehlgeschlagen." }
        Write-OK "Commit erstellt."
    }

    Write-Step "Pushe zu GitHub..."
    git push
    if ($LASTEXITCODE -ne 0) { Exit-WithError "git push fehlgeschlagen." }

    $branch     = git rev-parse --abbrev-ref HEAD
    $commitHash = git rev-parse --short HEAD
    $remote     = git remote get-url origin

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Push erfolgreich!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Branch:  $branch" -ForegroundColor White
    Write-Host "  Commit:  $commitHash" -ForegroundColor White
    Write-Host "  Remote:  $remote" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Umbrel Update: ssh umbrel@192.168.10.147 'bash ~/docker/wine-docker-manager/scripts/server/update.sh'" -ForegroundColor Yellow
    Write-Host ""

} finally {
    Pop-Location
}
