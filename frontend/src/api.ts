/**
 * API-Client für das Wine Manager Backend.
 * Alle Pfade werden relativ zu /api geroutet (via Nginx-Proxy in Produktion).
 */

export const BASE = '/api'

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

export interface UsbIpRemoteStatus {
  configured: boolean
  reachable: boolean
  host: string
  connection_type: 'wifi' | 'ethernet' | 'both' | null
}

// ── OBD2 ───────────────────────────────────────────────────────────────────

export interface ObdData {
  rpm: number | null
  speed: number | null
  coolant_temp: number | null
  throttle: number | null
  engine_load: number | null
  short_fuel_trim: number | null
  long_fuel_trim: number | null
  battery_voltage: number | null
  timestamp_ms: number
}

export interface ObdStatus {
  connected: boolean
  protocol: 'elm327' | 'iso9141' | null
  port: string | null
  error: string | null
}

export interface ObdDtcs {
  codes: { code: string; description: string }[]
  count: number
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

/** Upload mit Fortschritts-Callback (0–100). Nutzt XHR statt fetch. */
export function uploadFileWithProgress(
  file: File,
  onProgress: (percent: number) => void,
): Promise<UploadedFile> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    const form = new FormData()
    form.append('file', file)

    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) onProgress(Math.round((e.loaded / e.total) * 100))
    }

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve(JSON.parse(xhr.responseText))
      } else {
        reject(new Error(xhr.responseText || `HTTP ${xhr.status}`))
      }
    }
    xhr.onerror = () => reject(new Error('Netzwerkfehler beim Upload'))

    xhr.open('POST', `${BASE}/upload`)
    xhr.send(form)
  })
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

export async function usbIpRemoteStatus(): Promise<UsbIpRemoteStatus> {
  const r = await fetch(`${BASE}/usbip/remote/status`)
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function obdStatus(): Promise<ObdStatus> {
  const r = await fetch(`${BASE}/obd/status`)
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function obdData(): Promise<ObdData> {
  const r = await fetch(`${BASE}/obd/data`)
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function obdDtcs(): Promise<ObdDtcs> {
  const r = await fetch(`${BASE}/obd/dtcs`)
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function obdClearDtcs(): Promise<{ success: boolean; message: string }> {
  const r = await fetch(`${BASE}/obd/clear-dtcs`, { method: 'POST' })
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

/** SSE-Stream: ruft onData bei jedem OBD2-Update auf (~2Hz), gibt cleanup-Funktion zurück */
export function obdStream(onData: (d: ObdData) => void): () => void {
  const es = new EventSource(`${BASE}/obd/stream`)
  es.onmessage = (e) => {
    try { onData(JSON.parse(e.data)) } catch { /* ignore parse errors */ }
  }
  es.onerror = () => es.close()
  return () => es.close()
}

// ── WiFi-Adapter ────────────────────────────────────────────────────────────

export interface WifiAdapterInfo {
  host: string
  port: number
  reachable: boolean
  protocol: 'socketcan' | 'elm327'
  name: string
}

export interface WifiAdapterStatus {
  wican: WifiAdapterInfo
  vgate: WifiAdapterInfo
}

export async function wifiAdapterStatus(): Promise<WifiAdapterStatus> {
  const r = await fetch(`${BASE}/wifi-adapter/status`)
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

// ── Fahrzeuge ───────────────────────────────────────────────────────────────

export interface DtcSession {
  date: string
  codes: { code: string; description: string }[]
  odometer?: number | null
  notes: string
}

export interface Vehicle {
  id: string
  name: string
  make: string
  model: string
  year: number
  engine: string
  obd_protocol: 'auto' | 'iso9141' | 'elm327'
  vin: string
  notes: string
  dtc_history: DtcSession[]
  created_at: string
}

export type VehicleInput = Omit<Vehicle, 'id' | 'dtc_history' | 'created_at'>

export async function listVehicles(): Promise<Vehicle[]> {
  const r = await fetch(`${BASE}/vehicles`)
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function createVehicle(data: VehicleInput): Promise<Vehicle> {
  const r = await fetch(`${BASE}/vehicles`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function updateVehicle(id: string, data: Partial<VehicleInput>): Promise<Vehicle> {
  const r = await fetch(`${BASE}/vehicles/${encodeURIComponent(id)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function deleteVehicle(id: string): Promise<void> {
  const r = await fetch(`${BASE}/vehicles/${encodeURIComponent(id)}`, { method: 'DELETE' })
  if (!r.ok) throw new Error(await r.text())
}

export async function saveDtcSession(
  vehicleId: string,
  data: { codes: DtcSession['codes']; odometer?: number; notes?: string },
): Promise<DtcSession> {
  const r = await fetch(`${BASE}/vehicles/${encodeURIComponent(vehicleId)}/dtc-session`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}

export async function deleteDtcSession(vehicleId: string, sessionIndex: number): Promise<void> {
  const r = await fetch(
    `${BASE}/vehicles/${encodeURIComponent(vehicleId)}/dtc-session/${sessionIndex}`,
    { method: 'DELETE' },
  )
  if (!r.ok) throw new Error(await r.text())
}

export async function winetricksInstall(component: string): Promise<InstallResult> {
  const params = new URLSearchParams({ component })
  const r = await fetch(`${BASE}/winetricks/install?${params}`, { method: 'POST' })
  if (!r.ok) throw new Error(await r.text())
  return r.json()
}
