import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useData } from "@/contexts/DataContext"
import { useRouter } from "@/store/router"
import { PageHeader, KPI } from "@/components/shell/primitives"
import { EmptyState } from "@/components/shell/primitives"
import { LineChart } from "@/components/charts"
import { VirtualAgentGrid } from "@/components/monitor/VirtualAgentGrid"
import { agentStatus, formatBytes, toneFor } from "@/lib/format"

const MAX_PULSE = 80

export function DashboardScreen() {
  const { t } = useTranslation()
  const { agents, metrics, summary, refresh } = useData()
  const { navigate } = useRouter()
  const scrollRef = useRef<HTMLDivElement>(null)
  const openAgent = useCallback((id: string) => navigate("agent-detail", { agentId: id }), [navigate])

  const onlineAgents = agents.filter((a) => agentStatus(a.lastHeartbeat) === "online")

  // Derived KPIs (prefer summary, fall back to live metrics)
  const liveCpu = useMemo(() => {
    const vals = onlineAgents.map((a) => metrics[a.id]?.cpu?.usagePercent).filter((v): v is number => v != null)
    return vals.length ? vals.reduce((s, v) => s + v, 0) / vals.length : 0
  }, [onlineAgents, metrics])
  const avgCpu = +(summary.avgCpuPercent || liveCpu).toFixed(1)
  const avgMem = +(summary.memoryPercent || 0).toFixed(1)
  const usedMem = summary.usedMemory || 0

  const alerts = agents.filter((a) => {
    if (agentStatus(a.lastHeartbeat) !== "online") return true
    const m = metrics[a.id]
    if (!m) return false
    const memPct = m.memory?.total ? (m.memory.used / m.memory.total) * 100 : 0
    return (m.cpu?.usagePercent ?? 0) > 85 || memPct > 85 || (m.disks ?? []).some((d) => d.usagePercent > 85)
  }).length

  // Live fleet pulse (rolling avg cpu / mem)
  const [pulse, setPulse] = useState<{ cpu: number[]; mem: number[] }>({ cpu: [], mem: [] })
  const lastSample = useRef(0)
  useEffect(() => {
    const now = Date.now()
    if (now - lastSample.current < 1500) return
    lastSample.current = now
    setPulse((p) => ({
      cpu: [...p.cpu, avgCpu].slice(-MAX_PULSE),
      mem: [...p.mem, avgMem].slice(-MAX_PULSE),
    }))
  }, [avgCpu, avgMem])

  const cpuSeries = pulse.cpu.length > 1 ? pulse.cpu : [avgCpu, avgCpu]
  const memSeries = pulse.mem.length > 1 ? pulse.mem : [avgMem, avgMem]

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader
        eyebrow={t("mon.live")}
        title={t("mon.fleetOverview")}
        subtitle={t("mon.monitoringSubtitle", { online: onlineAgents.length, total: agents.length })}
        actions={
          <>
            <button className="btn btn-sm" onClick={() => refresh()}>
              {I.refresh({ size: 13 })}
              <span>{t("mon.refresh")}</span>
            </button>
            <button className="btn btn-sm btn-primary" onClick={() => navigate("tokens", { openWizard: true })}>
              {I.plus({ size: 13 })}
              <span>{t("wizard.addAgent")}</span>
            </button>
          </>
        }
      />
      <div ref={scrollRef} style={{ padding: "0 24px 24px", overflow: "auto", flex: 1 }}>
        {/* KPI strip */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: "var(--gap)" }}>
          <KPI
            icon={I.agents({ size: 13 })}
            label={t("mon.agentsOnline")}
            value={
              <>
                {onlineAgents.length}
                <span style={{ color: "var(--fg-4)", fontSize: 18 }}>/{agents.length}</span>
              </>
            }
            sub={t("mon.offlineCount", { count: agents.length - onlineAgents.length })}
            spark={cpuSeries.map(() => (agents.length ? (onlineAgents.length / agents.length) * 100 : 0))}
          />
          <KPI icon={I.cpu({ size: 13 })} label={t("mon.avgCpu")} value={`${avgCpu}%`} sub={t("mon.acrossOnline")} spark={cpuSeries} tone={toneFor(avgCpu)} />
          <KPI icon={I.mem({ size: 13 })} label={t("mon.avgMemory")} value={`${avgMem}%`} sub={t("mon.memUsedGiB", { value: formatBytes(usedMem) })} spark={memSeries} tone={toneFor(avgMem)} />
          <KPI icon={I.warn({ size: 13 })} label={t("mon.alerts")} value={alerts} sub={t("mon.needsAttention")} tone={alerts > 0 ? "warn" : ""} />
        </div>

        {/* Fleet pulse */}
        <div className="card" style={{ marginTop: 16, padding: 16 }}>
          <div className="row" style={{ justifyContent: "space-between", marginBottom: 12 }}>
            <div className="col" style={{ gap: 2 }}>
              <div className="upper" style={{ color: "var(--fg-4)" }}>{t("mon.fleetPulse")}</div>
              <div style={{ fontSize: 12, color: "var(--fg-3)" }}>{t("mon.fleetPulseSub")}</div>
            </div>
          </div>
          <LineChart
            height={140}
            yMax={100}
            unit="%"
            series={[
              { data: cpuSeries, label: "CPU avg", color: "var(--fg)", fill: true, fillOpacity: 0.08 },
              { data: memSeries, label: "Mem avg", color: "var(--fg-3)", dashed: true },
            ]}
            thresholds={[{ v: 90, label: "90%" }]}
          />
        </div>

        {/* Agent grid */}
        <div className="row" style={{ marginTop: 18, marginBottom: 10, justifyContent: "space-between", alignItems: "flex-end" }}>
          <div className="row gap-2" style={{ alignItems: "baseline" }}>
            <h2 className="display" style={{ fontSize: 14, fontWeight: 500, margin: 0 }}>{t("mon.agents")}</h2>
            <span className="dim mono" style={{ fontSize: 11 }}>{agents.length} {t("mon.total")}</span>
          </div>
          <button className="btn btn-sm btn-ghost" onClick={() => navigate("agents")}>
            {I.agents({ size: 13 })}
            <span>{t("nav.agents")}</span>
          </button>
        </div>

        {agents.length === 0 ? (
          <EmptyState
            icon={I.agents({ size: 28 })}
            title={t("mon.noAgents")}
            desc={t("mon.noAgentsDesc")}
            action={
              <button className="btn btn-sm btn-primary" onClick={() => navigate("tokens", { openWizard: true })}>
                {I.plus({ size: 13 })}
                <span>{t("wizard.addAgent")}</span>
              </button>
            }
          />
        ) : (
          <VirtualAgentGrid agents={agents} metrics={metrics} onOpen={openAgent} scrollRef={scrollRef} />
        )}
      </div>
    </div>
  )
}
