/**
 * VehiclesPage — Fahrzeugverwaltung mit DTC-Diagnosehistorie.
 * Unterstützt mehrere Fahrzeuge, OBD2-Protokoll-Konfiguration und
 * Speichern von DTC-Sitzungen aus dem Live-Scan.
 */
import { useEffect, useState } from 'react'
import {
  createVehicle,
  deleteDtcSession,
  deleteVehicle,
  listVehicles,
  obdDtcs,
  obdStatus,
  saveDtcSession,
  updateVehicle,
  type DtcSession,
  type Vehicle,
  type VehicleInput,
} from '../api'

const PROTOCOL_LABELS: Record<string, string> = {
  auto:     'Auto-Detect',
  iso9141:  'ISO 9141-2 (K-Line)',
  elm327:   'ELM327',
}

const PROTOCOL_COLORS: Record<string, string> = {
  auto:    'bg-gray-800 text-gray-400',
  iso9141: 'bg-blue-950 text-blue-300',
  elm327:  'bg-green-950 text-green-300',
}

const EMPTY_FORM: VehicleInput = {
  name: '', make: '', model: '', year: new Date().getFullYear(),
  engine: '', obd_protocol: 'auto', vin: '', notes: '',
}

export default function VehiclesPage() {
  const [vehicles, setVehicles]           = useState<Vehicle[]>([])
  const [loading, setLoading]             = useState(true)
  const [selectedId, setSelectedId]       = useState<string | null>(null)
  const [editingId, setEditingId]         = useState<string | null>(null)  // null = add form
  const [showForm, setShowForm]           = useState(false)
  const [form, setForm]                   = useState<VehicleInput>(EMPTY_FORM)
  const [saving, setSaving]               = useState(false)
  const [error, setError]                 = useState<string | null>(null)

  // OBD2 Live-Status für "Jetzt scannen"-Button
  const [obdConnected, setObdConnected]   = useState(false)
  const [savingDtc, setSavingDtc]         = useState<string | null>(null)  // vehicle id

  const reload = () =>
    listVehicles()
      .then(setVehicles)
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false))

  useEffect(() => {
    reload()
    // OBD2-Status einmalig prüfen
    obdStatus().then((s) => setObdConnected(s.connected)).catch(() => {})
  }, [])

  const selectedVehicle = vehicles.find((v) => v.id === selectedId) ?? null

  const openAdd = () => {
    setEditingId(null)
    setForm(EMPTY_FORM)
    setShowForm(true)
  }

  const openEdit = (v: Vehicle) => {
    setEditingId(v.id)
    setForm({
      name: v.name, make: v.make, model: v.model, year: v.year,
      engine: v.engine, obd_protocol: v.obd_protocol, vin: v.vin, notes: v.notes,
    })
    setShowForm(true)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    setError(null)
    try {
      if (editingId) {
        const updated = await updateVehicle(editingId, form)
        setVehicles((vs) => vs.map((v) => v.id === editingId ? updated : v))
      } else {
        const created = await createVehicle(form)
        setVehicles((vs) => [...vs, created])
        setSelectedId(created.id)
      }
      setShowForm(false)
    } catch (e) {
      setError(String(e))
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = async (id: string) => {
    if (!confirm('Fahrzeug und gesamte DTC-Historie löschen?')) return
    await deleteVehicle(id).catch((e) => setError(String(e)))
    setVehicles((vs) => vs.filter((v) => v.id !== id))
    if (selectedId === id) setSelectedId(null)
  }

  const handleSaveDtcSession = async (vehicleId: string) => {
    setSavingDtc(vehicleId)
    try {
      const dtcs = await obdDtcs()
      const session = await saveDtcSession(vehicleId, {
        codes: dtcs.codes,
        notes: `Live-Scan via OBD2 Monitor`,
      })
      setVehicles((vs) => vs.map((v) =>
        v.id === vehicleId
          ? { ...v, dtc_history: [...v.dtc_history, session] }
          : v,
      ))
    } catch (e) {
      setError(String(e))
    } finally {
      setSavingDtc(null)
    }
  }

  const handleDeleteSession = async (vehicleId: string, idx: number) => {
    if (!confirm('Diese Diagnosesitzung löschen?')) return
    await deleteDtcSession(vehicleId, idx).catch((e) => setError(String(e)))
    setVehicles((vs) => vs.map((v) =>
      v.id === vehicleId
        ? { ...v, dtc_history: v.dtc_history.filter((_, i) => i !== idx) }
        : v,
    ))
  }

  if (loading) return <p className="text-gray-500 text-sm animate-pulse">Lade Fahrzeuge...</p>

  return (
    <div className="max-w-4xl space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold text-gray-200">Fahrzeuge</h1>
        <button
          onClick={openAdd}
          className="text-sm px-3 py-1.5 rounded bg-wine-500 hover:bg-wine-600 text-white transition-colors"
        >
          + Neues Fahrzeug
        </button>
      </div>

      {error && (
        <div className="text-xs text-red-400 bg-red-950 border border-red-900 rounded px-3 py-2">
          {error}
          <button onClick={() => setError(null)} className="ml-3 text-red-300 hover:text-white">✕</button>
        </div>
      )}

      {/* Add / Edit Form */}
      {showForm && (
        <VehicleForm
          form={form}
          onChange={setForm}
          onSubmit={handleSubmit}
          onCancel={() => setShowForm(false)}
          saving={saving}
          isEdit={editingId !== null}
        />
      )}

      {/* Fahrzeugliste */}
      {vehicles.length === 0 && !showForm ? (
        <div className="bg-gray-900 border border-gray-800 rounded p-8 text-center">
          <p className="text-gray-600 text-sm">Noch keine Fahrzeuge eingetragen.</p>
          <button onClick={openAdd} className="mt-3 text-xs text-wine-400 hover:text-wine-300">
            + Erstes Fahrzeug hinzufügen
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {vehicles.map((v) => (
            <VehicleCard
              key={v.id}
              vehicle={v}
              selected={selectedId === v.id}
              obdConnected={obdConnected}
              savingDtc={savingDtc === v.id}
              onSelect={() => setSelectedId(selectedId === v.id ? null : v.id)}
              onEdit={() => openEdit(v)}
              onDelete={() => handleDelete(v.id)}
              onSaveDtc={() => handleSaveDtcSession(v.id)}
            />
          ))}
        </div>
      )}

      {/* Detail-Panel für ausgewähltes Fahrzeug */}
      {selectedVehicle && (
        <VehicleDetail
          vehicle={selectedVehicle}
          onDeleteSession={(idx) => handleDeleteSession(selectedVehicle.id, idx)}
        />
      )}
    </div>
  )
}


// ── Fahrzeug-Karte ────────────────────────────────────────────────────────────

function VehicleCard({
  vehicle: v, selected, obdConnected, savingDtc,
  onSelect, onEdit, onDelete, onSaveDtc,
}: {
  vehicle: Vehicle
  selected: boolean
  obdConnected: boolean
  savingDtc: boolean
  onSelect: () => void
  onEdit: () => void
  onDelete: () => void
  onSaveDtc: () => void
}) {
  const lastSession = v.dtc_history[v.dtc_history.length - 1]
  const lastDate = lastSession
    ? new Date(lastSession.date).toLocaleDateString('de-DE')
    : null
  const totalDtcs = lastSession?.codes.length ?? 0

  return (
    <div
      className={`bg-gray-900 border rounded p-4 space-y-3 cursor-pointer transition-colors ${
        selected ? 'border-wine-500' : 'border-gray-800 hover:border-gray-700'
      }`}
      onClick={onSelect}
    >
      {/* Kopfzeile */}
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-sm font-semibold text-gray-200 truncate">
            {v.name || `${v.make} ${v.model}`}
          </p>
          <p className="text-xs text-gray-500 truncate">
            {v.make} {v.model} · {v.year > 0 ? v.year : '—'}
          </p>
        </div>
        <span className={`text-xs px-1.5 py-0.5 rounded flex-shrink-0 font-mono ${PROTOCOL_COLORS[v.obd_protocol]}`}>
          {v.obd_protocol === 'iso9141' ? 'K-Line' : v.obd_protocol.toUpperCase()}
        </span>
      </div>

      {/* Motor */}
      {v.engine && (
        <p className="text-xs text-gray-600">{v.engine}</p>
      )}

      {/* Letzter Scan */}
      <div className="border-t border-gray-800 pt-2 flex items-center justify-between">
        <p className="text-xs text-gray-600">
          {lastDate
            ? <>Scan: <span className="text-gray-400">{lastDate}</span></>
            : 'Noch kein Scan'}
        </p>
        {lastDate && (
          totalDtcs === 0
            ? <span className="text-xs text-green-500">✓ Keine DTCs</span>
            : <span className="text-xs text-red-400">{totalDtcs} DTC{totalDtcs > 1 ? 's' : ''}</span>
        )}
      </div>

      {/* Aktionen — stoppt Event-Bubbling */}
      <div className="flex gap-2" onClick={(e) => e.stopPropagation()}>
        {obdConnected && (
          <button
            onClick={onSaveDtc}
            disabled={savingDtc}
            className="text-xs px-2 py-1 rounded bg-blue-900 text-blue-300 hover:bg-blue-800 disabled:opacity-40 flex-1"
          >
            {savingDtc ? '...' : '📡 DTC scannen'}
          </button>
        )}
        <button
          onClick={onEdit}
          className="text-xs px-2 py-1 rounded bg-gray-800 text-gray-400 hover:text-gray-200"
        >
          ✎
        </button>
        <button
          onClick={onDelete}
          className="text-xs px-2 py-1 rounded bg-gray-800 text-red-400 hover:bg-red-950"
        >
          ✕
        </button>
      </div>
    </div>
  )
}


// ── Detail-Panel ──────────────────────────────────────────────────────────────

function VehicleDetail({
  vehicle: v, onDeleteSession,
}: {
  vehicle: Vehicle
  onDeleteSession: (idx: number) => void
}) {
  return (
    <div className="bg-gray-900 border border-gray-800 rounded p-4 space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-medium text-gray-300">
          {v.name || `${v.make} ${v.model}`} — Diagnosehistorie
        </h2>
        <div className="flex gap-3 text-xs text-gray-600">
          {v.vin && <span>VIN: <span className="text-gray-400 font-mono">{v.vin}</span></span>}
          <span className={`px-1.5 py-0.5 rounded font-mono ${PROTOCOL_COLORS[v.obd_protocol]}`}>
            {PROTOCOL_LABELS[v.obd_protocol]}
          </span>
        </div>
      </div>

      {v.notes && (
        <p className="text-xs text-gray-500 italic">{v.notes}</p>
      )}

      {v.dtc_history.length === 0 ? (
        <p className="text-xs text-gray-600">Noch keine Diagnosesitzungen gespeichert.</p>
      ) : (
        <div className="space-y-2">
          {[...v.dtc_history].reverse().map((session, reversedIdx) => {
            const realIdx = v.dtc_history.length - 1 - reversedIdx
            return (
              <DtcSessionRow
                key={realIdx}
                session={session}
                onDelete={() => onDeleteSession(realIdx)}
              />
            )
          })}
        </div>
      )}
    </div>
  )
}


// ── DTC-Sitzungszeile ─────────────────────────────────────────────────────────

function DtcSessionRow({ session, onDelete }: { session: DtcSession; onDelete: () => void }) {
  const date = new Date(session.date)
  const hasCodes = session.codes.length > 0
  return (
    <div className="border border-gray-800 rounded p-3 space-y-2">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <span className="text-xs text-gray-500">
            {date.toLocaleDateString('de-DE')} {date.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })}
          </span>
          {session.odometer && (
            <span className="text-xs text-gray-600">{session.odometer.toLocaleString()} km</span>
          )}
          {session.notes && (
            <span className="text-xs text-gray-600 italic">{session.notes}</span>
          )}
        </div>
        <div className="flex items-center gap-2">
          {hasCodes
            ? <span className="text-xs text-red-400">{session.codes.length} DTC{session.codes.length > 1 ? 's' : ''}</span>
            : <span className="text-xs text-green-500">✓ Keine DTCs</span>
          }
          <button
            onClick={onDelete}
            className="text-xs text-gray-700 hover:text-red-400 px-1"
          >
            ✕
          </button>
        </div>
      </div>
      {hasCodes && (
        <div className="flex flex-wrap gap-1.5">
          {session.codes.map((dtc) => (
            <span
              key={dtc.code}
              title={dtc.description || dtc.code}
              className="text-xs font-mono px-2 py-0.5 rounded bg-red-950 text-red-400 border border-red-900 cursor-help"
            >
              {dtc.code}
            </span>
          ))}
        </div>
      )}
    </div>
  )
}


