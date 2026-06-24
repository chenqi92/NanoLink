import { memo, type ReactNode } from "react"
import { useTranslation } from "react-i18next"
import { I, osIcon } from "@/lib/icons"
import type { Agent, Metrics } from "@/lib/api"
import { Status, Perm } from "@/components/shell/primitives"
import { agentStatus, osFamily, toneFor, formatBytes, formatRate, toGiB, type Tone } from "@/lib/format"

function MetricRow({ icon, label, pct, tone, sub }: { icon: ReactNode; label: string; pct: number; tone: Tone; sub: string }) {
  return (
    <div className="row" style={{ alignItems: "center", gap: 8 }}>
      <span className="row gap-1 muted" style={{ width: 38, fontSize: 10.5, alignItems: "center" }}>
        {icon} <span className="mono">{label}</span>
      </span>
      <div style={{ flex: 1 }}>
        <div className="meter" style={{ height: 4 }}>
          <div className={`meter-fill ${tone}`} style={{ width: `${pct}%` }} />
        </div>
      </div>
      <span className="mono num" style={{ width: 38, textAlign: "right", color: tone ? `var(--${tone})` : "var(--fg)", fontSize: 11.5 }}>{Math.round(pct)}%</span>
      <span className="mono dim" style={{ fontSize: 10, minWidth: 116, textAlign: "right" }}>{sub}</span>
    </div>
  )
}

export const AgentCard = memo(function AgentCard({ agent: a, metrics: m, onClick }: { agent: Agent; metrics?: Metrics; onClick: (id: string) => void }) {
  const { t } = useTranslation()
  const status = agentStatus(a.lastHeartbeat)
  const off = status !== "online"

  const cpuUse = m?.cpu?.usagePercent ?? 0
  const memUse = m?.memory && m.memory.total ? (m.memory.used / m.memory.total) * 100 : 0
  const disks = m?.disks ?? []
  const worstDisk = disks.length ? disks.reduce((w, d) => (d.usagePercent > w.usagePercent ? d : w), disks[0]) : null
  const net = (m?.networks ?? []).find((n) => n.isUp && n.rxBytesPerSec + n.txBytesPerSec > 0) || m?.networks?.[0]
  const gpus = m?.gpus ?? []
  const gpuAvg = gpus.length ? gpus.reduce((s, g) => s + g.usagePercent, 0) / gpus.length : 0

  return (
    <div
      className="card"
      onClick={() => onClick(a.id)}
      style={{ padding: 14, cursor: "pointer", position: "relative", opacity: off ? 0.65 : 1, transition: "border-color 80ms ease" }}
      onMouseEnter={(e) => (e.currentTarget.style.borderColor = "var(--border-strong)")}
      onMouseLeave={(e) => (e.currentTarget.style.borderColor = "var(--border)")}
    >
      <div className="row gap-2" style={{ alignItems: "flex-start", justifyContent: "space-between" }}>
        <div className="row gap-2" style={{ alignItems: "center", minWidth: 0, flex: 1 }}>
          <span style={{ color: "var(--fg-4)" }}>{osIcon(osFamily(a.os))}</span>
          <div className="col" style={{ gap: 1, minWidth: 0 }}>
            <div className="mono truncate" style={{ fontWeight: 500, fontSize: 12.5, color: "var(--fg)" }}>{a.hostname}</div>
            <div className="dim truncate" style={{ fontSize: 10.5 }}>{a.os} · {a.arch}</div>
          </div>
        </div>
        <div className="col" style={{ alignItems: "flex-end", gap: 4 }}>
          <Status status={status} />
          <Perm level={a.permission} />
        </div>
      </div>

      <div className="hr" />

      {off || !m ? (
        <div style={{ padding: "12px 0 4px", color: "var(--fg-4)", fontSize: 11.5, display: "flex", alignItems: "center", gap: 8 }}>
          {I.warn({ size: 13 })}
          {off ? t("mon.offlineLast", { time: a.lastHeartbeat ? new Date(a.lastHeartbeat).toLocaleTimeString() : "—" }) : t("common.loading")}
        </div>
      ) : (
        <div className="col gap-3" style={{ paddingTop: 4 }}>
          <MetricRow icon={I.cpu({ size: 11 })} label="CPU" pct={cpuUse} tone={toneFor(cpuUse)} sub={`${m.cpu.coreCount}c · ${(m.cpu.frequencyMhz / 1000).toFixed(1)} GHz${m.cpu.temperature ? ` · ${Math.round(m.cpu.temperature)}°C` : ""}`} />
          <MetricRow icon={I.mem({ size: 11 })} label="MEM" pct={memUse} tone={toneFor(memUse)} sub={`${formatBytes(m.memory.used)} / ${formatBytes(m.memory.total)}`} />
          {worstDisk && <MetricRow icon={I.disk({ size: 11 })} label="DSK" pct={worstDisk.usagePercent} tone={toneFor(worstDisk.usagePercent)} sub={`${worstDisk.mountPoint} · ${toGiB(worstDisk.used).toFixed(0)}/${toGiB(worstDisk.total).toFixed(0)} GiB`} />}
          {net && (
            <div className="row" style={{ alignItems: "center", gap: 8, fontSize: 11.5 }}>
              <span className="row gap-1 muted" style={{ width: 38, fontSize: 10.5, alignItems: "center" }}>{I.net({ size: 11 })} <span className="mono">NET</span></span>
              <span className="mono num" style={{ flex: 1, color: "var(--fg-3)" }}>
                <span style={{ color: "var(--fg)" }}>↓ {formatRate(net.rxBytesPerSec)}</span>
                <span style={{ marginLeft: 10, color: "var(--fg)" }}>↑ {formatRate(net.txBytesPerSec)}</span>
              </span>
              <span className="mono dim" style={{ fontSize: 10.5 }}>{net.ipAddresses?.[0] ?? ""}</span>
            </div>
          )}
          {gpus.length > 0 && (
            <div className="row" style={{ alignItems: "center", gap: 8, fontSize: 11.5 }}>
              <span className="row gap-1 muted" style={{ width: 38, fontSize: 10.5, alignItems: "center" }}>{I.gpu({ size: 11 })} <span className="mono">GPU</span></span>
              <span className="mono num truncate" style={{ flex: 1, color: "var(--fg-2)" }}>
                {gpus.length}× {gpus[0].name.split(" ").slice(1, 3).join(" ") || gpus[0].name}
                <span className="dim"> · </span>
                <span style={{ color: gpuAvg > 90 ? "var(--crit)" : "var(--fg)" }}>{Math.round(gpuAvg)}%</span>
              </span>
              <span className="mono dim" style={{ fontSize: 10.5 }}>{Math.round(gpus[0].temperature)}°C</span>
            </div>
          )}
        </div>
      )}

      <div className="hr" />
      <div className="row" style={{ justifyContent: "space-between", alignItems: "center" }}>
        <span className="badge" style={{ height: 18, fontSize: 10 }}>{a.version ? `v${a.version}` : "—"}</span>
        <span className="mono dim" style={{ fontSize: 10.5 }}>{a.id.slice(-8)}</span>
      </div>
    </div>
  )
})
