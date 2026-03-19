/**
 * DesktopPage — Bettet den noVNC-Desktop per iframe ein.
 * Der noVNC-Server läuft auf Port 8080 des wine-desktop Containers.
 */
export default function DesktopPage() {
  // Im Browser: wine-desktop ist über den Docker-internen Proxy erreichbar
  const novncUrl = `http://${window.location.hostname}:8080/vnc.html?autoconnect=true&resize=scale`

  return (
    <div className="flex flex-col gap-3 h-[calc(100vh-8rem)]">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold text-gray-200">Wine Desktop</h1>
        <a
          href={novncUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-gray-400 hover:text-white border border-gray-700 rounded px-2 py-1"
        >
          In neuem Tab öffnen ↗
        </a>
      </div>

      <div className="flex-1 rounded border border-gray-700 overflow-hidden bg-black">
        <iframe
          src={novncUrl}
          className="w-full h-full"
          title="Wine Desktop"
          allow="clipboard-read; clipboard-write"
        />
      </div>

      <p className="text-xs text-gray-600">
        Direkt-VNC: <span className="text-gray-400">Port 5900</span> &nbsp;|&nbsp;
        Browser: <span className="text-gray-400">Port 8080</span>
      </p>
    </div>
  )
}
