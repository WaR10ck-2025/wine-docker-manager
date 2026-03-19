/**
 * API-Client für das Wine Manager Backend.
 * Alle Pfade werden relativ zu /api geroutet (via Nginx-Proxy in Produktion).
 */

const BASE = '/api'

export interface UploadedFile {
  filename: string
  size: number
}

export interface InstalledApp {
  name: string
  vendor: string
  exe: string
  path: string
}

export interface InstallResult {
  pid: number
  cmd: string[]
  filename: string
}

export interface ProcessStatus {
  pid: number
  running: boolean
  exit_code: number | null
  log_lines: number
}

// ── Uploads ────────────────────────────────────────────────────────────────

export async function listUploads(): Promise<UploadedFile[]> {
  const r = await fetch(`${BASE}/uploads`)
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function uploadFile(file: File): Promise<UploadedFile> {
  const form = new FormData()
  form.append('file', file)
  const r = await fetch(`${BASE}/upload`, { method: 'POST', body: form })
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function deleteUpload(filename: string): Promise<void> {
  const r = await fetch(`${BASE}/uploads/${encodeURIComponent(filename)}`, { method: 'DELETE' })
  if (!r.ok) throw new Error(await r.text())
}

// ── Installation ───────────────────────────────────────────────────────────

export async function installApp(filename: string, method = 'auto'): Promise<InstallResult> {
  const params = new URLSearchParams({ filename, method })
  const r = await fetch(`${BASE}/install?${params}`, { method: 'POST' })
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function processStatus(pid: number): Promise<ProcessStatus> {
  const r = await fetch(`${BASE}/status/${pid}`)
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

/** SSE-Stream: ruft onLine für jede Zeile auf, gibt cleanup-Funktion zurück */
export function streamLogs(pid: number, onLine: (line: string) => void): () => void {
  const es = new EventSource(`${BASE}/logs/${pid}`)
  es.onmessage = (e) => onLine(JSON.parse(e.data))
  es.onerror = () => es.close()
  return () => es.close()
}

// ── Apps ───────────────────────────────────────────────────────────────────

export async function listApps(): Promise<InstalledApp[]> {
  const r = await fetch(`${BASE}/apps`)
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function launchApp(exePath: string): Promise<{ pid: number }> {
  const params = new URLSearchParams({ exe_path: exePath })
  const r = await fetch(`${BASE}/launch?${params}`, { method: 'POST' })
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

// ── Winetricks ─────────────────────────────────────────────────────────────

export async function winetricksPresets(): Promise<{ presets: string[] }> {
  const r = await fetch(`${BASE}/winetricks/presets`)
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function winetricksInstall(component: string): Promise<InstallResult> {
  const params = new URLSearchParams({ component })
  const r = await fetch(`${BASE}/winetricks/install?${params}`, { method: 'POST' })
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}
