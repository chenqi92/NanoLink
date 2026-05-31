import { useEffect, useRef, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useData } from "@/contexts/DataContext"
import { useRouter } from "@/store/router"
import { isOnline } from "@/lib/format"

export function SearchPalette({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t } = useTranslation()
  const { agents } = useData()
  const { navigate } = useRouter()
  const [q, setQ] = useState("")
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (open) {
      setQ("")
      setTimeout(() => inputRef.current?.focus(), 50)
    }
  }, [open])

  if (!open) return null
  const ql = q.toLowerCase()
  const agentMatches = agents.filter((a) => !ql || a.hostname.toLowerCase().includes(ql) || a.os.toLowerCase().includes(ql) || a.id.toLowerCase().includes(ql)).slice(0, 8)

  return (
    <div className="scrim" onClick={onClose} style={{ alignItems: "flex-start", paddingTop: "10vh" }}>
      <div className="dialog" style={{ width: 560, maxHeight: "70vh" }} onClick={(e) => e.stopPropagation()}>
        <div className="row gap-2" style={{ padding: "10px 14px", borderBottom: "1px solid var(--border)" }}>
          {I.search({ size: 14 })}
          <input
            ref={inputRef}
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t("topbar.search")}
            style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "inherit", fontSize: 13, padding: 4 }}
          />
          <span className="kbd">esc</span>
        </div>
        <div style={{ overflow: "auto", padding: "6px 0", flex: 1 }}>
          {agentMatches.length > 0 ? (
            <div>
              <div className="upper" style={{ padding: "8px 14px 4px", color: "var(--fg-4)" }}>{t("nav.agents")}</div>
              {agentMatches.map((a) => (
                <div
                  key={a.id}
                  onClick={() => {
                    navigate("agent-detail", { agentId: a.id })
                    onClose()
                  }}
                  className="row gap-2"
                  style={{ padding: "8px 14px", cursor: "pointer", alignItems: "center" }}
                  onMouseEnter={(e) => (e.currentTarget.style.background = "var(--hover)")}
                  onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
                >
                  <span className={`dot ${isOnline(a.lastHeartbeat) ? "ok" : "crit"}`} />
                  <span className="mono" style={{ fontWeight: 500 }}>{a.hostname}</span>
                  <span className="muted" style={{ fontSize: 11 }}>{a.os} · {a.arch}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="muted" style={{ padding: "20px 14px", fontSize: 12.5 }}>{t("common.noData")}</div>
          )}
        </div>
      </div>
    </div>
  )
}
