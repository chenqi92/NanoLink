import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { metricsApi, type Metrics } from "@/lib/api"
import { LineChart } from "@/components/charts"

type Range = "5m" | "30m" | "1h" | "6h" | "1d" | "7d" | "30d"

const RANGE_MS: Record<Range, number> = {
  "5m": 5 * 60e3,
  "30m": 30 * 60e3,
  "1h": 60 * 60e3,
  "6h": 6 * 60 * 60e3,
  "1d": 24 * 60 * 60e3,
  "7d": 7 * 24 * 60 * 60e3,
  "30d": 30 * 24 * 60 * 60e3,
}
const RANGE_INTERVAL: Record<Range, string> = {
  "5m": "1m",
  "30m": "1m",
  "1h": "1m",
  "6h": "5m",
  "1d": "5m",
  "7d": "1h",
  "30d": "1d",
}
const RANGES: Range[] = ["5m", "30m", "1h", "6h", "1d", "7d", "30d"]

function ChartHead({ title, sub, stat, peak }: { title: string; sub?: string; stat?: string; peak?: string }) {
  return (
    <div className="row" style={{ justifyContent: "space-between", marginBottom: 8, alignItems: "baseline" }}>
      <div className="row gap-2" style={{ alignItems: "baseline" }}>
        <span style={{ fontSize: 12, fontWeight: 500 }}>{title}</span>
        {sub && <span className="dim" style={{ fontSize: 11 }}>{sub}</span>}
      </div>
      <div className="row gap-3" style={{ alignItems: "baseline" }}>
        {peak && <span className="mono dim" style={{ fontSize: 10.5 }}>peak {peak}</span>}
        {stat && <span className="mono num" style={{ fontSize: 13, fontWeight: 500 }}>{stat}</span>}
      </div>
    </div>
  )
}

const toMB = (b: number) => +(b / 1e6).toFixed(2)
const peakOf = (arr: number[]) => (arr.length ? Math.max(...arr) : 0)

