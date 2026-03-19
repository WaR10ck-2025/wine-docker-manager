/**
 * UsbIpPage — Verwaltet den USB/IP-Server.
 * Zwei Modi:
 *   1. Lokaler Server: Umbrel teilt Autocom → Windows-PC im LAN
 *   2. Mini-PC Headless: Headless Linux-PC teilt Autocom → Windows-VM auf Umbrel
 */
import { useEffect, useState } from 'react'
import { BASE, usbIpRemoteStatus, type UsbIpRemoteStatus } from '../api'

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
  const [activeTab, setActiveTab]       = useState<'local' | 'remote'>('local')

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

  useEffect(() => {
    fetchStatus()
    fetchRemote()
    const t = setInterval(() => { fetchStatus(); fetchRemote() }, 5000)
    return () => clearInterval(t)
  }, [])

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
