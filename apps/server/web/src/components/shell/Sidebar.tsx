import { useTranslation } from "react-i18next"
import type { ReactNode } from "react"
import { I } from "@/lib/icons"
import { useRouter, type Page } from "@/store/router"
import { useAuth } from "@/contexts/AuthContext"
import { pageRequiresSuperAdmin } from "@/lib/access"

interface NavItem {
  id: Page
  icon: ReactNode
  label: string
  badge?: number
}

export function Sidebar({ collapsed, setCollapsed, alertCount = 0, onNavigate }: { collapsed: boolean; setCollapsed: (v: boolean) => void; alertCount?: number; onNavigate?: () => void }) {
  const { t } = useTranslation()
  const { route, navigate } = useRouter()
  const { user } = useAuth()

  const groups: { label: string; items: NavItem[] }[] = [
    {
      label: t("nav.monitoring"),
      items: [
        { id: "assistant", icon: I.ai({}), label: t("nav.assistant") },
        { id: "dashboard", icon: I.dashboard({}), label: t("nav.dashboard") },
        { id: "agents", icon: I.agents({}), label: t("nav.agents") },
        { id: "alerts", icon: I.warn({}), label: t("nav.alerts"), badge: alertCount },
      ],
    },
    {
      label: t("nav.ops"),
      items: [
        { id: "operations", icon: I.bolt({}), label: t("nav.operations") },
        { id: "deployments", icon: I.arrowUp({}), label: t("nav.deployments") },
        { id: "logs", icon: I.audit({}), label: t("nav.logs") },
      ],
    },
    {
      label: t("nav.access"),
      items: [
        { id: "tokens", icon: I.token({}), label: t("nav.tokens") },
        { id: "devices", icon: I.device({}), label: t("nav.devices") },
        { id: "users", icon: I.users({}), label: t("nav.users") },
        { id: "groups", icon: I.group({}), label: t("nav.groups") },
        { id: "permissions", icon: I.shield({}), label: t("nav.permissions") },
      ],
    },
    {
      label: t("nav.platform"),
      items: [
        { id: "audit", icon: I.audit({}), label: t("nav.audit") },
        { id: "alert-config", icon: I.bell({}), label: t("nav.alertConfig") },
        { id: "settings", icon: I.settings({}), label: t("nav.settings") },
      ],
    },
  ]
  const visibleGroups = groups
    .map((group) => ({
      ...group,
      items: group.items.filter((item) => user?.isSuperAdmin || !pageRequiresSuperAdmin(item.id)),
    }))
    .filter((group) => group.items.length > 0)

  const isRail = collapsed

  return (
    <aside
      className="app-sidebar"
      style={{
        width: isRail ? 56 : 224,
        borderRight: "1px solid var(--border)",
        background: "var(--bg-2)",
        display: "flex",
        flexDirection: "column",
        transition: "width 160ms ease",
        flexShrink: 0,
      }}
    >
      <div
        style={{
          height: 52,
          padding: isRail ? 0 : "0 16px",
          display: "flex",
          alignItems: "center",
          justifyContent: isRail ? "center" : "space-between",
          borderBottom: "1px solid var(--border)",
        }}
      >
        <div className="row gap-2" style={{ alignItems: "center" }}>
          {I.brand({ size: 20 })}
          {!isRail && (
            <div className="col" style={{ gap: 0, lineHeight: 1.1 }}>
              <div style={{ fontWeight: 600, fontSize: 13.5, letterSpacing: "-0.01em" }}>NanoOps</div>
              <div className="mono" style={{ fontSize: 9.5, color: "var(--fg-4)", letterSpacing: "0.04em" }}>prod</div>
            </div>
          )}
        </div>
        {!isRail && (
          <button className="btn btn-ghost btn-sm btn-icon" onClick={() => setCollapsed(true)} title="Collapse">
            {I.back({ size: 14 })}
          </button>
        )}
      </div>

      <nav style={{ padding: 8, flex: 1, overflow: "auto" }}>
        {visibleGroups.map((g, gi) => (
          <div key={gi} style={{ marginBottom: 14 }}>
            {!isRail && <div className="upper" style={{ padding: "8px 10px 4px", color: "var(--fg-4)" }}>{g.label}</div>}
            <div className="col" style={{ gap: 1 }}>
              {g.items.map((it) => {
                const active = route.page === it.id || (route.page === "agent-detail" && it.id === "agents")
                return (
                  <button
                    key={it.id}
                    aria-current={active ? "page" : undefined}
                    onClick={() => {
                      navigate(it.id)
                      onNavigate?.()
                    }}
                    title={isRail ? it.label : ""}
                    style={{
                      appearance: "none",
                      border: "none",
                      background: active ? "var(--panel-2)" : "transparent",
                      color: active ? "var(--fg)" : "var(--fg-3)",
                      fontFamily: "inherit",
                      fontSize: 12.5,
                      fontWeight: active ? 500 : 400,
                      cursor: "pointer",
                      padding: isRail ? 0 : "0 10px",
                      height: 30,
                      borderRadius: 6,
                      display: "flex",
                      alignItems: "center",
                      justifyContent: isRail ? "center" : "flex-start",
                      gap: 10,
                      width: "100%",
                      position: "relative",
                      transition: "background 80ms ease, color 80ms ease",
                    }}
                    onMouseEnter={(e) => {
                      if (!active) e.currentTarget.style.background = "var(--hover)"
                    }}
                    onMouseLeave={(e) => {
                      if (!active) e.currentTarget.style.background = "transparent"
                    }}
                  >
                    {active && !isRail && <span style={{ position: "absolute", left: -8, top: 6, bottom: 6, width: 2, background: "var(--fg)", borderRadius: 2 }} />}
                    <span style={{ display: "inline-flex", alignItems: "center", color: active ? "var(--fg)" : "var(--fg-4)", flexShrink: 0 }}>{it.icon}</span>
                    {!isRail && <span style={{ whiteSpace: "nowrap", flex: 1, textAlign: "left" }}>{it.label}</span>}
                    {!isRail && it.badge !== undefined && it.badge > 0 && (
                      <span className="mono num" style={{ fontSize: 9.5, padding: "1px 5px", borderRadius: 8, background: "var(--crit)", color: "#fff", fontWeight: 600, minWidth: 16, textAlign: "center", lineHeight: 1.4 }}>{it.badge}</span>
                    )}
                  </button>
                )
              })}
            </div>
          </div>
        ))}
      </nav>

      {isRail ? (
        <div style={{ padding: 8, borderTop: "1px solid var(--border)", display: "flex", justifyContent: "center" }}>
          <button className="btn btn-ghost btn-icon btn-sm" onClick={() => setCollapsed(false)} title="Expand">
            {I.chev({ size: 14 })}
          </button>
        </div>
      ) : (
        <div style={{ padding: 8, borderTop: "1px solid var(--border)", display: "flex", justifyContent: "center" }}>
          <button className="btn btn-ghost btn-icon btn-sm" onClick={() => setCollapsed(true)} title="Collapse">
            {I.back({ size: 14 })}
          </button>
        </div>
      )}
    </aside>
  )
}
