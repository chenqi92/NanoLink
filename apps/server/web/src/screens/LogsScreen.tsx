import { useEffect, useMemo, useRef, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { PageHeader } from "@/components/shell/primitives"
import { AgentPicker } from "@/components/monitor/AgentPicker"
import { useAgentCommand } from "@/hooks/useAgentCommand"
import type { AgentLogEntry } from "@/lib/api"
import { useData } from "@/contexts/DataContext"
import { ContentState, LoadingState, RequestState } from "@/components/shell/RequestState"

type Scope = "system" | "server" | "audit"

const SCOPE_CMD: Record<Scope, string> = { system: "SYSTEM_LOGS", server: "SERVICE_LOGS", audit: "AUDIT_LOGS" }
const SCOPE_PERMISSION: Record<Scope, number> = { system: 1, server: 0, audit: 2 }
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
  const { agents } = useData()
  const [scope, setScope] = useState<Scope>("system")
  const [agentId, setAgentId] = useState("")
  const [service, setService] = useState("")
  const [level, setLevel] = useState("all")
  const [q, setQ] = useState("")
  const [paused, setPaused] = useState(false)
  const selectedAgent = agents.find((agent) => agent.id === agentId)
  const permission = selectedAgent?.permissionLevel ?? 0

  const canReadScope = permission >= SCOPE_PERMISSION[scope]
  const enabled = !!agentId && canReadScope && (scope !== "server" || !!service)
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

  useEffect(() => {
    if (selectedAgent && permission < SCOPE_PERMISSION[scope]) setScope("server")
  }, [selectedAgent, permission, scope])

  const allLines = data?.logResult?.lines ?? []
  const filtered = allLines.filter((l) => {
    if (level !== "all" && (l.level || "").toLowerCase() !== level) return false
    if (q && !l.message.toLowerCase().includes(q.toLowerCase())) return false
    return true
  })

  const scopes: { k: Scope; label: string; required: number }[] = [
    { k: "system", label: t("dev.systemLogs"), required: 1 },
    { k: "server", label: t("dev.serverLogs"), required: 0 },
    { k: "audit", label: t("dev.auditLogs"), required: 2 },
  ]

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader title={t("nav.logs")} subtitle={t("dev.logsSubtitle")} actions={<AgentPicker value={agentId} onChange={setAgentId} />} />
      <div style={{ padding: "0 24px", borderBottom: "1px solid var(--border)" }}>
        <div className="tabs" style={{ borderBottom: "none", marginBottom: -1 }}>
          {scopes.map((s) => (
            <button key={s.k} className={`tab ${scope === s.k ? "active" : ""}`} disabled={permission < s.required} title={permission < s.required ? t("access.permissionLevelDesc", { level: `L${s.required}` }) : undefined} onClick={() => setScope(s.k)}>{s.label}{permission < s.required && <span className="dim row gap-1" style={{ fontSize: 10 }}>{I.lock({ size: 10 })} L{s.required}</span>}</button>
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
          !agentId ? (
            <ContentState kind="empty" title={t("mon.noAgents")} compact />
          ) : !canReadScope ? (
            <ContentState kind="forbidden" eyebrow={t("access.restricted")} title={t("access.noPermissionTitle")} description={t("access.permissionLevelDesc", { level: `L${SCOPE_PERMISSION[scope]}` })} compact />
          ) : (
            <ContentState kind="empty" title={t("dev.enterServiceName")} compact />
          )
        ) : loading && !data ? (
          <LoadingState compact />
        ) : error != null ? (
          <RequestState error={error} onRetry={reload} compact />
        ) : filtered.length === 0 ? (
          <ContentState kind="empty" title={t("common.noData")} compact />
        ) : (
          <LogViewer lines={filtered} live={!paused} />
        )}
      </div>
    </div>
  )
}
