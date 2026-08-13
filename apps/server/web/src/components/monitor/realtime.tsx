import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import type { Metrics, CpuMetrics, MemoryMetrics, GpuMetrics, NpuMetrics } from "@/lib/api"
import { Donut, CoreMatrix, Sparkline } from "@/components/charts"
import { SectionPanel, KVRow } from "@/components/shell/primitives"
import { formatBytes, formatRate, toGiB, toneFor, tempTone, formatUptime } from "@/lib/format"

function EmptyRow({ msg }: { msg: string }) {
  return <div style={{ padding: 20, textAlign: "center", color: "var(--fg-4)", fontSize: 12 }}>{msg}</div>
}

export function CpuPanel({ cpu, load, history, historyLabels }: { cpu: CpuMetrics; load?: number[]; history?: number[]; historyLabels?: string[] }) {
  const { t } = useTranslation()
  const cores = cpu.perCoreUsage?.length ? cpu.perCoreUsage : Array.from({ length: cpu.coreCount || 0 }, () => cpu.usagePercent)
  const loadStr = (load ?? cpu.loadAverage ?? []).map((v) => v.toFixed(2)).join(" ")
  return (
    <div className="card" style={{ padding: 16 }}>
      <div className="row" style={{ justifyContent: "space-between", marginBottom: 14 }}>
        <div className="row gap-2" style={{ alignItems: "center", color: "var(--fg-2)" }}>
          {I.cpu({ size: 13 })} <span style={{ fontWeight: 500, fontSize: 12 }}>{t("metrics.cpu")}</span>
          <span className="dim mono" style={{ fontSize: 10.5 }}>{cpu.coreCount}c / {cpu.logicalCores || cpu.coreCount}t</span>
        </div>
        <div className="row gap-3 mono" style={{ fontSize: 11, color: "var(--fg-4)" }}>
          {loadStr && <span>{t("metrics.load")} <span style={{ color: "var(--fg-3)" }}>{loadStr}</span></span>}
          {cpu.temperature > 0 && <span style={{ color: tempTone(cpu.temperature) ? `var(--${tempTone(cpu.temperature)})` : "var(--fg-4)" }}>{Math.round(cpu.temperature)}°C</span>}
        </div>
      </div>
      <div className="row gap-4" style={{ alignItems: "center" }}>
        <Donut name={t("metrics.cpu")} value={cpu.usagePercent} size={96} thickness={7} label={`${Math.round(cpu.usagePercent)}%`} sub={cpu.frequencyMhz ? `${(cpu.frequencyMhz / 1000).toFixed(1)} GHz` : undefined} />
        <div className="col flex-1 gap-3">
          <div className="col" style={{ gap: 2 }}>
            <div className="dim" style={{ fontSize: 10.5 }}>{t("mon.model")}</div>
            <div className="mono" style={{ fontSize: 12, color: "var(--fg)" }}>{cpu.model || "—"}</div>
            <div className="dim mono" style={{ fontSize: 10.5 }}>{[cpu.vendor, cpu.architecture, cpu.frequencyMaxMhz ? `${t("metrics.max")} ${(cpu.frequencyMaxMhz / 1000).toFixed(2)} GHz` : ""].filter(Boolean).join(" · ")}</div>
          </div>
          {history && history.length > 1 && (
            <div style={{ color: "var(--fg-2)" }}>
              <div className="dim upper" style={{ marginBottom: 4 }}>{t("mon.lastHour")}</div>
              <Sparkline data={history} h={28} label={t("metrics.cpu")} unit="%" pointLabels={historyLabels} />
            </div>
          )}
        </div>
      </div>
      {cores.length > 0 && (
        <>
          <div className="hr" />
          <div className="col" style={{ gap: 6 }}>
            <div className="row" style={{ justifyContent: "space-between" }}>
              <span className="dim upper">{t("mon.perCore")}</span>
              <span className="mono dim" style={{ fontSize: 10.5 }}>{cores.length} {t("mon.cores")}</span>
            </div>
            <CoreMatrix cores={cores} label={t("metrics.core")} />
          </div>
        </>
      )}
    </div>
  )
}

