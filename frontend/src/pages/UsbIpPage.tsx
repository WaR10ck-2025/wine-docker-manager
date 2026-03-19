/**
 * UsbIpPage — Verwaltet den USB/IP-Server.
 * Drei Modi:
 *   1. Lokaler Server: Umbrel teilt Autocom → Windows-PC im LAN
 *   2. Mini-PC Headless: Headless Linux-PC teilt Autocom → Windows-VM auf Umbrel
 *   3. OBD2 Live: Echtzeit-Fahrzeugdaten vom Mini-PC (wenn verbunden)
 */
import { useEffect, useRef, useState } from 'react'
import {
  BASE,
  obdClearDtcs,
  obdDtcs,
  obdStatus,
  obdStream,
  usbIpRemoteStatus,
  type ObdData,
  type ObdDtcs,
  type ObdStatus,
  type UsbIpRemoteStatus,
} from '../api'

interface UsbIpStatus {
  running: boolean
  container: string
  devices: string[]
}

export default function UsbIpPage() {
  const [status, setStatus]             = useState<UsbIpStatus | null>(null)
  const [remoteStatus, setRemoteStatus] = useState<UsbIpRemoteStatus | null>(null)
  const [loading, setLoading]           = useState(true)
  const [busy, setBusy]                 = useState(false)
  const [activeTab, setActiveTab]       = useState<'local' | 'remote' | 'obd'>('local')

  // OBD2 State
  const [obdConnStatus, setObdConnStatus] = useState<ObdStatus | null>(null)
  const [obdLiveData, setObdLiveData]     = useState<ObdData | null>(null)
  const [obdFaultCodes, setObdFaultCodes] = useState<ObdDtcs | null>(null)
  const [clearingDtcs, setClearingDtcs]   = useState(false)
  const obdStreamCleanup = useRef<(() => void) | null>(null)

  const fetchStatus = () =>
    fetch(`${BASE}/usbip/status`)
      .then((r) => r.json())
      .then(setStatus)
      .catch(console.error)
      .finally(() => setLoading(false))

  const fetchRemote = () =>
    usbIpRemoteStatus()
      .then(setRemoteStatus)
      .catch(console.error)

  // OBD2 Status alle 5s pollen (unabhängig vom Tab)
  const fetchObdStatus = () =>
    obdStatus().then(setObdConnStatus).catch(() => {})

  useEffect(() => {
    fetchStatus()
    fetchRemote()
    fetchObdStatus()
    const t = setInterval(() => { fetchStatus(); fetchRemote(); fetchObdStatus() }, 5000)
    return () => clearInterval(t)
  }, [])

  // SSE-Stream starten/stoppen wenn OBD-Tab aktiv
  useEffect(() => {
    if (activeTab === 'obd') {
      obdDtcs().then(setObdFaultCodes).catch(() => {})
      const cleanup = obdStream(setObdLiveData)
      obdStreamCleanup.current = cleanup
      return () => { cleanup(); obdStreamCleanup.current = null }
    } else {
      obdStreamCleanup.current?.()
      obdStreamCleanup.current = null
    }
  }, [activeTab])

  const handleClearDtcs = async () => {
    if (!confirm('Alle Fehlercodes löschen? (Motorlampelle erlischt)')) return
    setClearingDtcs(true)
    await obdClearDtcs().catch(console.error)
    const fresh = await obdDtcs().catch(() => null)
    if (fresh) setObdFaultCodes(fresh)
    setClearingDtcs(false)
  }

  const toggle = async () => {
    setBusy(true)
    const url = status?.running ? `${BASE}/usbip/stop` : `${BASE}/usbip/start`
    await fetch(url, { method: 'POST' }).catch(console.error)
    await fetchStatus()
    setBusy(false)
  }

  if (loading) return <p className="text-gray-500 text-sm animate-pulse">Lade Status...</p>

  return (
    <div className="max-w-2xl space-y-6">
      <h1 className="text-lg font-semibold text-gray-200">USB/IP — Autocom CDP+</h1>

      {/* Tab-Switcher */}
      <div className="flex gap-1 border-b border-gray-800">
        <TabBtn active={activeTab === 'local'} onClick={() => setActiveTab('local')}>
          🔌 Lokaler Server
        </TabBtn>
        <TabBtn active={activeTab === 'remote'} onClick={() => setActiveTab('remote')}>
          🖥 Mini-PC Headless
          {remoteStatus?.configured && (
            <span className={`ml-2 w-1.5 h-1.5 rounded-full inline-block ${
              remoteStatus.reachable ? 'bg-green-500' : 'bg-red-500'
            }`} />
          )}
        </TabBtn>
        <TabBtn active={activeTab === 'obd'} onClick={() => setActiveTab('obd')}>
          🚗 OBD2 Live
          {obdConnStatus?.connected && (
            <span className="ml-2 w-1.5 h-1.5 rounded-full inline-block bg-green-500" />
          )}
        </TabBtn>
      </div>

      {/* ── Tab: Lokaler Server ────────────────────────────────────────────── */}
      {activeTab === 'local' && (
        <div className="space-y-6">
          <p className="text-xs text-gray-500">
            Umbrel-Server teilt den Autocom CDP+ über das Netzwerk. Ein Windows-PC verbindet sich
            und nutzt das Gerät als wäre es lokal angesteckt.
          </p>

          {/* Status-Karte */}
          <div className="bg-gray-900 border border-gray-800 rounded p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <span className={`w-2.5 h-2.5 rounded-full ${status?.running ? 'bg-green-500' : 'bg-gray-600'}`} />
                <span className="text-sm text-gray-300">
                  {status?.running ? 'Server läuft — Gerät wird geteilt' : 'Server gestoppt'}
                </span>
              </div>
              <button
                onClick={toggle}
                disabled={busy}
                className={`text-xs px-3 py-1 rounded disabled:opacity-50 text-white ${
                  status?.running ? 'bg-red-700 hover:bg-red-600' : 'bg-green-700 hover:bg-green-600'
                }`}
              >
                {busy ? '⏳' : status?.running ? '■ Stoppen' : '▶ Starten'}
              </button>
            </div>

            {status?.devices && status.devices.length > 0 && (
              <div className="text-xs font-mono text-gray-500 border-t border-gray-800 pt-2">
                {status.devices.map((d, i) => <div key={i}>{d}</div>)}
              </div>
            )}
          </div>

          {/* Anleitung Windows-Client */}
          <div className="space-y-3">
            <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wider">
              Windows-PC verbinden
            </h2>
            <div className="bg-gray-900 border border-gray-800 rounded p-4 space-y-4 text-sm">
              <Step n={1} title="usbipd-win installieren">
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
                  winget install usbipd
                </code>
              </Step>
              <Step n={2} title="Gerät vom Umbrel-Server binden">
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
                  usbipd attach --remote 192.168.10.147 --busid 3-6
                </code>
                <p className="text-gray-500 text-xs mt-1">
                  Das Gerät erscheint als lokales USB-Gerät im Geräte-Manager.
                </p>
              </Step>
              <Step n={3} title="DS150E Software starten">
                <p className="text-gray-400 text-xs">
                  Öffne DS150E auf dem Windows-PC. Der Autocom CDP+ wird erkannt.
                </p>
              </Step>
              <Step n={4} title="Gerät wieder freigeben">
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
                  usbipd detach --busid 3-6
                </code>
              </Step>
            </div>
          </div>

          <p className="text-xs text-gray-600">
            USB/IP Port: <span className="text-gray-400">3240</span> &nbsp;|&nbsp;
            Autocom Bus-ID: <span className="text-gray-400">3-6</span>
          </p>
        </div>
      )}

      {/* ── Tab: Mini-PC Headless ──────────────────────────────────────────── */}
      {activeTab === 'remote' && (
        <div className="space-y-6">
          <p className="text-xs text-gray-500">
            Ein headless Mini-PC (Linux, kein Monitor) steckt dauerhaft am Autocom CDP+ und
            teilt ihn per USB/IP. Die DS150E-Software läuft in der Windows-VM auf diesem Server.
          </p>

          {/* Remote Status */}
          <div className="bg-gray-900 border border-gray-800 rounded p-4">
            <div className="flex items-center gap-3">
              <span className={`w-2.5 h-2.5 rounded-full flex-shrink-0 ${
                !remoteStatus?.configured ? 'bg-gray-600' :
                remoteStatus.reachable ? 'bg-green-500' : 'bg-red-500'
              }`} />
              <div>
                <p className="text-sm text-gray-300">
                  {!remoteStatus?.configured
                    ? 'Nicht konfiguriert'
                    : remoteStatus.reachable
                      ? `Mini-PC erreichbar: ${remoteStatus.host}`
                      : `Mini-PC nicht erreichbar: ${remoteStatus.host}`}
                </p>
                {!remoteStatus?.configured && (
                  <p className="text-xs text-gray-600 mt-0.5">
                    USBIP_REMOTE_HOST in docker-compose.yml setzen, dann Container neu starten.
                  </p>
                )}
                {remoteStatus?.configured && !remoteStatus.reachable && (
                  <p className="text-xs text-gray-600 mt-0.5">
                    USB/IP Daemon läuft nicht — auf dem Mini-PC: systemctl status usbipd
                  </p>
                )}
              </div>
            </div>
          </div>

          {/* Schritt 1: Mini-PC einrichten */}
          <div className="space-y-3">
            <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wider">
              Schritt 1 — Mini-PC einrichten
            </h2>
            <div className="bg-gray-900 border border-gray-800 rounded p-4 space-y-4 text-sm">
              <Step n={1} title="Skript auf den Mini-PC kopieren">
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs whitespace-pre">
                  {`scp usbip-client/install.sh user@<mini-pc-ip>:~/
ssh user@<mini-pc-ip>`}
                </code>
              </Step>
              <Step n={2} title="Installation ausführen (als root)">
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
                  sudo bash install.sh
                </code>
                <p className="text-gray-500 text-xs mt-1">
                  Installiert usbip, richtet systemd Service + udev-Regel ein. Idempotent.
                </p>
              </Step>
              <Step n={3} title="IP-Adresse notieren und in docker-compose.yml eintragen">
                <p className="text-gray-400 text-xs mb-2">
                  Das Skript gibt die IP am Ende aus. Dann in <code className="text-blue-400">docker-compose.yml</code>:
                </p>
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
                  USBIP_REMOTE_HOST: "192.168.10.200"
                </code>
                <p className="text-gray-500 text-xs mt-1">
                  Danach: docker compose up -d manager-api
                </p>
              </Step>
              <Step n={4} title="Autocom CDP+ einstecken">
                <p className="text-gray-400 text-xs">
                  Der udev-Daemon bindet das Gerät automatisch. Status oben wechselt auf grün.
                </p>
              </Step>
            </div>
          </div>

          {/* Schritt 2: Windows VM einrichten */}
          <div className="space-y-3">
            <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wider">
              Schritt 2 — Windows VM einrichten (einmalig)
            </h2>
            <div className="bg-gray-900 border border-gray-800 rounded p-4 space-y-4 text-sm">
              <Step n={1} title="Windows VM starten (Tab: Windows VM)">
                <p className="text-gray-400 text-xs">
                  Erste Start lädt Windows 10 (~5 GB) herunter. Warten bis Desktop erscheint.
                </p>
              </Step>
              <Step n={2} title="Setup-Skript in die VM kopieren">
                <p className="text-gray-400 text-xs mb-2">
                  Im noVNC-Desktop: Browser öffnen oder Netzlaufwerk verbinden und
                  <code className="text-blue-400"> vm-setup/windows-usbip-autoconnect.ps1</code> herunterladen.
                </p>
              </Step>
              <Step n={3} title="PowerShell als Admin ausführen">
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
                  .\windows-usbip-autoconnect.ps1 -MiniPcIp 192.168.10.200
                </code>
                <p className="text-gray-500 text-xs mt-1">
                  Installiert usbipd-win + richtet Scheduled Task für Auto-Connect beim Start ein.
                </p>
              </Step>
              <Step n={4} title="DS150E installieren und testen">
                <p className="text-gray-400 text-xs">
                  Autocom CDP+ erscheint im Geräte-Manager. DS150E installieren und starten.
                </p>
              </Step>
            </div>
          </div>

          <p className="text-xs text-gray-600">
            Mini-PC USB/IP Port: <span className="text-gray-400">3240</span> &nbsp;|&nbsp;
            Auto-Connect: <span className="text-gray-400">Scheduled Task bei VM-Start</span>
          </p>
        </div>
      )}

      {/* ── Tab: OBD2 Live ─────────────────────────────────────────────────── */}
      {activeTab === 'obd' && (
        <div className="space-y-4">

          {/* Verbindungsstatus */}
          <div className="bg-gray-900 border border-gray-800 rounded p-3 flex items-center gap-3">
            <span className={`w-2.5 h-2.5 rounded-full flex-shrink-0 ${
              obdConnStatus?.connected ? 'bg-green-500' : 'bg-red-500'
            }`} />
            <div className="flex-1 min-w-0">
              <span className="text-sm text-gray-300">
                {obdConnStatus?.connected
                  ? `Verbunden — Protokoll: ${obdConnStatus.protocol?.toUpperCase()}, Port: ${obdConnStatus.port}`
                  : obdConnStatus?.error ?? 'Getrennt — OBD2 Monitor prüfen'}
              </span>
            </div>
            {obdConnStatus?.protocol && (
              <span className="text-xs px-2 py-0.5 rounded bg-blue-900 text-blue-300 font-mono flex-shrink-0">
                {obdConnStatus.protocol === 'elm327' ? 'ELM327' : 'ISO 9141-2'}
              </span>
            )}
          </div>

          {/* Gauges — 3-Spalten Grid */}
          <div className="grid grid-cols-3 gap-3">
            <GaugeCard title="MOTOR">
              <GaugeRow label="RPM"       value={obdLiveData?.rpm}              unit="rpm" />
              <GaugeRow label="Kühlmittel" value={obdLiveData?.coolant_temp}    unit="°C" />
              <GaugeRow label="Batterie"  value={obdLiveData?.battery_voltage}  unit="V" decimals={1} />
            </GaugeCard>
            <GaugeCard title="FAHRT">
              <GaugeRow label="Geschw."   value={obdLiveData?.speed}            unit="km/h" />
              <GaugeRow label="Last"      value={obdLiveData?.engine_load}      unit="%" decimals={1} />
            </GaugeCard>
            <GaugeCard title="KRAFTSTOFF">
              <GaugeRow label="Trim Kurz" value={obdLiveData?.short_fuel_trim}  unit="%" decimals={1} signed />
              <GaugeRow label="Trim Lang" value={obdLiveData?.long_fuel_trim}   unit="%" decimals={1} signed />
            </GaugeCard>
          </div>

          {/* Drosselklappe-Balken */}
          <div className="bg-gray-900 border border-gray-800 rounded p-3">
            <div className="flex items-center gap-3">
              <span className="text-xs text-gray-500 w-24 flex-shrink-0">Drosselklappe</span>
              <div className="flex-1 bg-gray-800 rounded-full h-2">
                <div
                  className="bg-green-500 h-2 rounded-full transition-all duration-300"
                  style={{ width: `${Math.min(obdLiveData?.throttle ?? 0, 100)}%` }}
                />
              </div>
              <span className="text-xs text-gray-300 w-10 text-right flex-shrink-0">
                {obdLiveData?.throttle != null ? `${obdLiveData.throttle.toFixed(0)}%` : '--'}
              </span>
            </div>
          </div>

          {/* DTCs */}
          <div className="bg-gray-900 border border-gray-800 rounded p-4 space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wider">
                Fehlercodes (DTCs)
                <span className="ml-2 text-gray-600 normal-case font-normal">
                  {obdFaultCodes != null ? `${obdFaultCodes.count} Einträge` : ''}
                </span>
              </h2>
              <div className="flex gap-2">
                <button
                  onClick={() => obdDtcs().then(setObdFaultCodes).catch(() => {})}
                  className="text-xs px-2 py-1 rounded bg-gray-800 text-gray-400 hover:text-gray-200"
                >
                  ↻ Aktualisieren
                </button>
                <button
                  onClick={handleClearDtcs}
                  disabled={clearingDtcs || !obdConnStatus?.connected}
                  className="text-xs px-2 py-1 rounded bg-red-900 text-red-300 hover:bg-red-800 disabled:opacity-40"
                >
                  {clearingDtcs ? '...' : '✕ Löschen'}
                </button>
              </div>
            </div>

            {!obdFaultCodes || obdFaultCodes.count === 0 ? (
              <p className="text-xs text-green-500">Keine Fehlercodes gespeichert ✓</p>
            ) : (
              <div className="flex flex-wrap gap-2">
                {obdFaultCodes.codes.map((dtc) => (
                  <span key={dtc.code} className="text-xs font-mono px-2 py-1 rounded bg-red-950 text-red-400 border border-red-900">
                    {dtc.code}
                  </span>
                ))}
              </div>
            )}
          </div>

          {/* SSH-Tipp */}
          <div className="bg-gray-900 border border-gray-800 rounded p-3 space-y-1">
            <p className="text-xs text-gray-500 font-medium">SSH Terminal-Dashboard</p>
            <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
              ssh root@autocom-usbip "obd-monitor"
            </code>
            <p className="text-xs text-gray-600">
              OBD2 API: Port 8765 &nbsp;|&nbsp; install: bash usbip-client/obd-monitor/install_obd.sh
            </p>
          </div>
        </div>
      )}
    </div>
  )
}

