import { useEffect, useRef, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useData } from "@/contexts/DataContext"
import { useRouter } from "@/store/router"
import { usersApi, type UserDetail } from "@/lib/api"
import { isOnline } from "@/lib/format"
import { useAuth } from "@/contexts/AuthContext"

export function SearchPalette({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t } = useTranslation()
  const { agents } = useData()
  const { navigate } = useRouter()
  const { user } = useAuth()
  const [q, setQ] = useState("")
  const [users, setUsers] = useState<UserDetail[]>([])
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (open) {
      setQ("")
      setTimeout(() => inputRef.current?.focus(), 50)
      if (user?.isSuperAdmin) usersApi.list().then(setUsers).catch(() => setUsers([]))
      else setUsers([])
    }
  }, [open, user?.isSuperAdmin])

  if (!open) return null
  const ql = q.toLowerCase()
  const agentMatches = agents.filter((a) => !ql || a.hostname.toLowerCase().includes(ql) || a.os.toLowerCase().includes(ql) || a.id.toLowerCase().includes(ql)).slice(0, 6)
  const userMatches = users.filter((u) => !ql || u.username.toLowerCase().includes(ql) || (u.email || "").toLowerCase().includes(ql)).slice(0, 4)

  const actions = [
    ...(user?.isSuperAdmin ? [{ label: t("wizard.addAgent"), run: () => { navigate("tokens", { openWizard: true }); onClose() } }] : []),
    { label: t("acc.generatePairing"), run: () => { navigate("devices", { openPair: true }); onClose() } },
    ...(user?.isSuperAdmin ? [{ label: t("nav.audit"), run: () => { navigate("audit"); onClose() } }] : []),
  ].filter((a) => !ql || a.label.toLowerCase().includes(ql))

  function go(page: Parameters<typeof navigate>[0], extra?: Parameters<typeof navigate>[1]) {
    navigate(page, extra)
    onClose()
  }

  const rowStyle: React.CSSProperties = { padding: "8px 14px", cursor: "pointer", display: "flex", alignItems: "center", gap: 10 }
  const hoverIn = (e: React.MouseEvent<HTMLDivElement>) => (e.currentTarget.style.background = "var(--hover)")
  const hoverOut = (e: React.MouseEvent<HTMLDivElement>) => (e.currentTarget.style.background = "transparent")

  return (
    <div className="scrim search-palette-scrim" onClick={onClose}>
      <div className="dialog search-palette-dialog" onClick={(e) => e.stopPropagation()}>
        <div className="row gap-2" style={{ padding: "10px 14px", borderBottom: "1px solid var(--border)" }}>
          {I.search({ size: 14 })}
          <input ref={inputRef} value={q} onChange={(e) => setQ(e.target.value)} placeholder={t("topbar.search")} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "inherit", fontSize: 13, padding: 4 }} />
          <span className="kbd">esc</span>
        </div>
        <div style={{ overflow: "auto", padding: "6px 0", flex: 1 }}>
          {agentMatches.length > 0 && (
            <div>
              <div className="upper" style={{ padding: "8px 14px 4px", color: "var(--fg-4)" }}>{t("nav.agents")}</div>
              {agentMatches.map((a) => (
                <div key={a.id} onClick={() => go("agent-detail", { agentId: a.id })} style={rowStyle} onMouseEnter={hoverIn} onMouseLeave={hoverOut}>
                  <span className={`dot ${isOnline(a.lastHeartbeat) ? "ok" : "crit"}`} />
                  <span className="mono" style={{ fontWeight: 500 }}>{a.hostname}</span>
                  <span className="muted" style={{ fontSize: 11 }}>{a.os} · {a.arch}</span>
                </div>
              ))}
            </div>
          )}
          {actions.length > 0 && (
            <div>
              <div className="upper" style={{ padding: "8px 14px 4px", color: "var(--fg-4)" }}>{t("topbar.actions")}</div>
              {actions.map((a, i) => (
                <div key={i} onClick={a.run} style={rowStyle} onMouseEnter={hoverIn} onMouseLeave={hoverOut}>
                  {I.bolt({ size: 13 })}<span>{a.label}</span>
                </div>
              ))}
            </div>
          )}
          {userMatches.length > 0 && (
            <div>
              <div className="upper" style={{ padding: "8px 14px 4px", color: "var(--fg-4)" }}>{t("nav.users")}</div>
              {userMatches.map((u) => (
                <div key={u.id} onClick={() => go("users")} style={rowStyle} onMouseEnter={hoverIn} onMouseLeave={hoverOut}>
                  {I.user({ size: 13 })}
                  <span className="mono">{u.username}</span>
                  <span className="dim" style={{ fontSize: 11 }}>{u.email}</span>
                </div>
              ))}
            </div>
          )}
          {agentMatches.length === 0 && userMatches.length === 0 && actions.length === 0 && (
            <div className="muted" style={{ padding: "20px 14px", fontSize: 12.5 }}>{t("common.noData")}</div>
          )}
        </div>
      </div>
    </div>
  )
}