export function MemPanel({ mem, history, historyLabels }: { mem: MemoryMetrics; history?: number[]; historyLabels?: string[] }) {
  const { t } = useTranslation()
  const pct = mem.total ? (mem.used / mem.total) * 100 : 0
  const swapPct = mem.swapTotal > 0 ? (mem.swapUsed / mem.swapTotal) * 100 : 0
  return (
    <div className="card" style={{ padding: 16 }}>
      <div className="row" style={{ justifyContent: "space-between", marginBottom: 14 }}>
        <div className="row gap-2" style={{ alignItems: "center", color: "var(--fg-2)" }}>
          {I.mem({ size: 13 })} <span style={{ fontWeight: 500, fontSize: 12 }}>{t("metrics.memory")}</span>
        </div>
        {mem.memoryType && <span className="dim mono" style={{ fontSize: 10.5 }}>{mem.memoryType}{mem.memorySpeedMhz ? ` · ${mem.memorySpeedMhz} MT/s` : ""}</span>}
      </div>
      <div className="row gap-4" style={{ alignItems: "center" }}>
        <Donut name={t("metrics.memory")} value={pct} size={96} thickness={7} label={`${Math.round(pct)}%`} sub={`${formatBytes(mem.used)} / ${formatBytes(mem.total)}`} />
        <div className="col flex-1 gap-3">
          <div className="col" style={{ gap: 6 }}>
            <KVRow label={t("metrics.used")} value={formatBytes(mem.used)} />
            <KVRow label={t("metrics.available")} value={formatBytes(mem.available)} />
            {mem.cached > 0 && <KVRow label={t("metrics.cache")} value={formatBytes(mem.cached)} />}
            <KVRow label={t("metrics.swap")} value={`${formatBytes(mem.swapUsed)} / ${formatBytes(mem.swapTotal)}`} />
          </div>
          {history && history.length > 1 && (
            <div style={{ color: "var(--fg-2)" }}>
              <Sparkline data={history} h={28} label={t("metrics.memory")} unit="%" pointLabels={historyLabels} />
            </div>
          )}
        </div>
      </div>
      {swapPct > 5 && (
        <div className="row gap-2" style={{ marginTop: 10, padding: "6px 8px", background: "rgba(245,158,11,.08)", border: "1px solid rgba(245,158,11,.25)", borderRadius: 6, fontSize: 11.5 }}>
          <span style={{ color: "var(--warn)" }}>{I.warn({ size: 12 })}</span>
          <span style={{ color: "var(--fg-2)" }}>{t("mon.swapPressure", { pct: Math.round(swapPct) })}</span>
        </div>
      )}
    </div>
  )
}

