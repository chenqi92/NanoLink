import { useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import "./i18n"
import "@/index.css"
import { useAuth } from "@/contexts/AuthContext"
import { alertsApi } from "@/lib/api"
import { LoginScreen } from "@/screens/LoginScreen"
import { Sidebar } from "@/components/shell/Sidebar"
import { Topbar } from "@/components/shell/Topbar"
import { SearchPalette } from "@/components/shell/SearchPalette"
import { AgentWizard } from "@/components/agents/AgentWizard"
import { ScreenRouter } from "@/screens"
import { useRouter } from "@/store/router"
import { I } from "@/lib/icons"
import { Drawer } from "@/components/shell/Drawer"
import "@/styles/shell.css"

function App() {
  const { t } = useTranslation()
  const { isAuthenticated, isLoading: authLoading, user } = useAuth()
  const { route, setRoute } = useRouter()
  const [collapsed, setCollapsed] = useState(false)
  const [openSearch, setOpenSearch] = useState(false)
  const [openWizard, setOpenWizard] = useState(false)
  const [mobileNavOpen, setMobileNavOpen] = useState(false)
  const [alertCount, setAlertCount] = useState(0)

  // Poll unacknowledged alert count for the sidebar badge
  useEffect(() => {
    if (!isAuthenticated) return
    let alive = true
    const fetchCount = () =>
      alertsApi
        .list()
        .then((a) => alive && setAlertCount(a.filter((x) => !x.ack).length))
        .catch(() => {})
    fetchCount()
    const id = setInterval(fetchCount, 30000)
    return () => {
      alive = false
      clearInterval(id)
    }
  }, [isAuthenticated])

  // Open the add-agent wizard when a navigation requests it
  useEffect(() => {
    if (route.openWizard) {
      if (user?.isSuperAdmin) setOpenWizard(true)
      setRoute({ ...route, openWizard: false })
    }
  }, [route, setRoute, user?.isSuperAdmin])

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
      <div style={{ height: "100%", display: "flex", alignItems: "center", justifyContent: "center", background: "var(--bg)", color: "var(--fg-3)" }}>
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
      <div className="app-shell">
        <Sidebar collapsed={collapsed} setCollapsed={setCollapsed} alertCount={alertCount} />
        <div className="col app-shell-main">
          <Topbar onOpenSearch={() => setOpenSearch(true)} onOpenNavigation={() => setMobileNavOpen(true)} />
          <main style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
            <ScreenRouter />
          </main>
        </div>
      </div>
      <Drawer open={mobileNavOpen} title={t("assistant.mobileNavigation")} closeLabel={t("assistant.closeNavigation")} side="left" width={280} onClose={() => setMobileNavOpen(false)} className="mobile-nav-drawer">
        <Sidebar collapsed={false} setCollapsed={() => {}} alertCount={alertCount} onNavigate={() => setMobileNavOpen(false)} />
      </Drawer>
      <SearchPalette open={openSearch} onClose={() => setOpenSearch(false)} />
      {openWizard && user?.isSuperAdmin && <AgentWizard onClose={() => setOpenWizard(false)} />}
    </>
  )
}

export default App
