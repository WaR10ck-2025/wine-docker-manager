# windows-usbip-autoconnect.ps1
# Richtet die automatische USB/IP-Verbindung zum Mini-PC in der Windows-VM ein.
# Einmalig in der Windows-VM ausführen (als Administrator).
#
# Verwendung:
#   .\windows-usbip-autoconnect.ps1 -MiniPcIp 192.168.10.200
#   .\windows-usbip-autoconnect.ps1 -MiniPcIp 192.168.10.200 -BusId "1-2"
#
param(
    [Parameter(Mandatory=$true)]
    [string]$MiniPcIp,

    [string]$BusId = "1-1"    # Bus-ID des Autocom auf dem Mini-PC (usbip list -l)
)

$ErrorActionPreference = "Stop"

function Write-Info  { param($m) Write-Host "[setup] $m" -ForegroundColor Green }
function Write-Warn  { param($m) Write-Host "[setup] $m" -ForegroundColor Yellow }
function Write-Err   { param($m) Write-Host "[setup] $m" -ForegroundColor Red }

Write-Info "Autocom CDP+ USB/IP Auto-Connect Setup"
Write-Host ""

# Admin-Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Bitte als Administrator ausführen (Rechtsklick -> Als Administrator ausführen)"
    exit 1
}

# ── 1. usbipd-win installieren ───────────────────────────────────────────────
Write-Info "Prüfe usbipd-win..."
$usbipdInstalled = $false
try {
    $null = Get-Command usbipd -ErrorAction Stop
    $usbipdInstalled = $true
    Write-Info "usbipd-win ist bereits installiert ✓"
} catch {
    Write-Info "Installiere usbipd-win via winget..."
    try {
        winget install --id dorssel.usbipd-win --silent --accept-package-agreements --accept-source-agreements
        # PATH neu laden
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        $usbipdInstalled = $true
        Write-Info "usbipd-win installiert ✓"
    } catch {
        Write-Err "Fehler bei winget-Installation: $_"
        Write-Warn "Manuell installieren: https://github.com/dorssel/usbipd-win/releases"
        exit 1
    }
}

# ── 2. Verbindung testen ─────────────────────────────────────────────────────
Write-Info "Teste Verbindung zum Mini-PC ${MiniPcIp}:3240..."
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($MiniPcIp, 3240)
    $tcp.Close()
    Write-Info "Mini-PC erreichbar ✓"
} catch {
    Write-Warn "Mini-PC nicht erreichbar. Sicherstellen dass:"
    Write-Warn "  1. Mini-PC läuft und im selben Netzwerk ist"
    Write-Warn "  2. usbipd auf dem Mini-PC läuft: systemctl status usbipd"
    Write-Warn "  3. Firewall Port 3240 freigegeben ist"
    Write-Warn "Trotzdem weiter mit Scheduled Task Setup..."
}

# ── 3. Verbind-Skript erstellen ──────────────────────────────────────────────
$connectScriptPath = "C:\ProgramData\AutocomUsbIp\connect.ps1"
$scriptDir = Split-Path $connectScriptPath
New-Item -ItemType Directory -Force -Path $scriptDir | Out-Null

$connectScript = @"
# Autocom CDP+ USB/IP Auto-Connect
# Automatisch generiert von windows-usbip-autoconnect.ps1

`$MiniPcIp = "$MiniPcIp"
`$BusId    = "$BusId"
`$MaxRetry = 10
`$Delay    = 15   # Sekunden zwischen Versuchen

for (`$i = 1; `$i -le `$MaxRetry; `$i++) {
    try {
        `$tcp = New-Object System.Net.Sockets.TcpClient
        `$tcp.Connect(`$MiniPcIp, 3240)
        `$tcp.Close()
        # Verbindung klappt — USB/IP attach
        usbipd attach --remote `$MiniPcIp --busid `$BusId 2>&1 | Out-File -Append "C:\ProgramData\AutocomUsbIp\connect.log"
        "[$(Get-Date)] Verbunden mit `$MiniPcIp busid `$BusId" | Out-File -Append "C:\ProgramData\AutocomUsbIp\connect.log"
        break
    } catch {
        "[$(Get-Date)] Versuch `$i/`$MaxRetry fehlgeschlagen: `$_" | Out-File -Append "C:\ProgramData\AutocomUsbIp\connect.log"
        Start-Sleep -Seconds `$Delay
    }
}
"@
$connectScript | Out-File -FilePath $connectScriptPath -Encoding UTF8
Write-Info "Verbind-Skript erstellt: $connectScriptPath"

# ── 4. Scheduled Task registrieren ──────────────────────────────────────────
Write-Info "Registriere Scheduled Task 'AutocomUsbIpConnect'..."
$taskName = "AutocomUsbIpConnect"

# Alten Task entfernen (falls vorhanden)
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
               -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$connectScriptPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
                -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null

Write-Info "Scheduled Task '$taskName' registriert (startet bei jedem Boot) ✓"

# ── 5. Jetzt sofort verbinden ────────────────────────────────────────────────
Write-Host ""
Write-Info "Verbinde jetzt sofort..."
try {
    $result = usbipd attach --remote $MiniPcIp --busid $BusId 2>&1
    Write-Info "Ergebnis: $result"
} catch {
    Write-Warn "Sofort-Verbindung fehlgeschlagen (wird beim nächsten Start automatisch versucht): $_"
}

# ── 6. Zusammenfassung ───────────────────────────────────────────────────────
Write-Host ""
Write-Info "═══════════════════════════════════════════"
Write-Info "Setup abgeschlossen!"
Write-Info ""
Write-Info "Mini-PC IP:  $MiniPcIp"
Write-Info "Bus-ID:      $BusId"
Write-Info "Task:        AutocomUsbIpConnect (läuft bei jedem Boot)"
Write-Info "Log:         C:\ProgramData\AutocomUsbIp\connect.log"
Write-Info ""
Write-Info "Bus-ID auf dem Mini-PC prüfen:"
Write-Info "  ssh user@$MiniPcIp 'usbip list -l'"
Write-Info "═══════════════════════════════════════════"