function GpuMetric({ label, pct, val, tone }: { label: string; pct: number; val: string; tone?: string }) {
  return (
    <div className="col" style={{ gap: 4 }}>
      <div className="row" style={{ justifyContent: "space-between" }}>
        <span className="dim" style={{ fontSize: 10.5 }}>{label}</span>
        <span className="mono num" style={{ fontSize: 11, color: tone ? `var(--${tone})` : "var(--fg-2)" }}>{val}</span>
      </div>
      <div className="meter">
        <div className={`meter-fill ${tone ?? ""}`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  )
}

export function GpuCard({ gpu }: { gpu: GpuMetrics }) {
  const { t } = useTranslation()
  const memPct = gpu.memoryTotal ? (gpu.memoryUsed / gpu.memoryTotal) * 100 : 0
  const pwrPct = gpu.powerLimitWatts ? (gpu.powerWatts / gpu.powerLimitWatts) * 100 : 0
  return (
    <div style={{ border: "1px solid var(--border)", borderRadius: 6, padding: 12, background: "var(--panel-2)" }}>
      <div className="row" style={{ justifyContent: "space-between", marginBottom: 10 }}>
        <div className="col" style={{ gap: 2, minWidth: 0 }}>
          <div className="mono truncate" style={{ fontSize: 12, fontWeight: 500 }}>{gpu.name}</div>
          <div className="dim mono truncate" style={{ fontSize: 10.5 }}>{[gpu.vendor, gpu.driverVersion, gpu.pcieGeneration].filter(Boolean).join(" · ")}</div>
        </div>
        <div className="row gap-3 mono num" style={{ fontSize: 11, color: "var(--fg-4)", alignItems: "center" }}>
          {gpu.temperature > 0 && <span style={{ color: tempTone(gpu.temperature) ? `var(--${tempTone(gpu.temperature)})` : "var(--fg-3)" }}>{Math.round(gpu.temperature)}°C</span>}
          {gpu.fanSpeedPercent > 0 && <span>{t("metrics.fan")} {gpu.fanSpeedPercent}%</span>}
        </div>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(110px, 1fr))", gap: 10, marginBottom: 8 }}>
        <GpuMetric label={t("mon.util")} pct={gpu.usagePercent} val={`${Math.round(gpu.usagePercent)}%`} tone={toneFor(gpu.usagePercent)} />
        {gpu.memoryTotal > 0 && <GpuMetric label={t("mon.vram")} pct={memPct} val={`${formatBytes(gpu.memoryUsed)} / ${formatBytes(gpu.memoryTotal)}`} tone={toneFor(memPct)} />}
        {gpu.powerLimitWatts > 0 && <GpuMetric label={t("metrics.power")} pct={pwrPct} val={`${gpu.powerWatts} / ${gpu.powerLimitWatts} W`} tone={pwrPct > 90 ? "warn" : ""} />}
      </div>
      <div className="row gap-3" style={{ fontSize: 10.5, color: "var(--fg-4)", fontFamily: "var(--font-mono)", flexWrap: "wrap" }}>
        {gpu.clockCoreMhz > 0 && <span>{t("metrics.core")} {gpu.clockCoreMhz} MHz</span>}
        {gpu.clockMemoryMhz > 0 && <span>{t("metrics.memoryClock")} {gpu.clockMemoryMhz} MHz</span>}
        {gpu.encoderUsage > 0 && <span>{t("metrics.encode")} {Math.round(gpu.encoderUsage)}%</span>}
        {gpu.decoderUsage > 0 && <span>{t("metrics.decode")} {Math.round(gpu.decoderUsage)}%</span>}
      </div>
    </div>
  )
}

export function NpuCard({ npu }: { npu: NpuMetrics }) {
  const { t } = useTranslation()
  const memPct = npu.memoryTotal ? (npu.memoryUsed / npu.memoryTotal) * 100 : 0
  return (
    <div style={{ border: "1px solid var(--border)", borderRadius: 6, padding: 12, background: "var(--panel-2)" }}>
      <div className="row" style={{ justifyContent: "space-between", marginBottom: 8 }}>
        <div className="col" style={{ gap: 2, minWidth: 0 }}>
          <div className="mono truncate" style={{ fontSize: 12, fontWeight: 500 }}>{npu.name}</div>
          <div className="dim mono truncate" style={{ fontSize: 10.5 }}>{[npu.vendor, npu.driverVersion].filter(Boolean).join(" · ")}</div>
        </div>
        <span className="mono dim" style={{ fontSize: 10.5 }}>{npu.temperature > 0 ? `${Math.round(npu.temperature)}°C` : ""}{npu.powerWatts ? ` · ${npu.powerWatts}W` : ""}</span>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(110px, 1fr))", gap: 10 }}>
        <GpuMetric label={t("metrics.utilization")} pct={npu.usagePercent} val={`${Math.round(npu.usagePercent)}%`} tone={toneFor(npu.usagePercent)} />
        {npu.memoryTotal > 0 && <GpuMetric label={t("metrics.memory")} pct={memPct} val={`${formatBytes(npu.memoryUsed)} / ${formatBytes(npu.memoryTotal)}`} />}
      </div>
    </div>
  )
}

