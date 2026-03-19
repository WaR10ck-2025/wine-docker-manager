import { NavLink, Route, Routes } from 'react-router-dom'
import InstallPage from './pages/InstallPage'
import AppsPage from './pages/AppsPage'
import DesktopPage from './pages/DesktopPage'
import WinetricksPage from './pages/WinetricksPage'
import UsbIpPage from './pages/UsbIpPage'
import WindowsVmPage from './pages/WindowsVmPage'
import VehiclesPage from './pages/VehiclesPage'

const NAV = [
  { to: '/',           label: '🖥  Wine Desktop'  },
  { to: '/install',    label: '📦  Installieren'  },
  { to: '/apps',       label: '▶  Apps'           },
  { to: '/winetricks', label: '🔧  Winetricks'    },
  { to: '/usbip',      label: '🔌  USB/IP'        },
  { to: '/windowsvm',  label: '🪟  Windows VM'    },
  { to: '/vehicles',   label: '🚗  Fahrzeuge'     },
]

export default function App() {
  return (
    <div className="min-h-screen flex flex-col">
      {/* Header */}
      <header className="border-b border-gray-800 px-6 py-3 flex items-center gap-6">
        <span className="text-wine-500 font-bold text-lg tracking-widest">WINE MANAGER</span>
        <nav className="flex gap-1 ml-4 flex-wrap">
          {NAV.map(({ to, label }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              className={({ isActive }) =>
                `px-3 py-1.5 rounded text-sm transition-colors ${
                  isActive
                    ? 'bg-wine-500 text-white'
                    : 'text-gray-400 hover:text-white hover:bg-gray-800'
                }`
              }
            >
              {label}
            </NavLink>
          ))}
        </nav>
      </header>

      {/* Content */}
      <main className="flex-1 p-6">
        <Routes>
          <Route path="/"           element={<DesktopPage />} />
          <Route path="/install"    element={<InstallPage />} />
          <Route path="/apps"       element={<AppsPage />} />
          <Route path="/winetricks" element={<WinetricksPage />} />
          <Route path="/usbip"      element={<UsbIpPage />} />
          <Route path="/windowsvm"  element={<WindowsVmPage />} />
          <Route path="/vehicles"   element={<VehiclesPage />} />
        </Routes>
      </main>
    </div>
  )
}
