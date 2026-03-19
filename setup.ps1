#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Wine Manager — Setup und Start
#>

Write-Host ""
Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       Wine Manager — Setup           ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Docker prüfen
try {
    docker info | Out-Null
} catch {
    Write-Error "Docker ist nicht erreichbar. Bitte Docker Desktop starten."
    exit 1
}

# USB-Hinweis für Windows-Hosts
Write-Host "HINWEIS: Für USB-Hardware auf Windows-Hosts:" -ForegroundColor Yellow
Write-Host "  winget install usbipd" -ForegroundColor Gray
Write-Host "  usbipd list" -ForegroundColor Gray
Write-Host "  usbipd bind --busid <ID>" -ForegroundColor Gray
Write-Host "  usbipd attach --wsl --busid <ID>" -ForegroundColor Gray
Write-Host ""

# Build
Write-Host "[1/3] Baue Docker-Images..." -ForegroundColor Green
docker compose build
if ($LASTEXITCODE -ne 0) { Write-Error "Build fehlgeschlagen"; exit 1 }

# Start
Write-Host "[2/3] Starte Dienste..." -ForegroundColor Green
docker compose up -d
if ($LASTEXITCODE -ne 0) { Write-Error "Start fehlgeschlagen"; exit 1 }

# Warten
Write-Host "[3/3] Warte auf Wine-Initialisierung (30s)..." -ForegroundColor Green
Start-Sleep 30

Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " Wine Manager läuft!" -ForegroundColor Green
Write-Host ""
Write-Host " App-Manager:  http://localhost:3000" -ForegroundColor White
Write-Host " Wine Desktop: http://localhost:8080" -ForegroundColor White
Write-Host " API Docs:     http://localhost:4000/docs" -ForegroundColor White
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan

Start-Process "http://localhost:3000"
