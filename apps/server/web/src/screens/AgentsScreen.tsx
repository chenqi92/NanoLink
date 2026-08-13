import { useCallback, useMemo, useRef, useState } from "react"
import { useVirtualizer } from "@tanstack/react-virtual"
import { useTranslation } from "react-i18next"
import { I, osIcon } from "@/lib/icons"
import { useData } from "@/contexts/DataContext"
import { useRouter } from "@/store/router"
import { PageHeader, EmptyState, Status, Perm } from "@/components/shell/primitives"
import { VirtualAgentGrid } from "@/components/monitor/VirtualAgentGrid"
import { agentStatus, osFamily, toneFor, formatRate } from "@/lib/format"
import { useAuth } from "@/contexts/AuthContext"

type Filter = "all" | "online" | "warn" | "offline"

export function AgentsScreen() {
  const { t } = useTranslation()
  const { agents, metrics, refresh } = useData()
  const { navigate } = useRouter()
  const { user } = useAuth()
  const [filter, setFilter] = useState<Filter>("all")
  const [view, setView] = useState<"grid" | "list">("grid")
  const [q, setQ] = useState("")
  const scrollRef = useRef<HTMLDivElement>(null)

  const openAgent = useCallback((id: string) => navigate("agent-detail", { agentId: id }), [navigate])

  function warnLevel(id: string): boolean {
    const m = metrics[id]
    if (!m) return false
    const memPct = m.memory?.total ? (m.memory.used / m.memory.total) * 100 : 0
    return (m.cpu?.usagePercent ?? 0) > 85 || memPct > 85 || (m.disks ?? []).some((d) => d.usagePercent > 85)
  }

  const counts = useMemo(() => {
    let online = 0
    let warn = 0
    let offline = 0
    for (const a of agents) {
      if (agentStatus(a.lastHeartbeat) !== "online") offline++
      else {
        online++
        if (warnLevel(a.id)) warn++
      }
    }
    return { all: agents.length, online, warn, offline }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [agents, metrics])

  const filtered = useMemo(
    () =>
      agents.filter((a) => {
        const ql = q.toLowerCase()
        if (ql && !(a.hostname.toLowerCase().includes(ql) || a.os.toLowerCase().includes(ql) || a.id.toLowerCase().includes(ql))) return false
        const online = agentStatus(a.lastHeartbeat) === "online"
        if (filter === "online") return online
        if (filter === "offline") return !online
        if (filter === "warn") return online && warnLevel(a.id)
        return true
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [agents, metrics, q, filter],
  )

  // List-view row virtualization. Uses top/bottom spacer rows inside <tbody> so
  // native table column sizing, border-collapse and the sticky <th> all stay
  // intact while only visible <tr>s mount.
  const ROW_H = 41 // 10px*2 padding + ~21px content; uniform across rows
  const listVirtualizer = useVirtualizer({
    count: filtered.length,
    getScrollElement: () => scrollRef.current,
    estimateSize: () => ROW_H,
    overscan: 8,
    enabled: view === "list",
  })
  const listRows = listVirtualizer.getVirtualItems()
  const padTop = listRows.length ? listRows[0].start : 0
  const padBottom = listRows.length ? listVirtualizer.getTotalSize() - listRows[listRows.length - 1].end : 0

  const chips: { k: Filter; label: string; n: number }[] = [
    { k: "all", label: t("mon.all"), n: counts.all },
    { k: "online", label: t("status.online"), n: counts.online },
    { k: "warn", label: t("mon.warn"), n: counts.warn },
    { k: "offline", label: t("status.offline"), n: counts.offline },
  ]

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader
        title={t("nav.agents")}
        actions={
          <>
            <button className="btn btn-sm" onClick={() => refresh()}>{I.refresh({ size: 13 })}<span>{t("mon.refresh")}</span></button>
            {user?.isSuperAdmin && <button className="btn btn-sm btn-primary" onClick={() => navigate("tokens", { openWizard: true })}>{I.plus({ size: 13 })}<span>{t("wizard.addAgent")}</span></button>}
          </>
        }
      />
      <div ref={scrollRef} style={{ padding: "0 24px 24px", overflow: "auto", flex: 1 }}>
        {/* toolbar */}
        <div className="row gap-3" style={{ marginBottom: 14, justifyContent: "space-between", flexWrap: "wrap" }}>
          <div className="row gap-2" style={{ flexWrap: "wrap" }}>
            <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 10px", height: 30, minWidth: 240 }}>
              {I.search({ size: 13 })}
              <input value={q} onChange={(e) => setQ(e.target.value)} placeholder={t("mon.searchAgents")} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "inherit", fontSize: 12 }} />
            </div>
            <div className="row gap-1">
              {chips.map((c) => (
                <button key={c.k} className="btn btn-sm" onClick={() => setFilter(c.k)} style={filter === c.k ? { background: "var(--accent)", color: "var(--accent-fg)", borderColor: "var(--accent)" } : {}}>
                  {c.label} <span className="mono num" style={{ opacity: 0.7 }}>{c.n}</span>
                </button>
              ))}
            </div>
          </div>
          <div className="row gap-1">
            <button className="btn btn-sm btn-icon" onClick={() => setView("grid")} style={view === "grid" ? { background: "var(--panel-3)", color: "var(--fg)" } : {}} title={t("mon.grid")}>{I.dashboard({ size: 13 })}</button>
            <button className="btn btn-sm btn-icon" onClick={() => setView("list")} style={view === "list" ? { background: "var(--panel-3)", color: "var(--fg)" } : {}} title={t("mon.list")}>{I.audit({ size: 13 })}</button>
          </div>
        </div>

        {filtered.length === 0 ? (
          <EmptyState icon={I.agents({ size: 28 })} title={t("mon.noAgents")} desc={agents.length ? undefined : t("mon.noAgentsDesc")} />
        ) : view === "grid" ? (
          <VirtualAgentGrid agents={filtered} metrics={metrics} onOpen={openAgent} scrollRef={scrollRef} />
        ) : (
          <div className="card" style={{ overflow: "hidden" }}>
            <table className="tbl">
              <thead>
                <tr>
                  <th>{t("nav.agents")}</th>
                  <th>OS</th>
                  <th>{t("status.online")}</th>
                  <th style={{ width: 130 }}>CPU</th>
                  <th style={{ width: 130 }}>MEM</th>
                  <th>{t("mon.netInterfaces")}</th>
                  <th>IP</th>
                  <th>{t("agent.version")}</th>
                  <th>{t("admin.permissions")}</th>
                  <th style={{ width: 28 }} />
                </tr>
              </thead>
              <tbody>
                {padTop > 0 && <tr style={{ height: padTop }}><td colSpan={10} style={{ padding: 0, border: "none" }} /></tr>}
                {listRows.map((vr) => {
                  const a = filtered[vr.index]
                  if (!a) return null
                  const m = metrics[a.id]
                  const cpu = m?.cpu?.usagePercent ?? 0
                  const mem = m?.memory?.total ? (m.memory.used / m.memory.total) * 100 : 0
                  const net = (m?.networks ?? []).find((n) => !n.interface.startsWith("lo") && ((n.ipAddresses?.length ?? 0) > 0 || n.rxBytesPerSec || n.txBytesPerSec))
                  const ip = net?.ipAddresses?.[0]
                  return (
                    <tr key={a.id} style={{ cursor: "pointer" }} onClick={() => openAgent(a.id)}>
                      <td>
                        <span className="row gap-2" style={{ alignItems: "center" }}>
                          <span style={{ color: "var(--fg-4)" }}>{osIcon(osFamily(a.os))}</span>
                          <span className="mono" style={{ fontWeight: 500 }}>{a.hostname}</span>
                        </span>
                      </td>
                      <td className="muted">{a.os} · {a.arch}</td>
                      <td><Status status={agentStatus(a.lastHeartbeat)} /></td>
                      <td>
                        <span className="row gap-2" style={{ alignItems: "center" }}>
                          <div className="meter" style={{ flex: 1, height: 4 }}><div className={`meter-fill ${toneFor(cpu)}`} style={{ width: `${Math.min(100, cpu)}%` }} /></div>
                          <span className="mono num" style={{ fontSize: 11, minWidth: 34, textAlign: "right", color: toneFor(cpu) ? `var(--${toneFor(cpu)})` : "var(--fg-2)" }}>{Math.round(cpu)}%</span>
                        </span>
                      </td>
                      <td>
                        <span className="row gap-2" style={{ alignItems: "center" }}>
                          <div className="meter" style={{ flex: 1, height: 4 }}><div className={`meter-fill ${toneFor(mem)}`} style={{ width: `${Math.min(100, mem)}%` }} /></div>
                          <span className="mono num" style={{ fontSize: 11, minWidth: 34, textAlign: "right", color: toneFor(mem) ? `var(--${toneFor(mem)})` : "var(--fg-2)" }}>{Math.round(mem)}%</span>
                        </span>
                      </td>
                      <td className="mono num dim" style={{ fontSize: 10.5, whiteSpace: "nowrap" }}>{net ? `↓${formatRate(net.rxBytesPerSec)} ↑${formatRate(net.txBytesPerSec)}` : "—"}</td>
                      <td className="mono dim" style={{ fontSize: 11 }}>{ip || "—"}</td>
                      <td className="mono dim">{a.version ? `v${a.version}` : "—"}</td>
                      <td><Perm level={a.permissionLevel} /></td>
                      <td style={{ textAlign: "right", color: "var(--fg-4)" }}>{I.chev({ size: 13 })}</td>
                    </tr>
                  )
                })}
                {padBottom > 0 && <tr style={{ height: padBottom }}><td colSpan={10} style={{ padding: 0, border: "none" }} /></tr>}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
