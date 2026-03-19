import { useEffect, useState } from 'react'
import { InstalledApp, launchApp, listApps } from '../api'

export default function AppsPage() {
  const [apps, setApps] = useState<InstalledApp[]>([])
  const [loading, setLoading] = useState(true)
  const [launching, setLaunching] = useState<string | null>(null)

  useEffect(() => {
    listApps()
      .then(setApps)
      .catch(console.error)
      .finally(() => setLoading(false))
  }, [])

  const handleLaunch = async (app: InstalledApp) => {
    setLaunching(app.exe)
    await launchApp(app.exe).catch((e) => alert(`Fehler: ${e.message}`))
    setTimeout(() => setLaunching(null), 2000)
  }

  if (loading) {
    return <p className="text-gray-500 text-sm animate-pulse">Lade App-Liste...</p>
  }

  if (apps.length === 0) {
    return (
      <div className="text-center py-20 text-gray-600">
        <p className="text-4xl mb-3">📭</p>
        <p>Keine installierten Apps gefunden.</p>
        <p className="text-sm mt-1">Installiere zuerst eine .exe oder .msi Datei.</p>
      </div>
    )
  }

  // Gruppiert nach Hersteller
  const byVendor = apps.reduce<Record<string, InstalledApp[]>>((acc, app) => {
    acc[app.vendor] = [...(acc[app.vendor] ?? []), app]
    return acc
  }, {})

  return (
    <div className="max-w-2xl space-y-6">
      <h1 className="text-lg font-semibold text-gray-200">Installierte Apps</h1>

      {Object.entries(byVendor).map(([vendor, vendorApps]) => (
        <div key={vendor}>
          <h2 className="text-xs text-gray-500 uppercase tracking-wider mb-2">{vendor}</h2>
          <div className="space-y-1">
            {vendorApps.map((app) => (
              <div
                key={app.exe}
                className="flex items-center justify-between bg-gray-900 border border-gray-800 rounded px-4 py-2"
              >
                <div>
                  <span className="text-sm text-white">{app.name}</span>
                  <span className="ml-2 text-xs text-gray-600 font-mono">{app.exe}</span>
                </div>
                <button
                  onClick={() => handleLaunch(app)}
                  disabled={launching === app.exe}
                  className="text-xs bg-green-700 hover:bg-green-600 disabled:opacity-50 text-white px-3 py-1 rounded"
                >
                  {launching === app.exe ? '⏳' : '▶ Starten'}
                </button>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
