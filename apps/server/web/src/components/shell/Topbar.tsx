import { useTranslation } from "react-i18next"
import { useState, useRef, useEffect } from "react"
import { I } from "@/lib/icons"
import { useRouter } from "@/store/router"
import { useSettings } from "@/store/settings"
import { useData } from "@/contexts/DataContext"
import { useAuth } from "@/contexts/AuthContext"
import { isOnline } from "@/lib/format"
import { authApi, type ApiError } from "@/lib/api"

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

  const crumbs: { label: string; muted?: boolean; mono?: boolean; onClick?: () => void }[] = []
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

function UserMenu() {
  const { t } = useTranslation()
  const { user, logout } = useAuth()
  const [open, setOpen] = useState(false)
  const [showPasswordDialog, setShowPasswordDialog] = useState(false)
  const [currentPwd, setCurrentPwd] = useState("")
  const [pwd, setPwd] = useState("")
  const [confirmPwd, setConfirmPwd] = useState("")
  const [pwdStatus, setPwdStatus] = useState<"idle" | "busy" | "done" | "error">("idle")
  const [pwdError, setPwdError] = useState("")
  const menuRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener("mousedown", onClickOutside)
    return () => document.removeEventListener("mousedown", onClickOutside)
  }, [open])

  async function updatePassword() {
    if (currentPwd.length === 0 || pwd.length < 8 || confirmPwd.length < 8) return
    if (pwd !== confirmPwd) {
      setPwdError(t("plat.passwordMismatch"))
      return
    }
    setPwdStatus("busy")
    setPwdError("")
    try {
      await authApi.changePassword(currentPwd, pwd)
      setCurrentPwd("")
      setPwd("")
      setConfirmPwd("")
      setPwdStatus("done")
      setTimeout(() => {
        setShowPasswordDialog(false)
        setPwdStatus("idle")
      }, 1500)
    } catch (err: unknown) {
      setPwdStatus("error")
      if ((err as Partial<ApiError>)?.status === 401) {
        setPwdError(t("plat.incorrectPassword"))
      } else {
        setPwdError(t("common.error"))
      }
    }
  }

  const avatar = (user?.username || "?").slice(0, 2).toUpperCase()

  return (
    <div style={{ position: "relative" }} ref={menuRef}>
      <button
        onClick={() => setOpen(!open)}
        className="row gap-2"
        style={{
          appearance: "none",
          border: "1px solid var(--border)",
          background: "var(--panel-2)",
          borderRadius: 999,
          padding: "3px 10px 3px 3px",
          cursor: "pointer",
          alignItems: "center",
          height: 30,
        }}
      >
        <div style={{ width: 24, height: 24, borderRadius: "50%", background: "linear-gradient(135deg, var(--fg-2), var(--fg-4))", color: "var(--bg)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 9, fontWeight: 700 }}>
          {avatar}
        </div>
        <span style={{ fontSize: 12, color: "var(--fg-2)", maxWidth: 100 }} className="truncate">{user?.username}</span>
        {I.chev({ size: 12, style: { transform: open ? "rotate(180deg)" : "rotate(0deg)", transition: "transform 120ms ease", color: "var(--fg-4)" } })}
      </button>

      {open && (
        <div
          style={{
            position: "absolute",
            top: "calc(100% + 6px)",
            right: 0,
            minWidth: 200,
            background: "var(--panel)",
            border: "1px solid var(--border)",
            borderRadius: 8,
            boxShadow: "0 8px 24px rgba(0,0,0,0.15)",
            overflow: "hidden",
            zIndex: 999,
          }}
        >
          <div style={{ padding: "10px 12px", borderBottom: "1px solid var(--border)" }}>
            <div style={{ fontSize: 12, fontWeight: 500, color: "var(--fg)" }}>{user?.username}</div>
            <div className="mono" style={{ fontSize: 10, color: "var(--fg-4)", marginTop: 2 }}>
              {user?.isSuperAdmin ? "SuperAdmin" : "User"}
            </div>
          </div>

          <div className="col" style={{ padding: 4 }}>
            <button
              onClick={() => {
                setOpen(false)
                setShowPasswordDialog(true)
              }}
              className="row gap-2"
              style={{
                appearance: "none",
                border: "none",
                background: "transparent",
                padding: "8px 10px",
                cursor: "pointer",
                fontFamily: "inherit",
                fontSize: 12,
                color: "var(--fg-2)",
                textAlign: "left",
                alignItems: "center",
                borderRadius: 4,
              }}
              onMouseEnter={(e) => (e.currentTarget.style.background = "var(--hover)")}
              onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
            >
              {I.lock({ size: 14 })}
              <span>{t("plat.changePassword")}</span>
            </button>

            <button
              onClick={() => {
                setOpen(false)
                logout()
              }}
              className="row gap-2"
              style={{
                appearance: "none",
                border: "none",
                background: "transparent",
                padding: "8px 10px",
                cursor: "pointer",
                fontFamily: "inherit",
                fontSize: 12,
                color: "var(--fg-2)",
                textAlign: "left",
                alignItems: "center",
                borderRadius: 4,
              }}
              onMouseEnter={(e) => (e.currentTarget.style.background = "var(--hover)")}
              onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
            >
              {I.power({ size: 14 })}
              <span>{t("topbar.signOut")}</span>
            </button>
          </div>
        </div>
      )}

      {showPasswordDialog && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            background: "rgba(0,0,0,0.5)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 9999,
          }}
          onClick={(e) => {
            if (e.target === e.currentTarget) {
              setShowPasswordDialog(false)
              setCurrentPwd("")
              setPwd("")
              setConfirmPwd("")
              setPwdStatus("idle")
              setPwdError("")
            }
          }}
        >
          <div
            className="card"
            style={{
              width: 400,
              maxWidth: "90vw",
              padding: 20,
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ fontSize: 16, fontWeight: 500, marginBottom: 16, color: "var(--fg)" }}>
              {t("plat.changePassword")}
            </div>
            <div className="col gap-3">
              <div className="col gap-1">
                <label style={{ fontSize: 12, color: "var(--fg-3)", fontWeight: 500 }}>
                  {t("plat.currentPassword")}
                </label>
                <input
                  className="input"
                  type="password"
                  autoComplete="current-password"
                  value={currentPwd}
                  onChange={(e) => {
                    setCurrentPwd(e.target.value)
                    setPwdStatus("idle")
                    setPwdError("")
                  }}
                  placeholder={t("plat.currentPassword")}
                  autoFocus
                />
              </div>
              <div className="col gap-1">
                <label style={{ fontSize: 12, color: "var(--fg-3)", fontWeight: 500 }}>
                  {t("plat.newPassword")}
                </label>
                <input
                  className="input"
                  type="password"
                  autoComplete="new-password"
                  value={pwd}
                  onChange={(e) => {
                    setPwd(e.target.value)
                    setPwdStatus("idle")
                    setPwdError("")
                  }}
                  placeholder={t("plat.newPassword")}
                />
                {pwd.length > 0 && pwd.length < 8 && (
                  <div className="hint" style={{ color: "var(--warn)" }}>
                    {t("plat.passwordMinLength")}
                  </div>
                )}
              </div>
              <div className="col gap-1">
                <label style={{ fontSize: 12, color: "var(--fg-3)", fontWeight: 500 }}>
                  {t("plat.confirmPassword")}
                </label>
                <input
                  className="input"
                  type="password"
                  autoComplete="new-password"
                  value={confirmPwd}
                  onChange={(e) => {
                    setConfirmPwd(e.target.value)
                    setPwdStatus("idle")
                    setPwdError("")
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && currentPwd.length > 0 && pwd.length >= 8 && confirmPwd.length >= 8) {
                      updatePassword()
                    }
                  }}
                  placeholder={t("plat.confirmPassword")}
                />
                {confirmPwd.length > 0 && pwd !== confirmPwd && (
                  <div className="hint" style={{ color: "var(--warn)" }}>
                    {t("plat.passwordMismatch")}
                  </div>
                )}
              </div>
              {pwdStatus === "done" && (
                <div className="badge ok">{t("plat.passwordUpdated")}</div>
              )}
              {pwdStatus === "error" && pwdError && (
                <div className="badge crit">{pwdError}</div>
              )}
              <div className="row gap-2" style={{ marginTop: 8 }}>
                <button
                  className="btn btn-sm btn-primary"
                  onClick={updatePassword}
                  disabled={currentPwd.length === 0 || pwd.length < 8 || confirmPwd.length < 8 || pwd !== confirmPwd || pwdStatus === "busy"}
                >
                  {pwdStatus === "busy" && <span className="dot pulse ok" />}
                  {t("plat.updatePassword")}
                </button>
                <button
                  className="btn btn-sm btn-ghost"
                  onClick={() => {
                    setShowPasswordDialog(false)
                    setCurrentPwd("")
                    setPwd("")
                    setConfirmPwd("")
                    setPwdStatus("idle")
                    setPwdError("")
                  }}
                >
                  {t("common.cancel")}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export function Topbar({ onOpenSearch, onOpenNavigation }: { onOpenSearch: () => void; onOpenNavigation: () => void }) {
  const { t } = useTranslation()
  const { navigate } = useRouter()
  const { tweaks, toggleTheme, lang, setLang } = useSettings()

  return (
    <header className="topbar" style={{ height: 52, padding: "0 16px", display: "flex", alignItems: "center", gap: 12, borderBottom: "1px solid var(--border)", background: "var(--bg)", flexShrink: 0, position: "relative", zIndex: 5 }}>
      <button className="btn btn-ghost btn-icon mobile-nav-trigger" onClick={onOpenNavigation} aria-label={t("assistant.openNavigation")} title={t("assistant.openNavigation")}>{I.menu({ size: 15 })}</button>
      <span className="topbar-breadcrumb"><Breadcrumb /></span>
      <div style={{ flex: 1 }} />

      <button
        onClick={onOpenSearch}
        className="row gap-2 topbar-search"
        style={{ appearance: "none", height: 30, padding: "0 10px", background: "var(--panel-2)", border: "1px solid var(--border)", color: "var(--fg-4)", fontFamily: "inherit", fontSize: 12, borderRadius: 6, cursor: "pointer", minWidth: 220, alignItems: "center", justifyContent: "flex-start", gap: 8 }}
      >
        {I.search({ size: 13 })}
        <span className="truncate">{t("topbar.search")}</span>
        <div style={{ flex: 1 }} />
        <span className="kbd">⌘K</span>
      </button>

      <span className="topbar-connection"><ConnStatus /></span>

      <button className="btn btn-ghost btn-sm topbar-assistant" onClick={() => navigate("assistant")} title={t("nav.assistant")}>
        {I.sparkle({ size: 13 })} <span>{t("topbar.assistant")}</span>
      </button>

      <div className="vr topbar-divider" style={{ height: 22 }} />

      <button className="btn btn-ghost btn-sm" onClick={() => setLang(lang === "en" ? "zh" : "en")} title={t("header.language")}>
        {I.globe({ size: 13 })} <span className="mono">{lang === "zh" ? "中" : "EN"}</span>
      </button>

      <button className="btn btn-ghost btn-sm btn-icon" onClick={toggleTheme} title={t("header.theme")}>
        {tweaks.theme === "dark" ? I.sun({ size: 13 }) : I.moon({ size: 13 })}
      </button>

      <UserMenu />
    </header>
  )
}