// ── Formular ──────────────────────────────────────────────────────────────────

function VehicleForm({
  form, onChange, onSubmit, onCancel, saving, isEdit,
}: {
  form: VehicleInput
  onChange: (f: VehicleInput) => void
  onSubmit: (e: React.FormEvent) => void
  onCancel: () => void
  saving: boolean
  isEdit: boolean
}) {
  const field = (key: keyof VehicleInput) => ({
    value: String(form[key]),
    onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) =>
      onChange({ ...form, [key]: key === 'year' ? Number(e.target.value) : e.target.value }),
  })

  return (
    <form
      onSubmit={onSubmit}
      className="bg-gray-900 border border-gray-700 rounded p-4 space-y-4"
    >
      <h2 className="text-sm font-medium text-gray-300">
        {isEdit ? 'Fahrzeug bearbeiten' : 'Neues Fahrzeug'}
      </h2>

      <div className="grid grid-cols-2 gap-3">
        <FormField label="Anzeigename (optional)">
          <input placeholder="Mein Suzuki" className={inputCls} {...field('name')} />
        </FormField>
        <FormField label="Hersteller *">
          <input placeholder="Suzuki" required className={inputCls} {...field('make')} />
        </FormField>
        <FormField label="Modell *">
          <input placeholder="Wagon R+" required className={inputCls} {...field('model')} />
        </FormField>
        <FormField label="Baujahr">
          <input type="number" min={1970} max={2099} className={inputCls} {...field('year')} />
        </FormField>
        <FormField label="Motor">
          <input placeholder="M13A 1.3L MPI" className={inputCls} {...field('engine')} />
        </FormField>
        <FormField label="OBD2-Protokoll">
          <select className={inputCls} {...field('obd_protocol')}>
            <option value="auto">Auto-Detect</option>
            <option value="iso9141">ISO 9141-2 (K-Line)</option>
            <option value="elm327">ELM327</option>
          </select>
        </FormField>
        <FormField label="VIN (optional)">
          <input placeholder="WA1LFAFP4BA..." className={`${inputCls} font-mono`} {...field('vin')} />
        </FormField>
      </div>

      <FormField label="Notizen">
        <textarea
          rows={2}
          placeholder="Bekannte Probleme, Besonderheiten..."
          className={`${inputCls} resize-none`}
          {...field('notes')}
        />
      </FormField>

      <div className="flex gap-2 justify-end">
        <button
          type="button"
          onClick={onCancel}
          className="text-xs px-3 py-1.5 rounded bg-gray-800 text-gray-400 hover:text-gray-200"
        >
          Abbrechen
        </button>
        <button
          type="submit"
          disabled={saving}
          className="text-xs px-3 py-1.5 rounded bg-wine-500 hover:bg-wine-600 text-white disabled:opacity-50"
        >
          {saving ? '...' : isEdit ? 'Speichern' : 'Erstellen'}
        </button>
      </div>
    </form>
  )
}

function FormField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1">
      <label className="text-xs text-gray-500">{label}</label>
      {children}
    </div>
  )
}

const inputCls =
  'w-full bg-gray-800 border border-gray-700 rounded px-2 py-1.5 text-sm text-gray-200 ' +
  'placeholder-gray-600 focus:outline-none focus:border-gray-500'
