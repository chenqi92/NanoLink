import { useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import "./i18n"
import "@/index.css"
import { useAuth } from "@/contexts/AuthContext"
import { LoginScreen } from "@/screens/LoginScreen"
import { Sidebar } from "@/components/shell/Sidebar"
import { Topbar } from "@/components/shell/Topbar"
import { SearchPalette } from "@/components/shell/SearchPalette"
import { ScreenRouter } from "@/screens"
import { I } from "@/lib/icons"

function App() {
  const { t } = useTranslation()
  const { isAuthenticated, isLoading: authLoading } = useAuth()
  const [collapsed, setCollapsed] = useState(false)
  const [openSearch, setOpenSearch] = useState(false)

  // Global ⌘K / Esc
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault()
        setOpenSearch(true)
      }
      if (e.key === "Escape") setOpenSearch(false)
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [])

  if (authLoading) {
    return (
      <div style={{ height: "100vh", display: "flex", alignItems: "center", justifyContent: "center", background: "var(--bg)", color: "var(--fg-3)" }}>
        <div className="col gap-3" style={{ alignItems: "center" }}>
          <span style={{ color: "var(--fg-dim)" }}>{I.brand({ size: 32 })}</span>
          <div className="row gap-2">
            <span className="dot pulse ok" />
            <span style={{ fontSize: 12.5 }}>{t("common.loading")}</span>
          </div>
        </div>
      </div>
    )
  }

  if (!isAuthenticated) {
    return <LoginScreen />
  }

  return (
    <>
      <div style={{ display: "flex", height: "100vh", width: "100vw", overflow: "hidden", background: "var(--bg)", color: "var(--fg)" }}>
        <Sidebar collapsed={collapsed} setCollapsed={setCollapsed} />
        <div className="col" style={{ flex: 1, minWidth: 0 }}>
          <Topbar onOpenSearch={() => setOpenSearch(true)} />
          <main style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
            <ScreenRouter />
          </main>
        </div>
      </div>
      <SearchPalette open={openSearch} onClose={() => setOpenSearch(false)} />
    </>
  )
}

export default App
