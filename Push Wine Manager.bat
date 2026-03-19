@echo off
chcp 65001 >nul
title Wine Manager – Push
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0push.ps1"
pause