export function HistoryTab({ agentId }: { agentId: string }) {
  const { t } = useTranslation()
  const [range, setRange] = useState<Range>("1h")
  const [autoRefresh, setAutoRefresh] = useState(true)
  const [history, setHistory] = useState<Metrics[]>([])
  const [loading, setLoading] = useState(true)
  const timer = useRef<ReturnType<typeof setInterval> | null>(null)

  const fetchHistory = useCallback(async () => {
    try {
      const end = Date.now()
      const start = end - RANGE_MS[range]
      const data = await metricsApi.history(agentId, start, end, RANGE_INTERVAL[range])
      setHistory(Array.isArray(data) ? data : [])
    } catch {
      setHistory([])
    } finally {
      setLoading(false)
    }
  }, [agentId, range])

  useEffect(() => {
    setLoading(true)
    fetchHistory()
  }, [fetchHistory])

  useEffect(() => {
    if (timer.current) clearInterval(timer.current)
    if (autoRefresh) {
      timer.current = setInterval(fetchHistory, 10_000)
    }
    return () => {
      if (timer.current) clearInterval(timer.current)
    }
  }, [autoRefresh, fetchHistory])

  const series = useMemo(() => {
    const cpu = history.map((m) => m.cpu?.usagePercent ?? 0)
    const mem = history.map((m) => (m.memory?.total ? (m.memory.used / m.memory.total) * 100 : 0))
    const netRx = history.map((m) => toMB((m.networks ?? []).reduce((s, n) => s + (n.rxBytesPerSec || 0), 0)))
    const netTx = history.map((m) => toMB((m.networks ?? []).reduce((s, n) => s + (n.txBytesPerSec || 0), 0)))
    const diskR = history.map((m) => toMB((m.disks ?? []).reduce((s, d) => s + (d.readBytesPerSec || 0), 0)))
    const diskW = history.map((m) => toMB((m.disks ?? []).reduce((s, d) => s + (d.writeBytesPerSec || 0), 0)))
    const hasGpu = history.some((m) => (m.gpus?.length ?? 0) > 0)
    const gpuUse = hasGpu ? history.map((m) => (m.gpus?.length ? m.gpus.reduce((s, g) => s + g.usagePercent, 0) / m.gpus.length : 0)) : null
    const gpuTemp = hasGpu ? history.map((m) => (m.gpus?.length ? m.gpus.reduce((s, g) => s + g.temperature, 0) / m.gpus.length : 0)) : null
    return { cpu, mem, netRx, netTx, diskR, diskW, gpuUse, gpuTemp }
  }, [history])

  const xLabels = [`-${range}`, "", "", "", "now"]
  const cur = history.length ? history[history.length - 1] : undefined
  const cpuMax = peakOf(series.cpu)
  const memMax = peakOf(series.mem)

  return (
    <div className="col" style={{ padding: 20, gap: 16 }}>
      {/* toolbar */}
      <div className="row" style={{ justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 12 }}>
        <div className="row gap-1" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: 3 }}>
          {RANGES.map((r) => (
            <button
              key={r}
              onClick={() => setRange(r)}
              className="btn btn-sm"
              style={{
                background: range === r ? "var(--panel)" : "transparent",
                border: range === r ? "1px solid var(--border-2)" : "1px solid transparent",
                color: range === r ? "var(--fg)" : "var(--fg-4)",
                height: 24,
                padding: "0 10px",
                fontFamily: "var(--font-mono)",
                fontSize: 11,
              }}
            >
              {r}
            </button>
          ))}
        </div>
        <div className="row gap-3" style={{ alignItems: "center" }}>
          <label className="row gap-2 muted" style={{ alignItems: "center", fontSize: 11.5, cursor: "pointer" }}>
            <input type="checkbox" checked={autoRefresh} onChange={(e) => setAutoRefresh(e.target.checked)} style={{ accentColor: "var(--fg)" }} />
            <span>{t("metrics.realtime")}</span>
          </label>
          <span className="row gap-2 muted" style={{ fontSize: 11, alignItems: "center" }}>
            <span className={`dot ${autoRefresh ? "pulse ok" : "off"}`} />
            <span className="mono">{history.length}pt</span>
          </span>
          <button className="btn btn-sm btn-ghost" onClick={() => fetchHistory()}>{I.refresh({ size: 13 })}</button>
        </div>
      </div>

      {loading && history.length === 0 ? (
        <div style={{ padding: 40, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("common.loading")}</div>
      ) : history.length === 0 ? (
        <div className="card" style={{ padding: "40px 24px", textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("common.noData")}</div>
      ) : (
        <>
          {(cpuMax > 90 || memMax > 90) && (
            <div className="card" style={{ padding: 12, background: "rgba(245,158,11,.04)", border: "1px solid rgba(245,158,11,.2)", display: "flex", gap: 12, alignItems: "flex-start" }}>
              <span style={{ color: "var(--warn)", marginTop: 2 }}>{I.warn({ size: 14 })}</span>
              <div className="col" style={{ gap: 4, flex: 1 }}>
                <div style={{ fontSize: 12.5, fontWeight: 500 }}>{t("metrics.anomalyDetected")}</div>
                <ul className="col" style={{ margin: 0, padding: 0, gap: 3, listStyle: "none", fontSize: 11.5, color: "var(--fg-3)" }}>
                  {cpuMax > 90 && <li>· CPU peak {Math.round(cpuMax)}%</li>}
                  {memMax > 90 && <li>· Memory peak {Math.round(memMax)}%</li>}
                </ul>
              </div>
            </div>
          )}

          <div className="card" style={{ padding: 16 }}>
            <ChartHead title="CPU" sub={t("metrics.usage")} stat={cur ? `${Math.round(cur.cpu?.usagePercent ?? 0)}%` : undefined} peak={`${Math.round(cpuMax)}%`} />
            <LineChart height={200} yMax={100} unit="%" xLabels={xLabels} series={[{ data: series.cpu, label: "CPU", color: "var(--fg)", fill: true, fillOpacity: 0.08 }]} thresholds={[{ v: 90, label: "90%", color: "var(--crit)" }]} />
          </div>

          <div className="card" style={{ padding: 16 }}>
            <ChartHead title={t("metrics.memory")} sub={t("metrics.usage")} stat={cur && cur.memory?.total ? `${Math.round((cur.memory.used / cur.memory.total) * 100)}%` : undefined} peak={`${Math.round(memMax)}%`} />
            <LineChart height={200} yMax={100} unit="%" xLabels={xLabels} series={[{ data: series.mem, label: "Mem", color: "var(--fg-2)", fill: true, fillOpacity: 0.05 }]} thresholds={[{ v: 90, label: "90%", color: "var(--crit)" }]} />
          </div>

          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
            <div className="card" style={{ padding: 16 }}>
              <ChartHead title={t("metrics.network")} sub="RX / TX" />
              <LineChart height={160} unit=" MB/s" xLabels={xLabels} series={[{ data: series.netRx, label: "RX", color: "var(--fg)", fill: true, fillOpacity: 0.06 }, { data: series.netTx, label: "TX", color: "var(--info)", dashed: true, strokeWidth: 1.25 }]} />
            </div>
            <div className="card" style={{ padding: 16 }}>
              <ChartHead title={t("metrics.diskIO")} sub="Read / Write" />
              <LineChart height={160} unit=" MB/s" xLabels={xLabels} series={[{ data: series.diskR, label: "Read", color: "var(--fg)", fill: true, fillOpacity: 0.06 }, { data: series.diskW, label: "Write", color: "var(--warn)", dashed: true, strokeWidth: 1.25 }]} />
            </div>
          </div>

          {series.gpuUse && series.gpuTemp && (
            <div className="card" style={{ padding: 16 }}>
              <ChartHead title="GPU" sub={`${t("mon.util")} + ${t("metrics.temperature")}`} />
              <LineChart height={180} yMax={100} unit="%" xLabels={xLabels} series={[{ data: series.gpuUse, label: "GPU util", color: "var(--fg)", fill: true, fillOpacity: 0.06 }, { data: series.gpuTemp, label: "Temp °C", color: "var(--crit)", dashed: true, strokeWidth: 1.25 }]} thresholds={[{ v: 90, label: "90%", color: "var(--crit)" }]} />
            </div>
          )}
        </>
      )}
    </div>
  )
}
