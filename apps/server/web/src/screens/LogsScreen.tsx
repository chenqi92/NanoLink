import { useEffect, useMemo, useRef, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { PageHeader } from "@/components/shell/primitives"
import { AgentPicker } from "@/components/monitor/AgentPicker"
import { useAgentCommand } from "@/hooks/useAgentCommand"
import type { AgentLogEntry } from "@/lib/api"

type Scope = "system" | "server" | "audit"

const SCOPE_CMD: Record<Scope, string> = { system: "SYSTEM_LOGS", server: "SERVICE_LOGS", audit: "AUDIT_LOGS" }
const LEVEL_COLOR: Record<string, string> = { info: "var(--fg-3)", warn: "var(--warn)", warning: "var(--warn)", error: "var(--crit)", err: "var(--crit)", debug: "var(--fg-dim)" }

function LogViewer({ lines, live }: { lines: AgentLogEntry[]; live?: boolean }) {
  const { t } = useTranslation()
  return (
    <div className="card" style={{ flex: 1, overflow: "auto", background: "var(--bg-2)", padding: "10px 12px", fontFamily: "var(--font-mono)", fontSize: 12, lineHeight: 1.6 }}>
      {lines.map((l, i) => (
        <div key={i} className="row gap-2" style={{ alignItems: "flex-start", whiteSpace: "pre-wrap", color: "var(--fg-2)" }}>
          {l.timestamp && <span className="dim" style={{ flexShrink: 0 }}>{l.timestamp}</span>}
          {l.level && <span style={{ flexShrink: 0, width: 48, color: LEVEL_COLOR[l.level.toLowerCase()] || "var(--fg-3)", textTransform: "uppercase", fontSize: 10.5, fontWeight: 600 }}>{l.level}</span>}
          {l.source && <span className="dim" style={{ flexShrink: 0, width: 96 }}>{l.source}</span>}
          <span style={{ minWidth: 0 }}>{l.message}</span>
        </div>
      ))}
      {live && (
        <div style={{ color: "var(--fg-4)", padding: "4px 0", fontStyle: "italic" }}>
          <span className="dot ok pulse" style={{ marginRight: 6 }} />
          {t("dev.tailWaiting")}
        </div>
      )}
    </div>
  )
}

export function LogsScreen() {
  const { t } = useTranslation()
  const [scope, setScope] = useState<Scope>("system")
  const [agentId, setAgentId] = useState("")
  const [service, setService] = useState("")
  const [level, setLevel] = useState("all")
  const [q, setQ] = useState("")
  const [paused, setPaused] = useState(false)

  const enabled = !!agentId && (scope !== "server" || !!service)
  const params = useMemo<Record<string, string>>(() => {
    const p: Record<string, string> = { lines: "200" }
    if (scope === "server") p.service = service
    return p
  }, [scope, service])
  const { data, loading, error, reload } = useAgentCommand(agentId, SCOPE_CMD[scope], { params, enabled })

  // live tail: re-poll while not paused
  const reloadRef = useRef(reload)
  useEffect(() => {
    reloadRef.current = reload
  }, [reload])
  useEffect(() => {
    if (paused || !enabled) return
    const id = setInterval(() => reloadRef.current(), 4000)
    return () => clearInterval(id)
  }, [paused, enabled])

  const allLines = data?.logResult?.lines ?? []
  const filtered = allLines.filter((l) => {
    if (level !== "all" && (l.level || "").toLowerCase() !== level) return false
    if (q && !l.message.toLowerCase().includes(q.toLowerCase())) return false
    return true
  })

  const scopes: { k: Scope; label: string }[] = [
    { k: "system", label: t("dev.systemLogs") },
    { k: "server", label: t("dev.serverLogs") },
    { k: "audit", label: t("dev.auditLogs") },
  ]

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader title={t("nav.logs")} subtitle={t("dev.logsSubtitle")} actions={<AgentPicker value={agentId} onChange={setAgentId} />} />
      <div style={{ padding: "0 24px", borderBottom: "1px solid var(--border)" }}>
        <div className="tabs" style={{ borderBottom: "none", marginBottom: -1 }}>
          {scopes.map((s) => (
            <button key={s.k} className={`tab ${scope === s.k ? "active" : ""}`} onClick={() => setScope(s.k)}>{s.label}</button>
          ))}
        </div>
      </div>
      <div className="col" style={{ padding: "16px 24px 24px", flex: 1, overflow: "hidden", gap: 12 }}>
        <div className="row gap-2" style={{ flexWrap: "wrap" }}>
          <button onClick={() => setPaused((p) => !p)} className="btn btn-sm" disabled={!enabled} style={{ background: "var(--panel-2)", borderColor: paused ? "var(--border-2)" : "var(--ok)", color: paused ? "var(--fg-3)" : "var(--ok)" }}>
            <span className={`dot ${paused ? "" : "ok pulse"}`} />
            <span>{paused ? t("dev.paused") : t("dev.liveTail")}</span>
          </button>
          {scope === "server" && (
            <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 10px", height: 30, minWidth: 180 }}>
              {I.bolt({ size: 13 })}
              <input value={service} onChange={(e) => setService(e.target.value)} placeholder="service (e.g. nginx)" style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "inherit", fontSize: 12 }} />
            </div>
          )}
          <select className="select" style={{ width: "auto" }} value={level} onChange={(e) => setLevel(e.target.value)}>
            <option value="all">{t("dev.allLevels")}</option>
            {["info", "warn", "error", "debug"].map((l) => <option key={l} value={l}>{l}</option>)}
          </select>
          <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 10px", height: 30, flex: 1, minWidth: 200 }}>
            {I.search({ size: 13 })}
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder={t("common.search")} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "inherit", fontSize: 12 }} />
          </div>
          <span className="mono dim" style={{ fontSize: 11, alignSelf: "center" }}>{filtered.length} {t("dev.lines2")}</span>
          <button className="btn btn-sm" disabled={!filtered.length} onClick={() => {
            const text = filtered.map((l) => `${l.timestamp ?? ""}\t${(l.level ?? "").toUpperCase()}\t${l.source ?? ""}\t${l.message}`).join("\n")
            const url = URL.createObjectURL(new Blob([text], { type: "text/plain" }))
            const a = document.createElement("a")
            a.href = url
            a.download = `${scope}-logs-${agentId || "agent"}.log`
            a.click()
            URL.revokeObjectURL(url)
          }}>{I.external({ size: 12 })}<span>{t("dev.export")}</span></button>
          <button className="btn btn-sm btn-ghost" onClick={reload} disabled={loading || !enabled}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button>
        </div>

        {!enabled ? (
          <div className="card" style={{ padding: "40px 24px", textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{scope === "server" ? "Enter a service name above" : t("common.loading")}</div>
        ) : loading && !data ? (
          <div style={{ padding: 32, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}><span className="dot pulse ok" /> {t("common.loading")}</div>
        ) : error ? (
          <div className="badge crit" style={{ height: "auto", padding: 10 }}>{error}</div>
        ) : filtered.length === 0 ? (
          <div className="card" style={{ padding: "40px 24px", textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("common.noData")}</div>
        ) : (
          <LogViewer lines={filtered} live={!paused} />
        )}
      </div>
    </div>
  )
}
