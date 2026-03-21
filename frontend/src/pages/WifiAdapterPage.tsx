/**
 * WifiAdapterPage — Pfad B: WiFi-native OBD2-Adapter via GL.iNet Router-Bridge.
 * Zeigt Status + Konfigurationsanleitungen für WiCAN Pro und Vgate iCar 2 WiFi.
 */
import { useEffect, useState } from 'react'
import { wifiAdapterStatus, type WifiAdapterStatus } from '../api'

type AdapterTab = 'wican' | 'vgate'

export default function WifiAdapterPage() {
  const [status, setStatus]       = useState<WifiAdapterStatus | null>(null)
  const [loading, setLoading]     = useState(true)
  const [activeTab, setActiveTab] = useState<AdapterTab>('wican')

  const fetchStatus = () =>
    wifiAdapterStatus()
      .then(setStatus)
      .catch(console.error)
      .finally(() => setLoading(false))

  useEffect(() => {
    fetchStatus()
    const t = setInterval(fetchStatus, 5000)
    return () => clearInterval(t)
  }, [])

  if (loading) return <p className="text-gray-500 text-sm animate-pulse">Lade Adapter-Status...</p>

  return (
    <div className="max-w-2xl space-y-6">
      <div className="space-y-1">
        <h1 className="text-lg font-semibold text-gray-200">WiFi OBD2 — Pfad B</h1>
        <p className="text-xs text-gray-600">
          GL.iNet Router bridgt WiFi-Adapter transparent ins LAN — kein Treiber auf dem Router nötig.
        </p>
      </div>

      {/* Tab-Switcher */}
      <div className="flex gap-1 border-b border-gray-800">
        <TabBtn active={activeTab === 'wican'} onClick={() => setActiveTab('wican')}>
          📡 WiCAN Pro
          {status && (
            <span className={`ml-2 w-1.5 h-1.5 rounded-full inline-block ${
              status.wican.reachable ? 'bg-green-500' : 'bg-gray-600'
            }`} />
          )}
        </TabBtn>
        <TabBtn active={activeTab === 'vgate'} onClick={() => setActiveTab('vgate')}>
          📶 Vgate iCar 2
          {status && (
            <span className={`ml-2 w-1.5 h-1.5 rounded-full inline-block ${
              status.vgate.reachable ? 'bg-green-500' : 'bg-gray-600'
            }`} />
          )}
        </TabBtn>
      </div>

      {/* ── Tab: WiCAN Pro ─────────────────────────────────────────────────── */}
      {activeTab === 'wican' && status && (
        <div className="space-y-5">
          <p className="text-xs text-gray-500">
            WiCAN Pro (ESP32-C3) — WiFi + J2534 + Linux SocketCAN. Steckt direkt im OBD2-Port.
            Verbindet sich mit dem Router-WLAN und ist dann via TCP erreichbar.
          </p>

          {/* Status-Karte */}
          <AdapterStatusCard info={status.wican} protocolLabel="SocketCAN TCP" />

          {/* Verbindung — python-can */}
          <div className="space-y-3">
            <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wider">
              Verbindung (python-can)
            </h2>
            <div className="bg-gray-900 border border-gray-800 rounded p-4 space-y-2">
              <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs whitespace-pre">{`import can
bus = can.interface.Bus(
    interface='socketcand', channel='can0',
    host='${status.wican.host}', port=${status.wican.port}
)
print('WiCAN Pro OK:', bus.channel_info)
bus.shutdown()`}</code>
              <p className="text-xs text-gray-600">
                Paket: <span className="text-gray-400 font-mono">pip install python-can</span>
              </p>
            </div>
          </div>

          {/* Setup-Schritte */}
          <div className="space-y-3">
            <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wider">
              Ersteinrichtung
            </h2>
            <div className="bg-gray-900 border border-gray-800 rounded p-4 space-y-4 text-sm">
              <Step n={1} title="WiCAN Pro Web-UI öffnen (während mit WiCAN-AP verbunden)">
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
                  http://192.168.4.1
                </code>
              </Step>
              <Step n={2} title="WiFi-Modus: Station → Router-SSID eintragen">
                <p className="text-xs text-gray-500">
                  WiFi → Mode: <span className="text-gray-300">Station</span>&nbsp;|&nbsp;
                  SSID: <span className="text-gray-300">GL-BE3600-AP</span>&nbsp;|&nbsp;
                  Passwort: Router-WLAN-Passwort
                </p>
              </Step>
              <Step n={3} title="DHCP-Reservation auf GL.iNet Router">
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs whitespace-pre">{`ssh root@192.168.10.194
uci add dhcp host
uci set dhcp.@host[-1].mac='<WiCAN-MAC>'
uci set dhcp.@host[-1].ip='${status.wican.host}'
uci commit dhcp && /etc/init.d/dnsmasq restart`}</code>
              </Step>
              <Step n={4} title="Verbindung prüfen">
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
                  ping {status.wican.host}
                </code>
                <p className="text-xs text-gray-600 mt-1">
                  Status-Indikator oben wechselt auf grün wenn Port {status.wican.port} erreichbar.
                </p>
              </Step>
            </div>
          </div>

          {/* Protokoll-Info */}
          <div className="grid grid-cols-2 gap-3 text-xs">
            <InfoCell label="Adapter" value="WiCAN Pro (ESP32-C3)" />
            <InfoCell label="Protokoll" value="SocketCAN + J2534" />
            <InfoCell label="Firmware" value="meatpiHQ/wican-fw (Open Source)" />
            <InfoCell label="Preis" value="~€50–80" />
          </div>
        </div>
      )}

      {/* ── Tab: Vgate iCar 2 ──────────────────────────────────────────────── */}
      {activeTab === 'vgate' && status && (
        <div className="space-y-5">
          <p className="text-xs text-gray-500">
            Vgate iCar 2 WiFi — ELM327 V2.x über TCP. Günstig, kein J2534.
            Ideal für Standard-OBD2 (Mode 01/02/03/04) via python-obd.
          </p>

          {/* Warnhinweis ELM327 */}
          <div className="bg-yellow-950 border border-yellow-900 rounded px-3 py-2 text-xs text-yellow-300">
            ⚠️ ELM327 only — kein J2534, kein UDS/ISO-TP. Für Volvo Tiefdiagnose: WiCAN Pro nutzen.
          </div>

          {/* Status-Karte */}
          <AdapterStatusCard info={status.vgate} protocolLabel="ELM327 TCP" />

          {/* Verbindung — python-obd */}
          <div className="space-y-3">
            <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wider">
              Verbindung (python-obd)
            </h2>
            <div className="bg-gray-900 border border-gray-800 rounded p-4 space-y-2">
              <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs whitespace-pre">{`import obd
conn = obd.OBD("${status.vgate.host}", portstr="${status.vgate.port}", timeout=10)
print("Status:", conn.status())
rpm = conn.query(obd.commands.RPM)
print(f"Drehzahl: {rpm.value}")`}</code>
              <p className="text-xs text-gray-600">
                Paket: <span className="text-gray-400 font-mono">pip install obd</span>
              </p>
            </div>
          </div>

          {/* Setup-Schritte */}
          <div className="space-y-3">
            <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wider">
              Ersteinrichtung
            </h2>
            <div className="bg-gray-900 border border-gray-800 rounded p-4 space-y-4 text-sm">
              <Step n={1} title="Vgate App → WiFi konfigurieren">
                <p className="text-xs text-gray-500">
                  Vgate Pro App (Android/iOS) → Settings → WiFi →
                  SSID: <span className="text-gray-300">GL-BE3600-AP</span> → Save
                </p>
                <p className="text-xs text-gray-600 mt-1">
                  Alternativ: Browser http://192.168.0.10 (während mit V-LINK verbunden)
                </p>
              </Step>
              <Step n={2} title="DHCP-Reservation auf GL.iNet Router">
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs whitespace-pre">{`ssh root@192.168.10.194
uci add dhcp host
uci set dhcp.@host[-1].mac='<iCar2-MAC>'
uci set dhcp.@host[-1].ip='${status.vgate.host}'
uci commit dhcp && /etc/init.d/dnsmasq restart`}</code>
              </Step>
              <Step n={3} title="Verbindung prüfen">
                <code className="block bg-black rounded px-3 py-2 text-green-400 text-xs">
                  ping {status.vgate.host}
                </code>
              </Step>
            </div>
          </div>

          {/* Protokoll-Info */}
          <div className="grid grid-cols-2 gap-3 text-xs">
            <InfoCell label="Adapter" value="Vgate iCar 2 WiFi" />
            <InfoCell label="Protokoll" value="ELM327 V2.x (kein J2534)" />
            <InfoCell label="OBD2 Modi" value="01 02 03 04 07 09" />
            <InfoCell label="Preis" value="~€20–40" />
          </div>
        </div>
      )}

      {/* Architektur-Hinweis */}
      <div className="bg-gray-900 border border-gray-800 rounded p-3 space-y-1">
        <p className="text-xs text-gray-500 font-medium">Pfad B — WiFi-Bridge Architektur</p>
        <p className="text-xs text-gray-600">
          GL.iNet Router bridgt alle WiFi-Clients automatisch ins LAN (br-lan).
          Kein Treiber auf dem Router nötig — der Server verbindet sich direkt per TCP.
        </p>
        <div className="font-mono text-xs text-gray-700 pt-1">
          Auto → WiFi-Adapter → Router (Bridge) → LAN → Server (TCP direkt)
        </div>
      </div>
    </div>
  )
}


// ── Hilfs-Komponenten ─────────────────────────────────────────────────────────

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

function AdapterStatusCard({ info, protocolLabel }: {
  info: { host: string; port: number; reachable: boolean }
  protocolLabel: string
}) {
  return (
    <div className="bg-gray-900 border border-gray-800 rounded p-4">
      <div className="flex items-center gap-3">
        <span className={`w-2.5 h-2.5 rounded-full flex-shrink-0 ${
          info.reachable ? 'bg-green-500' : 'bg-red-500'
        }`} />
        <div className="flex-1">
          <p className="text-sm text-gray-300">
            {info.reachable ? `Erreichbar — ${info.host}:${info.port}` : `Nicht erreichbar — ${info.host}:${info.port}`}
          </p>
          {!info.reachable && (
            <p className="text-xs text-gray-600 mt-0.5">
              Adapter eingesteckt? Im Router-WLAN eingebucht? DHCP-Reservation gesetzt?
            </p>
          )}
        </div>
        <span className="text-xs px-2 py-0.5 rounded bg-blue-900 text-blue-300 font-mono flex-shrink-0">
          {protocolLabel}
        </span>
      </div>
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

function InfoCell({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-gray-900 border border-gray-800 rounded p-2 space-y-0.5">
      <p className="text-gray-600">{label}</p>
      <p className="text-gray-300">{value}</p>
    </div>
  )
}
