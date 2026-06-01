// charts/index.tsx — minimal SVG chart primitives (ported from design/nanolink/charts.jsx).
// All charts consume CSS variables for color and work with simple number arrays.
import { useMemo, useRef, useEffect, useState } from "react"

// ─── Sparkline ─────────────────────────────────────────────
export function Sparkline({
  data,
  w = 100,
  h = 24,
  stroke = "currentColor",
  fill = "currentColor",
  fillOpacity = 0.12,
  strokeWidth = 1.25,
  max,
  min,
}: {
  data: number[]
  w?: number
  h?: number
  stroke?: string
  fill?: string
  fillOpacity?: number
  strokeWidth?: number
  max?: number
  min?: number
}) {
  if (!data?.length) return <svg width={w} height={h} />
  // Coerce non-finite values (undefined/NaN) so a missing metric never yields a
  // NaN path coordinate.
  const clean = data.map((v) => (Number.isFinite(v) ? v : 0))
  const lo = min ?? Math.min(...clean)
  const hi = max ?? Math.max(...clean)
  const range = hi - lo || 1
  const step = w / (clean.length - 1 || 1)
  let d = ""
  let area = ""
  clean.forEach((v, i) => {
    const x = i * step
    const y = h - ((v - lo) / range) * (h - 2) - 1
    d += (i === 0 ? "M" : "L") + x.toFixed(1) + "," + y.toFixed(1)
    area += (i === 0 ? "M" : "L") + x.toFixed(1) + "," + y.toFixed(1)
  })
  area += `L${w},${h} L0,${h} Z`
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} style={{ display: "block", width: "100%" }} preserveAspectRatio="none">
      <path d={area} fill={fill} opacity={fillOpacity} />
      <path d={d} fill="none" stroke={stroke} strokeWidth={strokeWidth} strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  )
}

// ─── Time-series line chart ────────────────────────────────
export interface ChartSeries {
  data: number[]
  label: string
  color: string
  dashed?: boolean
  fill?: boolean
  fillOpacity?: number
  strokeWidth?: number
}

export interface ChartThreshold {
  v: number
  label?: string
  color?: string
}

