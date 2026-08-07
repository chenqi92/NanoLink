import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useRouter } from "@/store/router"
import { useSettings } from "@/store/settings"
import { useData } from "@/contexts/DataContext"
import { isOnline } from "@/lib/format"

const PAGE_KEYS: Record<string, string> = {
  dashboard: "nav.dashboard",
  agents: "nav.agents",
  alerts: "nav.alerts",
  assistant: "nav.assistant",
  operations: "nav.operations",
  logs: "nav.logs",
  tokens: "nav.tokens",
  devices: "nav.devices",
  users: "nav.users",
  groups: "nav.groups",
  permissions: "nav.permissions",
  audit: "nav.audit",
  settings: "nav.settings",
}

function Breadcrumb() {
  const { t } = useTranslation()
  const { route, navigate } = useRouter()
  const { agents } = useData()

  const crumbs: { label: string; muted?: boolean; mono?: boolean; onClick?: () => void }[] = [{ label: "nano.io", muted: true }]
  if (route.page === "agent-detail") {
    const a = agents.find((x) => x.id === route.agentId)
    crumbs.push({ label: t("nav.agents"), onClick: () => navigate("agents") })
    if (a) crumbs.push({ label: a.hostname, mono: true })
  } else {
    crumbs.push({ label: t(PAGE_KEYS[route.page] || "nav.dashboard") })
  }

  return (
    <div className="row gap-2" style={{ alignItems: "center", fontSize: 13 }}>
      {crumbs.map((c, i) => (
        <span key={i} className="row gap-2" style={{ alignItems: "center" }}>
          {i > 0 && <span style={{ color: "var(--fg-dim)" }}>/</span>}
          {c.onClick ? (
            <a className="lnk" onClick={c.onClick} style={{ cursor: "pointer", color: "var(--fg-3)" }}>{c.label}</a>
          ) : (
            <span className={c.mono ? "mono" : ""} style={{ color: c.muted ? "var(--fg-4)" : "var(--fg)", fontWeight: i === crumbs.length - 1 ? 500 : 400 }}>{c.label}</span>
          )}
        </span>
      ))}
    </div>
  )
}

function ConnStatus() {
  const { t } = useTranslation()
  const { agents, connectionMode, wsStatus } = useData()
  const online = agents.filter((a) => isOnline(a.lastHeartbeat)).length
  const total = agents.length
  const live = wsStatus === "connected"
  return (
    <div className="row gap-2" style={{ alignItems: "center", padding: "0 10px", background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, height: 30 }}>
      <span className={`dot ${live ? "pulse ok" : "warn"}`} />
      <span className="mono" style={{ fontSize: 11, color: "var(--fg-2)" }}>{live ? t("status.live") : t(`status.${connectionMode === "polling" ? "polling" : "connecting"}`)}</span>
      <span className="mono" style={{ fontSize: 11, color: "var(--fg-4)" }}>·</span>
      <span className="mono num" style={{ fontSize: 11, color: "var(--fg-3)" }}>
        {online}/{total} {t("status.connected")}
      </span>
    </div>
  )
}

export function Topbar({ onOpenSearch }: { onOpenSearch: () => void }) {
  const { t } = useTranslation()
  const { navigate } = useRouter()
  const { tweaks, toggleTheme, lang, setLang } = useSettings()

  return (
    <header style={{ height: 52, padding: "0 16px", display: "flex", alignItems: "center", gap: 12, borderBottom: "1px solid var(--border)", background: "var(--bg)", flexShrink: 0, position: "relative", zIndex: 5 }}>
      <Breadcrumb />
      <div style={{ flex: 1 }} />

      <button
        onClick={onOpenSearch}
        className="row gap-2"
        style={{ appearance: "none", height: 30, padding: "0 10px", background: "var(--panel-2)", border: "1px solid var(--border)", color: "var(--fg-4)", fontFamily: "inherit", fontSize: 12, borderRadius: 6, cursor: "pointer", minWidth: 220, alignItems: "center", justifyContent: "flex-start", gap: 8 }}
      >
        {I.search({ size: 13 })}
        <span className="truncate">{t("topbar.search")}</span>
        <div style={{ flex: 1 }} />
        <span className="kbd">⌘K</span>
      </button>

      <ConnStatus />

      <button className="btn btn-ghost btn-sm" onClick={() => navigate("assistant")} title={t("nav.assistant")}>
        {I.sparkle({ size: 13 })} <span>{t("topbar.assistant")}</span>
      </button>

      <div className="vr" style={{ height: 22 }} />

      <button className="btn btn-ghost btn-sm" onClick={() => setLang(lang === "en" ? "zh" : "en")} title={t("header.language")}>
        {I.globe({ size: 13 })} <span className="mono">{lang === "zh" ? "中" : "EN"}</span>
      </button>

      <button className="btn btn-ghost btn-sm btn-icon" onClick={toggleTheme} title={t("header.theme")}>
        {tweaks.theme === "dark" ? I.sun({ size: 13 }) : I.moon({ size: 13 })}
      </button>
    </header>
  )
}
