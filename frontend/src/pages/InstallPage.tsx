import { useCallback, useEffect, useRef, useState } from 'react'
import { deleteUpload, installApp, listUploads, uploadFile, UploadedFile } from '../api'
import LogStream from '../components/LogStream'

function formatBytes(b: number) {
  if (b < 1024) return `${b} B`
  if (b < 1024 ** 2) return `${(b / 1024).toFixed(1)} KB`
  return `${(b / 1024 ** 2).toFixed(1)} MB`
}

export default function InstallPage() {
  const [files, setFiles] = useState<UploadedFile[]>([])
  const [dragging, setDragging] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [activePid, setActivePid] = useState<number | null>(null)
  const [doneMsg, setDoneMsg] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  const refresh = () => listUploads().then(setFiles).catch(console.error)

  useEffect(() => { refresh() }, [])

  const handleFiles = useCallback(async (fileList: FileList) => {
    setUploading(true)
    for (const f of Array.from(fileList)) {
      await uploadFile(f).catch((e) => alert(`Upload fehlgeschlagen: ${e.message}`))
    }
    setUploading(false)
    refresh()
  }, [])

  const onDrop = (e: React.DragEvent) => {
    e.preventDefault()
    setDragging(false)
    if (e.dataTransfer.files.length) handleFiles(e.dataTransfer.files)
  }

  const startInstall = async (filename: string, method: string) => {
    setDoneMsg(null)
    const result = await installApp(filename, method).catch((e) => {
      alert(`Fehler: ${e.message}`)
      return null
    })
    if (result) setActivePid(result.pid)
  }

  return (
    <div className="max-w-2xl space-y-6">
      <h1 className="text-lg font-semibold text-gray-200">Software installieren</h1>

      {/* Drop-Zone */}
      <div
        onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        onClick={() => fileRef.current?.click()}
        className={`border-2 border-dashed rounded-lg p-10 text-center cursor-pointer transition-colors ${
          dragging ? 'border-wine-500 bg-wine-500/10' : 'border-gray-700 hover:border-gray-500'
        }`}
      >
        <p className="text-gray-400 text-sm">
          {uploading ? '⏳ Lädt hoch...' : '.exe / .msi hierher ziehen oder klicken'}
        </p>
        <input
          ref={fileRef}
          type="file"
          accept=".exe,.msi,.zip"
          multiple
          className="hidden"
          onChange={(e) => e.target.files && handleFiles(e.target.files)}
        />
      </div>

      {/* Dateiliste */}
      {files.length > 0 && (
        <div className="space-y-2">
          <h2 className="text-sm text-gray-400 uppercase tracking-wider">Hochgeladene Dateien</h2>
          {files.map((f) => (
            <div
              key={f.filename}
              className="flex items-center justify-between bg-gray-900 border border-gray-800 rounded px-4 py-2"
            >
              <div>
                <span className="text-sm text-white">{f.filename}</span>
                <span className="ml-2 text-xs text-gray-500">{formatBytes(f.size)}</span>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => startInstall(f.filename, 'auto')}
                  className="text-xs bg-wine-500 hover:bg-wine-600 text-white px-3 py-1 rounded"
                >
                  Installieren
                </button>
                <button
                  onClick={() => startInstall(f.filename, 'wine')}
                  className="text-xs bg-gray-700 hover:bg-gray-600 text-white px-3 py-1 rounded"
                >
                  wine direkt
                </button>
                <button
                  onClick={() => deleteUpload(f.filename).then(refresh)}
                  className="text-xs text-gray-500 hover:text-red-400 px-2 py-1"
                >
                  ✕
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Log-Stream */}
      {doneMsg && (
        <div className="text-sm text-green-400 border border-green-800 rounded p-2">{doneMsg}</div>
      )}
      <LogStream
        pid={activePid}
        onDone={(code) =>
          setDoneMsg(code === 0 ? '✓ Installation abgeschlossen' : `⚠ Beendet mit Code ${code}`)
        }
      />
    </div>
  )
}
