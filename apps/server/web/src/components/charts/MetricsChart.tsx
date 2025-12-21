import { useMemo } from "react"
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
  Area,
  AreaChart,
} from "recharts"
import { useTheme } from "@/hooks/use-theme"

export interface ChartDataPoint {
  timestamp: string | number
  value: number
  value2?: number
}

export interface MetricsChartProps {
  data: ChartDataPoint[]
  title: string
  unit?: string
  color?: string
  color2?: string
  threshold?: number
  thresholdLabel?: string
  showArea?: boolean
  height?: number
  label?: string
  label2?: string
  yDomain?: [number, number]
}

const formatTime = (timestamp: string | number) => {
  const date = new Date(timestamp)
  return date.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", second: "2-digit" })
}

const formatValue = (value: number, unit?: string) => {
  if (unit === "bytes") {
    if (value >= 1024 * 1024 * 1024) return `${(value / (1024 * 1024 * 1024)).toFixed(1)} GB`
    if (value >= 1024 * 1024) return `${(value / (1024 * 1024)).toFixed(1)} MB`
    if (value >= 1024) return `${(value / 1024).toFixed(1)} KB`
    return `${value} B`
  }
  if (unit === "%") return `${value.toFixed(1)}%`
  if (unit === "MB/s") return `${value.toFixed(2)} MB/s`
  return value.toFixed(2)
}

export function MetricsChart({
  data,
  title,
  unit = "%",
  color = "#3b82f6",
  color2 = "#22c55e",
  threshold,
  thresholdLabel,
  showArea = false,
  height = 200,
  label = "Value",
  label2,
  yDomain,
}: MetricsChartProps) {
  const { resolvedTheme } = useTheme()
  const isDark = resolvedTheme === "dark"

  const chartData = useMemo(() => {
    return data.map((d) => ({
      ...d,
      time: formatTime(d.timestamp),
    }))
  }, [data])

  const gridColor = isDark ? "#27272a" : "#e4e4e7"
  const textColor = isDark ? "#a1a1aa" : "#71717a"
  const bgColor = isDark ? "#09090b" : "#ffffff"

  const CustomTooltip = ({ active, payload, label: tooltipLabel }: { active?: boolean; payload?: Array<{ value: number; dataKey: string; color: string }>; label?: string }) => {
    if (!active || !payload) return null
    return (
      <div
        className="rounded-lg border border-[var(--color-border)] p-2 shadow-lg"
        style={{ backgroundColor: bgColor }}
      >
        <p className="text-xs text-[var(--color-muted-foreground)] mb-1">{tooltipLabel}</p>
        {payload.map((entry, i) => (
          <p key={i} className="text-sm font-medium" style={{ color: entry.color }}>
            {entry.dataKey === "value" ? label : label2}: {formatValue(entry.value, unit)}
          </p>
        ))}
      </div>
    )
  }

  const ChartComponent = showArea ? AreaChart : LineChart

  return (
    <div className="rounded-lg border border-[var(--color-border)] bg-[var(--color-card)] p-4">
      <h4 className="text-sm font-medium mb-3">{title}</h4>
      <ResponsiveContainer width="100%" height={height}>
        <ChartComponent data={chartData} margin={{ top: 5, right: 10, left: 0, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke={gridColor} vertical={false} />
          <XAxis
            dataKey="time"
            tick={{ fontSize: 10, fill: textColor }}
            tickLine={false}
            axisLine={{ stroke: gridColor }}
            interval="preserveStartEnd"
          />
          <YAxis
            domain={yDomain || (unit === "%" ? [0, 100] : ["auto", "auto"])}
            tick={{ fontSize: 10, fill: textColor }}
            tickLine={false}
            axisLine={false}
            tickFormatter={(v) => formatValue(v, unit)}
            width={50}
          />
          <Tooltip content={<CustomTooltip />} />
          {threshold && (
            <ReferenceLine
              y={threshold}
              stroke="#ef4444"
              strokeDasharray="5 5"
              label={{ value: thresholdLabel || `${threshold}${unit}`, fill: "#ef4444", fontSize: 10 }}
            />
          )}
          {showArea ? (
            <>
              <Area
                type="monotone"
                dataKey="value"
                stroke={color}
                fill={color}
                fillOpacity={0.2}
                strokeWidth={2}
                dot={false}
                isAnimationActive={false}
              />
              {label2 && (
                <Area
                  type="monotone"
                  dataKey="value2"
                  stroke={color2}
                  fill={color2}
                  fillOpacity={0.2}
                  strokeWidth={2}
                  dot={false}
                  isAnimationActive={false}
                />
              )}
            </>
          ) : (
            <>
              <Line
                type="monotone"
                dataKey="value"
                stroke={color}
                strokeWidth={2}
                dot={false}
                isAnimationActive={false}
              />
              {label2 && (
                <Line
                  type="monotone"
                  dataKey="value2"
                  stroke={color2}
                  strokeWidth={2}
                  dot={false}
                  isAnimationActive={false}
                />
              )}
            </>
          )}
        </ChartComponent>
      </ResponsiveContainer>
    </div>
  )
}

// Mini sparkline for agent cards
export interface SparklineProps {
  data: number[]
  color?: string
  height?: number
  width?: number
}

export function Sparkline({ data, color = "#3b82f6", height = 24, width = 80 }: SparklineProps) {
  const chartData = data.map((value, index) => ({ value, index }))

  return (
    <ResponsiveContainer width={width} height={height}>
      <LineChart data={chartData} margin={{ top: 2, right: 2, left: 2, bottom: 2 }}>
        <Line
          type="monotone"
          dataKey="value"
          stroke={color}
          strokeWidth={1.5}
          dot={false}
          isAnimationActive={false}
        />
      </LineChart>
    </ResponsiveContainer>
  )
}
