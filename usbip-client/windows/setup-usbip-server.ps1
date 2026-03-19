# setup-usbip-server.ps1
# ─────────────────────────────────────────────────────────────────────────────
# Richtet den MEEGOPAD PC Stick als headless USB/IP-Server ein.
# Teilt den Autocom CDP+ (FTDI 0403:d6da) über das Netzwerk (Port 3240).
#
# Einmalig als Administrator ausführen:
#   PowerShell -ExecutionPolicy Bypass -File setup-usbip-server.ps1
#
# Was dieses Skript tut:
#   1. usbipd-win installieren (Windows-Dienst, auto-start)
#   2. Autocom CDP+ binden (persistiert in Registry, auto-rebind bei Einstecken)
#   3. Windows Firewall für Port 3240 freigeben
#   4. OpenSSH Server aktivieren (für headless Remote-Verwaltung)
#   5. Automatische Anmeldung konfigurieren (optional, für headless Betrieb)
# ─────────────────────────────────────────────────────────────────────────────
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$AUTOCOM_HW_ID  = "0403:d6da"   # FTDI Vendor:Product
$USBIP_PORT     = 3240
$FIREWALL_RULE  = "USB/IP Server (Autocom CDP+)"

function Write-Info  { param($m) Write-Host "[setup] $m" -ForegroundColor Green }
function Write-Warn  { param($m) Write-Host "[setup] $m" -ForegroundColor Yellow }
function Write-Step  { param($n,$m) Write-Host "`n[$n/5] $m" -ForegroundColor Cyan }

Write-Host ""
Write-Host "  MEEGOPAD — Autocom CDP+ USB/IP Server Setup" -ForegroundColor White
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

# ── 1. usbipd-win installieren ───────────────────────────────────────────────
Write-Step 1 "usbipd-win installieren"

$usbipdOk = $false
try {
    $ver = (usbipd --version 2>&1)
    Write-Info "usbipd-win bereits installiert: $ver"
    $usbipdOk = $true
} catch {
    Write-Info "Installiere usbipd-win via winget..."
    try {
        winget install --id dorssel.usbipd-win --silent `
            --accept-package-agreements --accept-source-agreements
        # PATH neu laden
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        $usbipdOk = $true
        Write-Info "usbipd-win installiert ✓"
    } catch {
        Write-Warn "winget fehlgeschlagen: $_"
        Write-Warn "Manuell installieren: https://github.com/dorssel/usbipd-win/releases"
        Write-Warn "Nach der Installation dieses Skript erneut ausführen."
        exit 1
    }
}

# Dienst-Status prüfen
$svc = Get-Service -Name "usbipd" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne "Running") {
    Start-Service "usbipd"
    Write-Info "usbipd-Dienst gestartet ✓"
} elseif ($svc) {
    Write-Info "usbipd-Dienst läuft ✓"
}

# ── 2. Autocom CDP+ binden ───────────────────────────────────────────────────
Write-Step 2 "Autocom CDP+ binden (Hardware-ID: $AUTOCOM_HW_ID)"

# Verfügbare Geräte anzeigen
Write-Info "Verfügbare USB-Geräte:"
usbipd list 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

# Nach Hardware-ID binden (persistiert in Registry, auto-rebind bei Einstecken)
try {
    usbipd bind --hardware-id $AUTOCOM_HW_ID 2>&1 | Out-Null
    Write-Info "Autocom CDP+ ($AUTOCOM_HW_ID) gebunden ✓"
    Write-Info "Gerät wird bei jedem Einstecken automatisch geteilt."
} catch {
    # Schon gebunden ist kein Fehler
    if ($_ -match "already" -or $_ -match "bereits") {
        Write-Info "Gerät ist bereits gebunden ✓"
    } else {
        Write-Warn "Bind fehlgeschlagen (Gerät eingesteckt?): $_"
        Write-Warn "Später manuell: usbipd bind --hardware-id $AUTOCOM_HW_ID"
    }
}

# ── 3. Windows Firewall ──────────────────────────────────────────────────────
Write-Step 3 "Windows Firewall — Port $USBIP_PORT freigeben"

# Bestehende Regel entfernen
Remove-NetFirewallRule -DisplayName $FIREWALL_RULE -ErrorAction SilentlyContinue

New-NetFirewallRule `
    -DisplayName $FIREWALL_RULE `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $USBIP_PORT `
    -Action Allow `
    -Profile Any | Out-Null

Write-Info "Firewall-Regel erstellt: TCP Port $USBIP_PORT ✓"

# ── 4. OpenSSH Server (Remote-Verwaltung) ────────────────────────────────────
Write-Step 4 "OpenSSH Server aktivieren (headless Remote-Zugriff)"

$sshFeature = Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*"
if ($sshFeature.State -ne "Installed") {
    Write-Info "Installiere OpenSSH Server..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
    Write-Info "OpenSSH Server installiert ✓"
} else {
    Write-Info "OpenSSH Server bereits installiert ✓"
}

Set-Service -Name sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue

# Firewall für SSH (falls nicht vorhanden)
$sshRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $sshRule) {
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (TCP)" `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}
Write-Info "SSH-Zugriff aktiviert: ssh $env:USERNAME@<ip> ✓"

# ── 5. Energieoptionen (kein Standby) ────────────────────────────────────────
Write-Step 5 "Energieoptionen — Standby deaktivieren"

powercfg /change standby-timeout-ac 0    | Out-Null
powercfg /change hibernate-timeout-ac 0  | Out-Null
powercfg /change monitor-timeout-ac 0    | Out-Null
Write-Info "Standby + Monitor-Timeout deaktiviert (headless Dauerbetrieb) ✓"

# Hochleistungsplan aktivieren
$plan = powercfg /list | Select-String "Hohe Leistung|High performance" | Select-Object -First 1
if ($plan) {
    $guid = ($plan -split "\s+")[3]
    powercfg /setactive $guid | Out-Null
    Write-Info "Energieplan: Hohe Leistung aktiviert ✓"
}

# ── Zusammenfassung ──────────────────────────────────────────────────────────
$IP = (Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -notmatch "^169" } |
       Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  Setup abgeschlossen!" -ForegroundColor Green
Write-Host ""
Write-Host "  IP-Adresse:    $IP" -ForegroundColor White
Write-Host "  SSH-Zugriff:   ssh $env:USERNAME@$IP" -ForegroundColor White
Write-Host "  USB/IP Port:   $USBIP_PORT" -ForegroundColor White
Write-Host ""
Write-Host "  In docker-compose.yml setzen:" -ForegroundColor Gray
Write-Host "    USBIP_REMOTE_HOST: `"$IP`"" -ForegroundColor Green
Write-Host ""
Write-Host "  Windows VM einrichten:" -ForegroundColor Gray
Write-Host "    ..\windows-usbip-autoconnect.ps1 -MiniPcIp $IP -BusId 1-1" -ForegroundColor Green
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

# Status ausgeben
Write-Host "  Aktueller usbipd Status:" -ForegroundColor Gray
usbipd list 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
Write-Host ""