function TabBtn({ active, onClick, children }: {
  active: boolean
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      onClick={onClick}
      className={`px-4 py-2 text-sm border-b-2 transition-colors flex items-center gap-1 ${
        active
          ? 'border-wine-500 text-white'
          : 'border-transparent text-gray-500 hover:text-gray-300'
      }`}
    >
      {children}
    </button>
  )
}

function Step({ n, title, children }: { n: number; title: string; children: React.ReactNode }) {
  return (
    <div className="flex gap-3">
      <span className="flex-shrink-0 w-5 h-5 rounded-full bg-gray-800 text-gray-400 text-xs flex items-center justify-center font-mono">
        {n}
      </span>
      <div className="flex-1">
        <p className="text-gray-300 text-xs font-medium mb-1">{title}</p>
        {children}
      </div>
    </div>
  )
}

function GaugeCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-gray-900 border border-gray-800 rounded p-3 space-y-2">
      <p className="text-xs font-medium text-gray-500 uppercase tracking-wider">{title}</p>
      {children}
    </div>
  )
}

function GaugeRow({
  label, value, unit, decimals = 0, signed = false,
}: {
  label: string; value: number | null | undefined; unit: string; decimals?: number; signed?: boolean
}) {
  const display = value != null
    ? `${signed && value > 0 ? '+' : ''}${value.toFixed(decimals)} ${unit}`
    : '--'
  const color = value != null ? 'text-white' : 'text-gray-600'
  return (
    <div className="flex justify-between items-baseline">
      <span className="text-xs text-gray-500">{label}</span>
      <span className={`text-sm font-mono ${color}`}>{display}</span>
    </div>
  )
}
