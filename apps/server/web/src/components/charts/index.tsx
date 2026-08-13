// charts/index.tsx — interactive SVG chart primitives (ported from design/nanolink/charts.jsx).
// All charts consume CSS variables for color and work with simple number arrays.
import { useEffect, useMemo, useRef, useState } from "react"

type TooltipPlacement = "inside" | "above" | "cursor"

interface TooltipRow {
  label?: string
  value: string
  color?: string
}

function formatChartNumber(value: number | undefined) {
  if (value === undefined || !Number.isFinite(value)) return "—"
  const abs = Math.abs(value)
  return value.toLocaleString(undefined, {
    maximumFractionDigits: Number.isInteger(value) ? 0 : abs < 1 ? 4 : 2,
  })
}

function formatChartValue(value: number | undefined, unit = "") {
  return `${formatChartNumber(value)}${value !== undefined && Number.isFinite(value) ? unit : ""}`
}

function formatGaugeValue(value: number, max: number, unit: string) {
  if (max === 100 && unit === "%") return formatChartValue(value, unit)
  const pct = max > 0 ? (value / max) * 100 : 0
  return `${formatChartValue(value, unit)} / ${formatChartValue(max, unit)} · ${formatChartValue(pct, "%")}`
}

function pointTitle(labels: string[] | undefined, index: number, count: number) {
  return labels?.[index] || `#${index + 1} / ${count}`
}

function ChartTooltip({
  x,
  y,
  title,
  rows,
  compact = false,
  placement = "inside",
}: {
  x: number
  y?: number
  title?: string
  rows: TooltipRow[]
  compact?: boolean
  placement?: TooltipPlacement
}) {
  const align = x < 28 ? "start" : x > 72 ? "end" : "center"
  return (
    <div
      className={`chart-tooltip chart-tooltip--${placement} chart-tooltip--align-${align}${compact ? " chart-tooltip--compact" : ""}`}
      style={{ left: `${Math.max(0, Math.min(100, x))}%`, ...(y === undefined ? {} : { top: `${Math.max(0, Math.min(100, y))}%` }) }}
      role="tooltip"
    >
      {title && <div className="chart-tooltip__title mono">{title}</div>}
      {rows.map((row, index) => (
        <div className="chart-tooltip__row" key={`${row.label ?? "value"}-${index}`}>
          {row.color && <span className="chart-tooltip__swatch" style={{ background: row.color }} />}
          {row.label && <span className="chart-tooltip__label">{row.label}</span>}
          <span className="chart-tooltip__value mono num">{row.value}</span>
        </div>
      ))}
    </div>
  )
}

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
  label,
  unit = "",
  pointLabels,
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
  label?: string
  unit?: string
  pointLabels?: string[]
}) {
  const wrap = useRef<HTMLDivElement>(null)
  const [activeIndex, setActiveIndex] = useState<number | null>(null)
  if (!data?.length) return <svg width={w} height={h} aria-hidden="true" />

  // Coerce non-finite values so a missing metric never yields a NaN path coordinate.
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

  const active = activeIndex === null ? null : Math.min(activeIndex, clean.length - 1)
  const activeX = active === null ? 0 : active * step
  const activeY = active === null ? 0 : h - ((clean[active] - lo) / range) * (h - 2) - 1
  const accessibleLabel = active === null
    ? `${label ? `${label}: ` : ""}${formatChartValue(data[data.length - 1], unit)}`
    : `${pointTitle(pointLabels, active, clean.length)}, ${label ? `${label}: ` : ""}${formatChartValue(data[active], unit)}`
  const setIndexFromPointer = (clientX: number, rect: DOMRect) => {
    const ratio = rect.width ? (clientX - rect.left) / rect.width : 0
    setActiveIndex(Math.round(Math.max(0, Math.min(1, ratio)) * (clean.length - 1)))
  }

  return (
    <div
      ref={wrap}
      className="chart-interactive chart-sparkline"
      tabIndex={0}
      role="img"
      aria-label={accessibleLabel}
      onFocus={() => setActiveIndex((current) => current ?? clean.length - 1)}
      onBlur={() => setActiveIndex(null)}
      onPointerLeave={() => setActiveIndex(null)}
      onKeyDown={(event) => {
        if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
          event.preventDefault()
          const delta = event.key === "ArrowLeft" ? -1 : 1
          setActiveIndex((current) => Math.max(0, Math.min(clean.length - 1, (current ?? clean.length - 1) + delta)))
        } else if (event.key === "Home" || event.key === "End") {
          event.preventDefault()
          setActiveIndex(event.key === "Home" ? 0 : clean.length - 1)
        }
      }}
    >
      <svg
        width={w}
        height={h}
        viewBox={`0 0 ${w} ${h}`}
        style={{ display: "block", width: "100%", cursor: "crosshair", touchAction: "pan-y" }}
        preserveAspectRatio="none"
        aria-hidden="true"
        onPointerMove={(event) => setIndexFromPointer(event.clientX, event.currentTarget.getBoundingClientRect())}
        onPointerDown={(event) => {
          wrap.current?.focus()
          setIndexFromPointer(event.clientX, event.currentTarget.getBoundingClientRect())
        }}
      >
        <rect width={w} height={h} fill="transparent" pointerEvents="all" />
        <path d={area} fill={fill} opacity={fillOpacity} pointerEvents="none" />
        <path d={d} fill="none" stroke={stroke} strokeWidth={strokeWidth} strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" pointerEvents="none" />
        {active !== null && (
          <g pointerEvents="none">
            <line x1={activeX} x2={activeX} y1={0} y2={h} stroke="var(--chart-axis)" strokeWidth={1} strokeDasharray="2 2" vectorEffect="non-scaling-stroke" />
            <circle cx={activeX} cy={activeY} r={2.5} fill={stroke} stroke="var(--panel)" strokeWidth={1.5} vectorEffect="non-scaling-stroke" />
          </g>
        )}
      </svg>
      {active !== null && (
        <ChartTooltip
          x={(activeX / w) * 100}
          title={pointTitle(pointLabels, active, clean.length)}
          rows={[{ label, value: formatChartValue(data[active], unit), color: stroke }]}
          compact
          placement="above"
        />
      )}
    </div>
  )
}

