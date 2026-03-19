@echo off
title Wine Manager — Setup
chcp 65001 >nul

echo ╔══════════════════════════════════════╗
echo ║       Wine Manager — Setup           ║
echo ╚══════════════════════════════════════╝
echo.

:: Docker-Verfügbarkeit prüfen
docker info >nul 2>&1
if errorlevel 1 (
    echo [FEHLER] Docker ist nicht gestartet oder nicht installiert.
    echo Bitte Docker Desktop starten und erneut versuchen.
    pause & exit /b 1
)

echo [1/3] Baue Docker-Images...
docker compose build
if errorlevel 1 (
    echo [FEHLER] Build fehlgeschlagen.
    pause & exit /b 1
)

echo.
echo [2/3] Starte Dienste...
docker compose up -d
if errorlevel 1 (
    echo [FEHLER] Start fehlgeschlagen.
    pause & exit /b 1
)

echo.
echo [3/3] Warte auf Wine-Initialisierung (30 Sekunden)...
timeout /t 30 /nobreak >nul

echo.
echo ════════════════════════════════════════
echo  Wine Manager läuft!
echo.
echo  App-Manager:  http://localhost:3000
echo  Wine Desktop: http://localhost:8080
echo  API:          http://localhost:4000
echo ════════════════════════════════════════
echo.

:: Browser öffnen
start http://localhost:3000

pause
