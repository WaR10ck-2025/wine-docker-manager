/**
 * UsbIpPage — Verwaltet den USB/IP-Server.
 * Teilt den Autocom CDP+ über das Netzwerk an einen Windows-PC.
 */
import { useEffect, useState } from 'react'
import { BASE } from '../api'

interface UsbIpStatus {
  running: boolean
  container: string
  devices: string[]
}

export default function UsbIpPage() {
  const [status, setStatus] = useState<UsbIpStatus | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)

  const fetchStatus = () =>
    fetch(`${BASE}/usbip/status`)
      .then((r) => r.json())
      .then(setStatus)
      .catch(console.error)
      .finally(() => setLoading(false))

  useEffect(() => {
    fetchStatus()
    const t = setInterval(fetchStatus, 5000)
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
      <h1 className="text-lg font-semibold text-gray-200">USB/IP Server</h1>

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
            <p className="text-gray-400 text-xs mb-2">
              Modernes USB/IP für Windows — einmalige Installation:
            </p>
            <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
              winget install usbipd
            </code>
            <p className="text-gray-600 text-xs mt-1">
              Alternativ: <span className="text-blue-400">github.com/dorssel/usbipd-win</span>
            </p>
          </Step>

          <Step n={2} title="Gerät anzeigen (Windows PowerShell als Admin)">
            <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
              usbipd list
            </code>
          </Step>

          <Step n={3} title="Gerät vom Umbrel-Server binden">
            <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
              usbipd attach --remote 192.168.10.147 --busid 3-6
            </code>
            <p className="text-gray-500 text-xs mt-1">
              Das Gerät erscheint dann als lokales USB-Gerät im Geräte-Manager.
            </p>
          </Step>

          <Step n={4} title="DS150E Software starten">
            <p className="text-gray-400 text-xs">
              Öffne DS150E auf dem Windows-PC. Der Autocom CDP+ wird wie ein direkt
              angestecktes USB-Gerät erkannt.
            </p>
          </Step>

          <Step n={5} title="Gerät wieder freigeben">
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