// ─── Time-series line chart ────────────────────────────────
export interface ChartSeries {
  data: number[]
  label: string
  color: string
  unit?: string
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
  pointLabels,
  ariaLabel,
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
  pointLabels?: string[]
  ariaLabel?: string
}) {
  const wrap = useRef<HTMLDivElement>(null)
  const [w, setW] = useState(600)
  const [activeIndex, setActiveIndex] = useState<number | null>(null)
  useEffect(() => {
    if (!wrap.current) return
    const ro = new ResizeObserver((entries) => setW(entries[0].contentRect.width))
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

  const innerW = Math.max(w - padL - padR, 1)
  const innerH = Math.max(height - padT - padB, 1)
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
    let path = ""
    data.forEach((v, i) => {
      path += (i === 0 ? "M" : "L") + xFor(i).toFixed(1) + "," + safeY(v).toFixed(1)
    })
    return path
  }
  function fillFor(data: number[]) {
    if (!data?.length) return ""
    let path = `M${xFor(0)},${yFor(ymin)}`
    data.forEach((v, i) => {
      path += `L${xFor(i).toFixed(1)},${safeY(v).toFixed(1)}`
    })
    path += `L${xFor(data.length - 1)},${yFor(ymin)} Z`
    return path
  }

  const xTickPos = xLabels.map((_, index) => (xLabels.length > 1 ? index / (xLabels.length - 1) : 0))
  const active = activeIndex === null ? null : Math.min(activeIndex, len - 1)
  const activeX = active === null ? 0 : xFor(active)
  const accessibleLabel = active === null
    ? ariaLabel || series.map((item) => item.label).join(" / ")
    : `${pointTitle(pointLabels, active, len)}, ${series.map((item) => `${item.label}: ${formatChartValue(item.data[active], item.unit ?? unit)}`).join(", ")}`
  const setIndexFromPointer = (clientX: number, rect: DOMRect) => {
    const svgX = rect.width ? ((clientX - rect.left) / rect.width) * w : padL
    const ratio = (svgX - padL) / innerW
    setActiveIndex(Math.round(Math.max(0, Math.min(1, ratio)) * (len - 1)))
  }

  return (
    <div
      ref={wrap}
      className="chart-interactive chart-line"
      style={{ width: "100%" }}
      tabIndex={0}
      role="img"
      aria-label={accessibleLabel}
      onFocus={() => setActiveIndex((current) => current ?? len - 1)}
      onBlur={() => setActiveIndex(null)}
      onPointerLeave={() => setActiveIndex(null)}
      onKeyDown={(event) => {
        if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
          event.preventDefault()
          const delta = event.key === "ArrowLeft" ? -1 : 1
          setActiveIndex((current) => Math.max(0, Math.min(len - 1, (current ?? len - 1) + delta)))
        } else if (event.key === "Home" || event.key === "End") {
          event.preventDefault()
          setActiveIndex(event.key === "Home" ? 0 : len - 1)
        }
      }}
    >
      <svg
        width={w}
        height={height}
        style={{ display: "block", overflow: "visible", cursor: "crosshair", touchAction: "pan-y" }}
        aria-hidden="true"
        onPointerMove={(event) => setIndexFromPointer(event.clientX, event.currentTarget.getBoundingClientRect())}
        onPointerDown={(event) => {
          wrap.current?.focus()
          setIndexFromPointer(event.clientX, event.currentTarget.getBoundingClientRect())
        }}
      >
        {grid &&
          yTicks.map((tick, i) => (
            <line
              key={i}
              x1={padL}
              x2={w - padR}
              y1={yFor(tick)}
              y2={yFor(tick)}
              stroke="var(--chart-grid)"
              strokeWidth={1}
              strokeDasharray={i === 0 || i === yTicks.length - 1 ? "" : "2 3"}
            />
          ))}
        {showAxis &&
          yTicks.map((tick, i) => (
            <text key={`y${i}`} x={padL - 6} y={yFor(tick) + 3.5} fill="var(--fg-4)" fontSize="10" textAnchor="end" fontFamily="var(--font-mono)">
              {Math.round(tick)}
              {unit}
            </text>
          ))}
        {thresholds.map((threshold, i) => (
          <g key={`th${i}`}>
            <line x1={padL} x2={w - padR} y1={yFor(threshold.v)} y2={yFor(threshold.v)} stroke={threshold.color || "var(--crit)"} strokeWidth={1} strokeDasharray="3 3" opacity={0.7} />
            {threshold.label && (
              <text x={w - padR - 4} y={yFor(threshold.v) - 4} fontSize="9.5" fill={threshold.color || "var(--crit)"} textAnchor="end" fontFamily="var(--font-mono)">
                {threshold.label}
              </text>
            )}
          </g>
        ))}
        {series.map((item, i) => (
          <g key={`${item.label}-${i}`}>
            {item.fill && <path d={fillFor(item.data)} fill={item.color} opacity={item.fillOpacity ?? 0.1} />}
            <path
              d={pathFor(item.data)}
              fill="none"
              stroke={item.color}
              strokeWidth={item.strokeWidth ?? 1.5}
              strokeDasharray={item.dashed ? "4 3" : ""}
              strokeLinejoin="round"
              strokeLinecap="round"
            />
          </g>
        ))}
        {showAxis &&
          xTickPos.map((position, i) => (
            <text
              key={`x${i}`}
              x={padL + position * innerW}
              y={height - 4}
              fill="var(--fg-4)"
              fontSize="10"
              textAnchor={i === 0 ? "start" : i === xTickPos.length - 1 ? "end" : "middle"}
              fontFamily="var(--font-mono)"
            >
              {xLabels[i]}
            </text>
          ))}
        <rect x={padL} y={padT} width={innerW} height={innerH} fill="transparent" pointerEvents="all" />
        {active !== null && (
          <g pointerEvents="none">
            <line x1={activeX} x2={activeX} y1={padT} y2={padT + innerH} stroke="var(--chart-axis)" strokeWidth={1} strokeDasharray="3 3" />
            {series.map((item, index) => {
              const value = item.data[active]
              return Number.isFinite(value) ? (
                <circle key={`${item.label}-${index}`} cx={activeX} cy={safeY(value)} r={3.25} fill={item.color} stroke="var(--panel)" strokeWidth={1.5} />
              ) : null
            })}
          </g>
        )}
      </svg>
      {active !== null && (
        <ChartTooltip
          x={(activeX / Math.max(w, 1)) * 100}
          title={pointTitle(pointLabels, active, len)}
          rows={series.map((item) => ({ label: item.label, value: formatChartValue(item.data[active], item.unit ?? unit), color: item.color }))}
          placement="inside"
        />
      )}
      {showLegend && series.length > 1 && (
        <div className="row gap-3" style={{ paddingLeft: padL, marginTop: 2, fontSize: 11 }}>
          {series.map((item, i) => (
            <div key={`${item.label}-${i}`} className="row gap-2 muted" style={{ alignItems: "center" }}>
              <span style={{ width: 10, height: 2, background: item.color, display: "inline-block", borderRadius: 2 }} />
              <span>{item.label}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ─── Dot / Bar matrix ──────────────────────────────────────
export function DotBar({ value, max = 100, count = 24, label, unit = "" }: { value: number; max?: number; count?: number; label?: string; unit?: string }) {
  const [active, setActive] = useState(false)
  const pct = Math.max(0, Math.min(1, max > 0 ? value / max : 0))
  const filled = Math.round(pct * count)
  const tone = pct > 0.9 ? "var(--crit)" : pct > 0.75 ? "var(--warn)" : "var(--fg-2)"
  return (
    <div
      className="chart-interactive chart-inline"
      tabIndex={0}
      role="img"
      aria-label={`${label ? `${label}: ` : ""}${formatGaugeValue(value, max, unit)}`}
      onPointerEnter={() => setActive(true)}
      onPointerLeave={() => setActive(false)}
      onPointerDown={(event) => event.currentTarget.focus()}
      onFocus={() => setActive(true)}
      onBlur={() => setActive(false)}
    >
      <div className="row gap-1" style={{ alignItems: "flex-end", height: 12 }}>
        {Array.from({ length: count }).map((_, i) => {
          const on = i < filled
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
      {active && <ChartTooltip x={50} title={label} rows={[{ value: formatGaugeValue(value, max, unit), color: tone }]} compact placement="above" />}
    </div>
  )
}

// ─── Per-core matrix ───────────────────────────────────────
export function CoreMatrix({ cores, label = "Core", unit = "%" }: { cores: number[]; label?: string; unit?: string }) {
  const cols = Math.min(16, Math.max(1, Math.ceil(Math.sqrt(cores.length * 2))))
  const rows = Math.max(1, Math.ceil(cores.length / cols))
  const [activeIndex, setActiveIndex] = useState<number | null>(null)
  const active = activeIndex === null || !cores.length ? null : Math.min(activeIndex, cores.length - 1)
  const activeValue = active === null ? undefined : cores[active]
  const activeX = active === null ? 0 : ((active % cols + 0.5) / cols) * 100
  const activeY = active === null ? 0 : ((Math.floor(active / cols) + 0.5) / rows) * 100

  return (
    <div
      className="chart-interactive chart-core-matrix"
      tabIndex={0}
      role="img"
      aria-label={active === null ? `${label}: ${cores.length}` : `${label} ${active + 1}: ${formatChartValue(activeValue, unit)}`}
      onFocus={() => setActiveIndex((current) => current ?? 0)}
      onBlur={() => setActiveIndex(null)}
      onPointerLeave={() => setActiveIndex(null)}
      onKeyDown={(event) => {
        if (!cores.length) return
        let next = active ?? 0
        if (event.key === "ArrowLeft") next -= 1
        else if (event.key === "ArrowRight") next += 1
        else if (event.key === "ArrowUp") next -= cols
        else if (event.key === "ArrowDown") next += cols
        else if (event.key === "Home") next = 0
        else if (event.key === "End") next = cores.length - 1
        else return
        event.preventDefault()
        setActiveIndex(Math.max(0, Math.min(cores.length - 1, next)))
      }}
    >
      <div style={{ display: "grid", gridTemplateColumns: `repeat(${cols}, 1fr)`, gap: 3 }}>
        {cores.map((raw, i) => {
          const value = Number.isFinite(raw) ? raw : 0
          const tone = value > 90 ? "var(--crit)" : value > 70 ? "var(--warn)" : value > 30 ? "var(--fg-2)" : "var(--fg-dim)"
          return (
            <div
              key={i}
              role="presentation"
              onPointerEnter={() => setActiveIndex(i)}
              onPointerDown={(event) => {
                event.currentTarget.parentElement?.parentElement?.focus()
                setActiveIndex(i)
              }}
              style={{
                height: 18,
                background: "var(--panel-3)",
                position: "relative",
                borderRadius: 2,
                overflow: "hidden",
                boxShadow: active === i ? `0 0 0 1px ${tone}` : undefined,
              }}
            >
              <div style={{ position: "absolute", left: 0, bottom: 0, right: 0, height: `${Math.max(0, Math.min(100, value))}%`, background: tone, opacity: 0.85 }} />
            </div>
          )
        })}
      </div>
      {active !== null && (
        <ChartTooltip
          x={activeX}
          y={activeY}
          title={`${label} ${active + 1}`}
          rows={[{ value: formatChartValue(activeValue, unit), color: activeValue !== undefined && activeValue > 90 ? "var(--crit)" : activeValue !== undefined && activeValue > 70 ? "var(--warn)" : "var(--fg-2)" }]}
          compact
          placement="cursor"
        />
      )}
    </div>
  )
}

// ─── Donut ─────────────────────────────────────────────────
export function Donut({
  value,
  max = 100,
  size = 80,
  thickness = 6,
  label,
  sub,
  name,
  unit = "%",
}: {
  value: number
  max?: number
  size?: number
  thickness?: number
  label: string
  sub?: string
  name?: string
  unit?: string
}) {
  const [active, setActive] = useState(false)
  const r = size / 2 - thickness
  const c = 2 * Math.PI * r
  const pct = Math.max(0, Math.min(1, max > 0 ? value / max : 0))
  const tone = pct > 0.9 ? "var(--crit)" : pct > 0.75 ? "var(--warn)" : "var(--fg)"
  return (
    <div
      className="chart-interactive chart-donut"
      style={{ width: size, height: size }}
      tabIndex={0}
      role="img"
      aria-label={`${name ? `${name}: ` : ""}${formatGaugeValue(value, max, unit)}`}
      onPointerEnter={() => setActive(true)}
      onPointerLeave={() => setActive(false)}
      onPointerDown={(event) => event.currentTarget.focus()}
      onFocus={() => setActive(true)}
      onBlur={() => setActive(false)}
    >
      <svg width={size} height={size} aria-hidden="true">
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
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", pointerEvents: "none" }}>
        <div className="num" style={{ fontWeight: 600, fontSize: size > 80 ? 22 : 16, color: "var(--fg)" }}>
          {label}
        </div>
        {sub && (
          <div className="num" style={{ fontSize: 10, color: "var(--fg-4)" }}>
            {sub}
          </div>
        )}
      </div>
      {active && <ChartTooltip x={50} title={name} rows={[{ value: formatGaugeValue(value, max, unit), color: tone }]} compact placement="above" />}
    </div>
  )
}
