@echo off
:: Setup USB/IP Server — Als Administrator ausführen!
powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File ""%~dp0setup-usbip-server.ps1""' -Verb RunAs"
