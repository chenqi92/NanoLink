import { useEffect, useRef, useState } from "react"
import { useTranslation } from "react-i18next"
import { I, osIcon } from "@/lib/icons"
import { useData } from "@/contexts/DataContext"
import { useRouter } from "@/store/router"
import { metricsApi, type Metrics } from "@/lib/api"
import { Status, Perm } from "@/components/shell/primitives"
import { RealtimeTab } from "@/components/monitor/realtime"
import { HistoryTab } from "@/components/monitor/HistoryTab"
import { TerminalTab } from "@/components/monitor/TerminalTab"
import { OnDemandTab } from "@/components/monitor/OnDemandTab"
import { ProcessesTab, DockerTab, AgentLogsTab } from "@/components/monitor/AgentDataTabs"
import { agentStatus, osFamily } from "@/lib/format"

type Tab = "realtime" | "history" | "processes" | "services" | "docker" | "files" | "logs" | "terminal"
const MAX_HIST = 60

export function AgentDetailScreen() {
  const { t } = useTranslation()
  const { agents, metrics: ctxMetrics } = useData()
  const { route, navigate } = useRouter()
  const [tab, setTab] = useState<Tab>("realtime")

  const a = agents.find((x) => x.id === route.agentId)
  const ctxM = route.agentId ? ctxMetrics[route.agentId] : undefined
  const [fetched, setFetched] = useState<Metrics | null>(null)
  const m = ctxM ?? fetched ?? undefined

  // initial fetch fallback (before WS delivers metrics for this agent)
  useEffect(() => {
    if (!route.agentId || ctxM) return
    let alive = true
    metricsApi.get(route.agentId).then((d) => { if (alive) setFetched(d) }).catch(() => {})
    return () => { alive = false }
  }, [route.agentId, ctxM])

  // live history buffer for sparklines
  const [hist, setHist] = useState<{ cpu: number[]; mem: number[] }>({ cpu: [], mem: [] })
  const lastTs = useRef("")
  useEffect(() => {
    if (!m) return
    if (m.timestamp && m.timestamp === lastTs.current) return
    lastTs.current = m.timestamp || ""
    const cpu = m.cpu?.usagePercent ?? 0
    const memPct = m.memory?.total ? (m.memory.used / m.memory.total) * 100 : 0
    setHist((h) => ({ cpu: [...h.cpu, cpu].slice(-MAX_HIST), mem: [...h.mem, memPct].slice(-MAX_HIST) }))
  }, [m])

  // reset history when switching agents
  useEffect(() => {
    setHist({ cpu: [], mem: [] })
    setFetched(null)
  }, [route.agentId])

  if (!a) {
    return (
      <div style={{ padding: 40, textAlign: "center", color: "var(--fg-4)" }}>
        <div style={{ marginBottom: 12 }}>{I.warn({ size: 28 })}</div>
        <div style={{ fontSize: 13 }}>{t("common.noData")}</div>
        <button className="btn btn-sm" style={{ marginTop: 16 }} onClick={() => navigate("agents")}>{I.back({ size: 13 })}<span>{t("nav.agents")}</span></button>
      </div>
    )
  }

  const status = agentStatus(a.lastHeartbeat)
  const ip = m?.networks?.find((n) => !n.interface.startsWith("lo") && n.ipAddresses?.length)?.ipAddresses?.[0]

  const tabs: { k: Tab; label: string; icon: React.ReactNode; live?: boolean }[] = [
    { k: "realtime", label: t("agent.realtimeData"), icon: <span className="dot pulse ok" style={{ width: 5, height: 5 }} /> },
    { k: "history", label: t("agent.historyCharts"), icon: I.chart({ size: 13 }) },
    { k: "processes", label: t("mon.tabProcesses"), icon: I.cpu({ size: 13 }) },
    { k: "services", label: t("mon.tabServices"), icon: I.bolt({ size: 13 }) },
    { k: "docker", label: t("mon.tabDocker"), icon: I.disk({ size: 13 }) },
    { k: "files", label: t("mon.tabFiles"), icon: I.audit({ size: 13 }) },
    { k: "logs", label: t("mon.tabLogs"), icon: <span className="dot pulse ok" style={{ width: 5, height: 5 }} /> },
    { k: "terminal", label: t("agent.terminal"), icon: I.term({ size: 13 }) },
  ]

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <div style={{ padding: "16px 24px 0", borderBottom: "1px solid var(--border)" }}>
        <div className="row gap-3" style={{ alignItems: "flex-start", marginBottom: 14 }}>
          <button className="btn btn-ghost btn-sm btn-icon" onClick={() => navigate("agents")}>{I.back({ size: 14 })}</button>
          <div className="col flex-1" style={{ gap: 4, minWidth: 0 }}>
            <div className="row gap-2" style={{ alignItems: "center", flexWrap: "wrap" }}>
              <Status status={status} />
              <h1 className="mono" style={{ margin: 0, fontSize: 18, fontWeight: 500 }}>{a.hostname}</h1>
              <Perm level={a.permission} />
              <span className="badge"><span style={{ display: "inline-flex", marginRight: 2 }}>{osIcon(osFamily(a.os))}</span> {a.os}</span>
              <span className="badge mono">{a.arch}</span>
              {a.version && <span className="badge mono">agent v{a.version}</span>}
            </div>
            <div className="row gap-3" style={{ fontSize: 11.5, color: "var(--fg-4)", flexWrap: "wrap" }}>
              {ip && <><span>IP <span className="mono" style={{ color: "var(--fg-3)" }}>{ip}</span></span><span>·</span></>}
              <span>{t("mon.connectedFor")} <span className="mono" style={{ color: "var(--fg-3)" }}>{a.connectedAt ? new Date(a.connectedAt).toLocaleString() : "—"}</span></span>
              <span>·</span>
              <span>{t("mon.heartbeat")} <span className="mono" style={{ color: "var(--fg-3)" }}>{a.lastHeartbeat ? new Date(a.lastHeartbeat).toLocaleTimeString() : "—"}</span></span>
            </div>
          </div>
          <div className="row gap-2">
            <button className="btn btn-sm" disabled={a.permission < 3} onClick={() => setTab("terminal")}>{I.term({ size: 13 })}<span>{t("mon.openTerminal")}</span></button>
            <button className="btn btn-sm btn-ghost btn-icon"><span>{I.more({ size: 14 })}</span></button>
          </div>
        </div>
        <div className="tabs" style={{ borderBottom: "none", marginBottom: -1, overflowX: "auto" }}>
          {tabs.map((tb) => {
            const disabled = tb.k === "terminal" && a.permission < 1
            return (
              <button key={tb.k} className={`tab ${tab === tb.k ? "active" : ""}`} onClick={() => !disabled && setTab(tb.k)} disabled={disabled}>
                {tb.icon} {tb.label}
                {disabled && <span className="dim" style={{ fontSize: 10 }}>{t("mon.noAccess")}</span>}
              </button>
            )
          })}
        </div>
      </div>

      <div style={{ flex: 1, overflow: "auto" }}>
        {tab === "realtime" &&
          (m ? <RealtimeTab m={m} history={hist} /> : <div style={{ padding: 40, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{status === "online" ? t("common.loading") : t("mon.offlineNoHistory")}</div>)}
        {tab === "history" && <HistoryTab agentId={a.id} />}
        {tab === "terminal" && <TerminalTab agentId={a.id} permission={a.permission} />}
        {tab === "processes" && <ProcessesTab agentId={a.id} />}
        {tab === "services" && <OnDemandTab agentId={a.id} host={a.hostname} kind="services" icon={I.bolt({ size: 24 })} disabled={status !== "online"} />}
        {tab === "docker" && <DockerTab agentId={a.id} />}
        {tab === "files" && <OnDemandTab agentId={a.id} host={a.hostname} kind="files" icon={I.audit({ size: 24 })} disabled={status !== "online"} />}
        {tab === "logs" && <AgentLogsTab agentId={a.id} permission={a.permission} />}
      </div>
    </div>
  )
}