export function LineChart({
  series,
  height = 180,
  yMax,
  yMin = 0,
  unit = "%",
  thresholds = [],
  grid = true,
  showAxis = true,
  showLegend = true,
  xLabels = ["-60m", "-45m", "-30m", "-15m", "now"],
}: {
  series: ChartSeries[]
  height?: number
  yMax?: number
  yMin?: number
  unit?: string
  thresholds?: ChartThreshold[]
  grid?: boolean
  showAxis?: boolean
  showLegend?: boolean
  xLabels?: string[]
}) {
  const wrap = useRef<HTMLDivElement>(null)
  const [w, setW] = useState(600)
  useEffect(() => {
    if (!wrap.current) return
    const ro = new ResizeObserver((es) => setW(es[0].contentRect.width))
    ro.observe(wrap.current)
    return () => ro.disconnect()
  }, [])
  const padL = 36
  const padR = 8
  const padT = 8
  const padB = showAxis ? 22 : 4

  const allData = series.flatMap((s) => s.data || []).filter((v) => Number.isFinite(v))
  const dataMin = allData.length ? Math.min(...allData) : 0
  const dataMax = allData.length ? Math.max(...allData) : 1
  const ymax = yMax ?? Math.max(dataMax * 1.1, 1)
  const ymin = yMin ?? Math.min(dataMin, 0)
  const len = Math.max(...series.map((s) => s.data?.length || 0), 1)

  const innerW = w - padL - padR
  const innerH = height - padT - padB
  const xFor = (i: number) => padL + (i / (len - 1 || 1)) * innerW
  const yFor = (v: number) => padT + (1 - (v - ymin) / (ymax - ymin || 1)) * innerH

  const yTicks = useMemo(() => {
    const n = 4
    const out: number[] = []
    for (let i = 0; i <= n; i++) out.push(ymin + ((ymax - ymin) * i) / n)
    return out
  }, [ymin, ymax])

  const safeY = (v: number) => yFor(Number.isFinite(v) ? v : ymin)
  function pathFor(data: number[]) {
    if (!data?.length) return ""
    let d = ""
    data.forEach((v, i) => {
      d += (i === 0 ? "M" : "L") + xFor(i).toFixed(1) + "," + safeY(v).toFixed(1)
    })
    return d
  }
  function fillFor(data: number[]) {
    if (!data?.length) return ""
    let d = `M${xFor(0)},${yFor(ymin)}`
    data.forEach((v, i) => {
      d += `L${xFor(i).toFixed(1)},${safeY(v).toFixed(1)}`
    })
    d += `L${xFor(data.length - 1)},${yFor(ymin)} Z`
    return d
  }

  const xTickPos = [0, 0.25, 0.5, 0.75, 1]

  return (
    <div ref={wrap} style={{ width: "100%" }}>
      <svg width={w} height={height} style={{ display: "block", overflow: "visible" }}>
        {grid &&
          yTicks.map((t, i) => (
            <line
              key={i}
              x1={padL}
              x2={w - padR}
              y1={yFor(t)}
              y2={yFor(t)}
              stroke="var(--chart-grid)"
              strokeWidth={1}
              strokeDasharray={i === 0 || i === yTicks.length - 1 ? "" : "2 3"}
            />
          ))}
        {showAxis &&
          yTicks.map((t, i) => (
            <text key={"y" + i} x={padL - 6} y={yFor(t) + 3.5} fill="var(--fg-4)" fontSize="10" textAnchor="end" fontFamily="var(--font-mono)">
              {Math.round(t)}
              {unit}
            </text>
          ))}
        {thresholds.map((th, i) => (
          <g key={"th" + i}>
            <line x1={padL} x2={w - padR} y1={yFor(th.v)} y2={yFor(th.v)} stroke={th.color || "var(--crit)"} strokeWidth={1} strokeDasharray="3 3" opacity={0.7} />
            {th.label && (
              <text x={w - padR - 4} y={yFor(th.v) - 4} fontSize="9.5" fill={th.color || "var(--crit)"} textAnchor="end" fontFamily="var(--font-mono)">
                {th.label}
              </text>
            )}
          </g>
        ))}
        {series.map((s, i) => (
          <g key={i}>
            {s.fill && <path d={fillFor(s.data)} fill={s.color} opacity={s.fillOpacity ?? 0.1} />}
            <path
              d={pathFor(s.data)}
              fill="none"
              stroke={s.color}
              strokeWidth={s.strokeWidth ?? 1.5}
              strokeDasharray={s.dashed ? "4 3" : ""}
              strokeLinejoin="round"
              strokeLinecap="round"
            />
          </g>
        ))}
        {showAxis &&
          xTickPos.map((p, i) => (
            <text
              key={"x" + i}
              x={padL + p * innerW}
              y={height - 4}
              fill="var(--fg-4)"
              fontSize="10"
              textAnchor={i === 0 ? "start" : i === xTickPos.length - 1 ? "end" : "middle"}
              fontFamily="var(--font-mono)"
            >
              {xLabels[i]}
            </text>
          ))}
      </svg>
      {showLegend && series.length > 1 && (
        <div className="row gap-3" style={{ paddingLeft: padL, marginTop: 2, fontSize: 11 }}>
          {series.map((s, i) => (
            <div key={i} className="row gap-2 muted" style={{ alignItems: "center" }}>
              <span style={{ width: 10, height: 2, background: s.color, display: "inline-block", borderRadius: 2 }} />
              <span>{s.label}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ─── Dot / Bar matrix ──────────────────────────────────────
export function DotBar({ value, max = 100, count = 24 }: { value: number; max?: number; count?: number }) {
  const pct = Math.max(0, Math.min(1, value / max))
  const filled = Math.round(pct * count)
  return (
    <div className="row gap-1" style={{ alignItems: "flex-end", height: 12 }}>
      {Array.from({ length: count }).map((_, i) => {
        const on = i < filled
        const tone = pct > 0.9 ? "var(--crit)" : pct > 0.75 ? "var(--warn)" : "var(--fg-2)"
        return (
          <span
            key={i}
            style={{
              width: 3,
              height: on ? 4 + Math.abs(Math.sin(i * 0.7)) * 8 : 3,
              background: on ? tone : "var(--border)",
              borderRadius: 1,
              transition: "height 200ms ease, background 200ms ease",
            }}
          />
        )
      })}
    </div>
  )
}

// ─── Per-core matrix ───────────────────────────────────────
export function CoreMatrix({ cores }: { cores: number[] }) {
  const cols = Math.min(16, Math.ceil(Math.sqrt(cores.length * 2)))
  return (
    <div style={{ display: "grid", gridTemplateColumns: `repeat(${cols}, 1fr)`, gap: 3 }}>
      {cores.map((raw, i) => {
        const v = Number.isFinite(raw) ? raw : 0
        const tone = v > 90 ? "var(--crit)" : v > 70 ? "var(--warn)" : v > 30 ? "var(--fg-2)" : "var(--fg-dim)"
        return (
          <div key={i} title={`Core ${i}: ${v.toFixed(0)}%`} style={{ height: 18, background: "var(--panel-3)", position: "relative", borderRadius: 2, overflow: "hidden" }}>
            <div style={{ position: "absolute", left: 0, bottom: 0, right: 0, height: `${v}%`, background: tone, opacity: 0.85 }} />
          </div>
        )
      })}
    </div>
  )
}

// ─── Donut ─────────────────────────────────────────────────
export function Donut({ value, max = 100, size = 80, thickness = 6, label, sub }: { value: number; max?: number; size?: number; thickness?: number; label: string; sub?: string }) {
  const r = size / 2 - thickness
  const c = 2 * Math.PI * r
  const pct = Math.max(0, Math.min(1, value / max))
  const tone = pct > 0.9 ? "var(--crit)" : pct > 0.75 ? "var(--warn)" : "var(--fg)"
  return (
    <div style={{ position: "relative", width: size, height: size }}>
      <svg width={size} height={size}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--panel-3)" strokeWidth={thickness} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={tone}
          strokeWidth={thickness}
          strokeDasharray={`${c * pct} ${c}`}
          strokeLinecap="round"
          transform={`rotate(-90 ${size / 2} ${size / 2})`}
          style={{ transition: "stroke-dasharray 400ms ease" }}
        />
      </svg>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
        <div className="num" style={{ fontWeight: 600, fontSize: size > 80 ? 22 : 16, color: "var(--fg)" }}>
          {label}
        </div>
        {sub && (
          <div className="num" style={{ fontSize: 10, color: "var(--fg-4)" }}>
            {sub}
          </div>
        )}
      </div>
    </div>
  )
}
