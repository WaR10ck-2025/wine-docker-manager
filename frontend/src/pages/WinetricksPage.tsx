import { useEffect, useState } from 'react'
import { winetricksInstall, winetricksPresets } from '../api'
import LogStream from '../components/LogStream'

const CATEGORIES: Record<string, string[]> = {
  '.NET Framework': ['dotnet48', 'dotnet40', 'dotnet35'],
  'Visual C++': ['vcrun2022', 'vcrun2019', 'vcrun2017', 'vcrun2015'],
  'DirectX / DXVK': ['d3dx9', 'dxvk'],
  'Sonstiges': ['corefonts', 'ie8', 'mfc42'],
}

export default function WinetricksPage() {
  const [presets, setPresets] = useState<string[]>([])
  const [custom, setCustom] = useState('')
  const [activePid, setActivePid] = useState<number | null>(null)
  const [installing, setInstalling] = useState<string | null>(null)
  const [doneMsg, setDoneMsg] = useState<string | null>(null)

  useEffect(() => {
    winetricksPresets().then((r) => setPresets(r.presets)).catch(console.error)
  }, [])

  const install = async (component: string) => {
    setInstalling(component)
    setDoneMsg(null)
    const result = await winetricksInstall(component).catch((e) => {
      alert(`Fehler: ${e.message}`)
      return null
    })
    setInstalling(null)
    if (result) setActivePid(result.pid)
  }

  return (
    <div className="max-w-2xl space-y-6">
      <h1 className="text-lg font-semibold text-gray-200">Winetricks — Laufzeiten installieren</h1>

      {Object.entries(CATEGORIES).map(([cat, items]) => (
        <div key={cat}>
          <h2 className="text-xs text-gray-500 uppercase tracking-wider mb-2">{cat}</h2>
          <div className="flex flex-wrap gap-2">
            {items.map((item) => (
              <button
                key={item}
                onClick={() => install(item)}
                disabled={installing !== null}
                className="text-xs border border-gray-700 hover:border-wine-500 hover:text-wine-500 disabled:opacity-40 rounded px-3 py-1.5 transition-colors"
              >
                {installing === item ? '⏳ ' : ''}{item}
              </button>
            ))}
          </div>
        </div>
      ))}

      {/* Benutzerdefinierte Komponente */}
      <div>
        <h2 className="text-xs text-gray-500 uppercase tracking-wider mb-2">Benutzerdefiniert</h2>
        <div className="flex gap-2">
          <input
            value={custom}
            onChange={(e) => setCustom(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && custom && install(custom)}
            placeholder="z.B. vcrun6, mfc140..."
            className="flex-1 bg-gray-900 border border-gray-700 rounded px-3 py-1.5 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-wine-500"
          />
          <button
            onClick={() => custom && install(custom)}
            disabled={!custom || installing !== null}
            className="text-xs bg-wine-500 hover:bg-wine-600 disabled:opacity-40 text-white px-4 py-1.5 rounded"
          >
            Installieren
          </button>
        </div>
      </div>

      {doneMsg && (
        <div className="text-sm text-green-400 border border-green-800 rounded p-2">{doneMsg}</div>
      )}
      <LogStream
        pid={activePid}
        onDone={(code) =>
          setDoneMsg(code === 0 ? '✓ Komponente installiert' : `⚠ Beendet mit Code ${code}`)
        }
      />
    </div>
  )
}