export function RealtimeTab({ m, history }: { m: Metrics; history?: { cpu: number[]; mem: number[]; timestamps: string[] } }) {
  const { t, i18n } = useTranslation()
  const disks = m.disks ?? []
  const nets = (m.networks ?? []).filter((n) => !n.interface.startsWith("lo"))
  const gpus = m.gpus ?? []
  const npus = m.npus ?? []
  const sessions = m.userSessions ?? []
  const sys = m.systemInfo
  const historyLabels = (history?.timestamps ?? []).map((timestamp) => {
    const date = new Date(timestamp)
    return Number.isNaN(date.getTime())
      ? timestamp
      : date.toLocaleTimeString(i18n.resolvedLanguage || i18n.language, { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false })
  })

  return (
    <div className="col" style={{ padding: 20, gap: 16 }}>
      <div className="responsive-split-grid" style={{ gap: 16 }}>
        <CpuPanel cpu={m.cpu} load={m.loadAverage} history={history?.cpu} historyLabels={historyLabels} />
        <MemPanel mem={m.memory} history={history?.mem} historyLabels={historyLabels} />
      </div>

      <SectionPanel title={t("mon.storage")} icon={I.disk({ size: 13 })} count={disks.length} bodyStyle={{ padding: 0 }}>
        {disks.length === 0 ? (
          <EmptyRow msg={t("common.noData")} />
        ) : (
          <table className="tbl">
            <thead>
              <tr>
                <th>{t("mon.mount")}</th>
                <th>{t("mon.device")}</th>
                <th>{t("metrics.fileSystem")}</th>
                <th style={{ width: 200 }}>{t("mon.usage")}</th>
                <th style={{ textAlign: "right" }}>{t("metrics.read")}</th>
                <th style={{ textAlign: "right" }}>{t("metrics.write")}</th>
                <th style={{ textAlign: "right" }}>{t("mon.health")}</th>
              </tr>
            </thead>
            <tbody>
              {disks.map((d, i) => (
                <tr key={i}>
                  <td className="mono">{d.mountPoint}</td>
                  <td className="mono dim" style={{ fontSize: 11 }}>{d.device}</td>
                  <td className="mono">{d.fsType}</td>
                  <td>
                    <div className="row gap-2" style={{ alignItems: "center" }}>
                      <div className="meter" style={{ flex: 1, height: 4 }}>
                        <div className={`meter-fill ${toneFor(d.usagePercent)}`} style={{ width: `${d.usagePercent}%` }} />
                      </div>
                      <span className="mono num" style={{ fontSize: 11, color: toneFor(d.usagePercent) ? `var(--${toneFor(d.usagePercent)})` : "var(--fg-2)", minWidth: 32, textAlign: "right" }}>{Math.round(d.usagePercent)}%</span>
                      <span className="mono dim" style={{ fontSize: 10.5 }}>{toGiB(d.used).toFixed(0)}/{toGiB(d.total).toFixed(0)} GiB</span>
                    </div>
                  </td>
                  <td className="mono num" style={{ textAlign: "right" }}>{formatRate(d.readBytesPerSec)}</td>
                  <td className="mono num" style={{ textAlign: "right" }}>{formatRate(d.writeBytesPerSec)}</td>
                  <td style={{ textAlign: "right" }}>
                    {d.healthStatus ? <span className={`badge ${d.healthStatus === "healthy" ? "ok" : "warn"}`}>{d.healthStatus}</span> : <span className="dim">—</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </SectionPanel>

      <SectionPanel title={t("mon.netInterfaces")} icon={I.net({ size: 13 })} count={nets.length} bodyStyle={{ padding: 0 }}>
        {nets.length === 0 ? (
          <EmptyRow msg={t("common.noData")} />
        ) : (
          <table className="tbl">
            <thead>
              <tr>
                <th>{t("mon.iface")}</th>
                <th>{t("mon.link")}</th>
                <th>{t("mon.address")}</th>
                <th style={{ textAlign: "right" }}>{t("metrics.rx")}</th>
                <th style={{ textAlign: "right" }}>{t("metrics.tx")}</th>
                <th style={{ textAlign: "right" }}>{t("mon.speed")}</th>
              </tr>
            </thead>
            <tbody>
              {nets.map((n, i) => (
                <tr key={i}>
                  <td className="mono">{n.interface}<span className="dim" style={{ marginLeft: 6, fontSize: 10.5 }}>{n.interfaceType}</span></td>
                  <td>
                    <span className={`dot ${n.isUp ? "ok" : "crit"}`} /> <span style={{ fontSize: 11 }}>{n.isUp ? t("mon.up") : t("mon.down")}</span>
                  </td>
                  <td className="mono dim" style={{ fontSize: 11 }}>{(n.ipAddresses ?? []).join(", ") || "—"}</td>
                  <td className="mono num" style={{ textAlign: "right" }}>{formatRate(n.rxBytesPerSec)}</td>
                  <td className="mono num" style={{ textAlign: "right" }}>{formatRate(n.txBytesPerSec)}</td>
                  <td className="mono num" style={{ textAlign: "right", color: "var(--fg-3)" }}>{n.speedMbps ? (n.speedMbps >= 1000 ? `${(n.speedMbps / 1000).toFixed(0)} Gb/s` : `${n.speedMbps} Mb/s`) : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </SectionPanel>

      {(gpus.length > 0 || npus.length > 0) && (
        <div className={gpus.length && npus.length ? "responsive-split-grid" : ""} style={{ display: "grid", gridTemplateColumns: gpus.length && npus.length ? undefined : "1fr", gap: 16 }}>
          {gpus.length > 0 && (
            <SectionPanel title={t("mon.gpus")} icon={I.gpu({ size: 13 })} count={gpus.length}>
              <div className="col gap-3">{gpus.map((g, i) => <GpuCard key={i} gpu={g} />)}</div>
            </SectionPanel>
          )}
          {npus.length > 0 && (
            <SectionPanel title={t("mon.npus")} icon={I.npu({ size: 13 })} count={npus.length}>
              <div className="col gap-3">{npus.map((n, i) => <NpuCard key={i} npu={n} />)}</div>
            </SectionPanel>
          )}
        </div>
      )}

      <div className="responsive-split-grid responsive-split-grid--balanced" style={{ gap: 16 }}>
        <SectionPanel title={t("mon.userSessions")} icon={I.user({ size: 13 })} count={sessions.length} bodyStyle={{ padding: 0 }}>
          {sessions.length === 0 ? (
            <EmptyRow msg={t("mon.noSessions")} />
          ) : (
            <table className="tbl">
              <thead><tr><th>{t("sessions.user")}</th><th>{t("sessions.tty")}</th><th>{t("mon.from")}</th><th>{t("sessions.idle")}</th><th>{t("sessions.type")}</th></tr></thead>
              <tbody>
                {sessions.map((s, i) => (
                  <tr key={i}>
                    <td className="mono">{s.username}</td>
                    <td className="mono dim">{s.tty}</td>
                    <td className="mono dim">{s.remoteHost || "—"}</td>
                    <td className="mono dim">{s.idleSeconds ? `${Math.round(s.idleSeconds / 60)}m` : "0"}</td>
                    <td><span className="badge">{s.sessionType}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </SectionPanel>

        <SectionPanel title={t("system.info")} icon={I.info({ size: 13 })}>
          <div className="col" style={{ gap: 6, fontSize: 12 }}>
            <KVRow label={t("system.osName")} value={sys ? `${sys.osName} ${sys.osVersion}` : "—"} />
            <KVRow label={t("system.kernel")} value={sys?.kernelVersion || "—"} />
            <KVRow label={t("system.uptime")} value={sys ? formatUptime(sys.uptimeSeconds) : "—"} />
            <KVRow label={t("system.hostname")} value={sys?.hostname || "—"} />
            {sys?.systemModel && <KVRow label={t("system.systemModel")} value={`${sys.systemVendor} ${sys.systemModel}`} />}
            {sys?.motherboardModel && <KVRow label={t("mon.board")} value={`${sys.motherboardVendor} ${sys.motherboardModel}`} />}
            {sys?.biosVersion && <KVRow label={t("system.bios")} value={sys.biosVersion} />}
          </div>
        </SectionPanel>
      </div>
    </div>
  )
}
