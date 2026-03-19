/**
 * WindowsVmPage — Steuert die Windows-VM (QEMU/KVM via dockurr/windows).
 * Bettet den noVNC-Desktop der VM per iframe ein.
 */
import { useEffect, useState } from 'react'
import { BASE } from '../api'

interface VmStatus {
  running: boolean
  container: string
}

export default function WindowsVmPage() {
  const [status, setStatus] = useState<VmStatus | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)

  const vmUrl = `http://${window.location.hostname}:8100`

  const fetchStatus = () =>
    fetch(`${BASE}/windowsvm/status`)
      .then((r) => r.json())
      .then(setStatus)
      .catch(console.error)
      .finally(() => setLoading(false))

  useEffect(() => {
    fetchStatus()
    const t = setInterval(fetchStatus, 8000)
    return () => clearInterval(t)
  }, [])

  const start = async () => {
    setBusy(true)
    await fetch(`${BASE}/windowsvm/start`, { method: 'POST' }).catch(console.error)
    // Windows VM braucht ~30s zum Starten
    setTimeout(() => { fetchStatus(); setBusy(false) }, 10000)
  }

  const stop = async () => {
    if (!confirm('Windows-VM herunterfahren? Ungespeicherte Daten gehen verloren!')) return
    setBusy(true)
    await fetch(`${BASE}/windowsvm/stop`, { method: 'POST' }).catch(console.error)
    await fetchStatus()
    setBusy(false)
  }

  if (loading) return <p className="text-gray-500 text-sm animate-pulse">Lade Status...</p>

  return (
    <div className="flex flex-col gap-3 h-[calc(100vh-8rem)]">
      {/* Header */}
      <div className="flex items-center justify-between flex-shrink-0">
        <div className="flex items-center gap-3">
          <h1 className="text-lg font-semibold text-gray-200">Windows VM</h1>
          <span className={`text-xs px-2 py-0.5 rounded-full ${
            status?.running ? 'bg-green-900 text-green-400' : 'bg-gray-800 text-gray-500'
          }`}>
            {status?.running ? 'Läuft' : 'Gestoppt'}
          </span>
        </div>

        <div className="flex items-center gap-2">
          {status?.running && (
            <a
              href={vmUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-gray-400 hover:text-white border border-gray-700 rounded px-2 py-1"
            >
              In neuem Tab ↗
            </a>
          )}
          {status?.running ? (
            <button
              onClick={stop}
              disabled={busy}
              className="text-xs bg-red-800 hover:bg-red-700 disabled:opacity-50 text-white px-3 py-1 rounded"
            >
              {busy ? '⏳' : '■ Herunterfahren'}
            </button>
          ) : (
            <button
              onClick={start}
              disabled={busy}
              className="text-xs bg-blue-700 hover:bg-blue-600 disabled:opacity-50 text-white px-3 py-1 rounded"
            >
              {busy ? '⏳ Startet...' : '▶ VM starten'}
            </button>
          )}
        </div>
      </div>

      {/* VM-Anzeige oder Setup-Hinweis */}
      {status?.running ? (
        <div className="flex-1 rounded border border-gray-700 overflow-hidden bg-black">
          <iframe
            src={vmUrl}
            className="w-full h-full"
            title="Windows VM"
            allow="clipboard-read; clipboard-write"
          />
        </div>
      ) : (
        <div className="flex-1 rounded border border-gray-800 bg-gray-950 flex flex-col items-center justify-center gap-4 text-center p-8">
          <div className="text-4xl">🪟</div>
          <div className="space-y-2">
            <p className="text-gray-300 text-sm font-medium">Windows-VM ist nicht gestartet</p>
            <p className="text-gray-600 text-xs max-w-md">
              Beim ersten Start wird Windows 10 automatisch heruntergeladen (~5 GB)
              und installiert. Das dauert 10–30 Minuten.
            </p>
          </div>
          <div className="text-xs text-gray-700 space-y-1 mt-2">
            <p>RAM: 3 GB &nbsp;|&nbsp; CPU: 2 Kerne &nbsp;|&nbsp; Disk: 64 GB</p>
            <p>KVM-Beschleunigung: <span className="text-green-700">aktiv</span></p>
            <p>Autocom CDP+ USB-Passthrough: <span className="text-green-700">konfiguriert</span></p>
          </div>
          <button
            onClick={start}
            disabled={busy}
            className="mt-2 text-sm bg-blue-700 hover:bg-blue-600 disabled:opacity-50 text-white px-6 py-2 rounded"
          >
            {busy ? '⏳ VM wird gestartet...' : '▶ Windows-VM starten'}
          </button>
        </div>
      )}

      <div className="flex-shrink-0">
        <p className="text-xs text-gray-600">
          noVNC: <span className="text-gray-400">Port 8100</span> &nbsp;|&nbsp;
          RDP: <span className="text-gray-400">Port 3389</span> &nbsp;|&nbsp;
          KVM: <span className="text-gray-400">Intel Pentium Gold 8505</span>
        </p>
      </div>
    </div>
  )
}
