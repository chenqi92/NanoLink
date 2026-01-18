import { useState, useEffect, useCallback, useMemo, useRef } from "react"
import { useTranslation } from "react-i18next"
import { ArrowLeft, RefreshCw, Calendar, AlertTriangle, Wifi, WifiOff } from "lucide-react"
import { Button } from "@/components/ui/button"
import { MetricsChart, type ChartDataPoint } from "./MetricsChart"
import { api, type Metrics } from "@/lib/api"
import { useData } from "@/contexts/DataContext"

interface AgentMetricsViewProps {
  agentId: string
  agentName: string
  onBack: () => void
}

type TimeRange = "5m" | "10m" | "30m" | "1h" | "6h" | "1d" | "7d" | "30d" | "custom"

// Map time range to milliseconds for API query
const timeRangeToMs: Record<Exclude<TimeRange, "custom">, number> = {
  "5m": 5 * 60 * 1000,
  "10m": 10 * 60 * 1000,
  "30m": 30 * 60 * 1000,
  "1h": 60 * 60 * 1000,
  "6h": 6 * 60 * 60 * 1000,
  "1d": 24 * 60 * 60 * 1000,
  "7d": 7 * 24 * 60 * 60 * 1000,
  "30d": 30 * 24 * 60 * 60 * 1000,
}

// Map time range to aggregation interval
const timeRangeToInterval: Record<Exclude<TimeRange, "custom">, string> = {
  "5m": "auto",
  "10m": "auto",
  "30m": "1m",
  "1h": "1m",
  "6h": "5m",
  "1d": "15m",
  "7d": "1h",
  "30d": "1h",
}

// Max history points to keep in memory for real-time mode
const MAX_REALTIME_HISTORY = 300

export function AgentMetricsView({ agentId, agentName, onBack }: AgentMetricsViewProps) {
  const { t } = useTranslation()
  const { metrics: wsMetrics, wsStatus } = useData()
  
  const [history, setHistory] = useState<Metrics[]>([])
  const [loading, setLoading] = useState(true)
  const [timeRange, setTimeRange] = useState<TimeRange>("10m")
  const [autoRefresh, setAutoRefresh] = useState(true)
  const [showCustomRange, setShowCustomRange] = useState(false)
  const [customStart, setCustomStart] = useState("")
  const [customEnd, setCustomEnd] = useState("")
  
  // Track if we're in real-time mode (using WebSocket data)
  // Real-time mode: autoRefresh enabled and not custom range
  const isRealtimeMode = autoRefresh && timeRange !== "custom"
  
  // Ref to track last processed metrics timestamp to avoid duplicates
  const lastMetricsTimestamp = useRef<string | null>(null)
  
  // Ref to track if initial history has been loaded


  // Handle real-time WebSocket metrics updates - append to existing history
  useEffect(() => {
    if (!isRealtimeMode) return
    
    const currentMetrics = wsMetrics[agentId]
    if (!currentMetrics) {
      return
    }
    
    // Generate unique key from timestamp or CPU usage change
    let metricsKey: string
    if (typeof currentMetrics.timestamp === 'string' && currentMetrics.timestamp) {
      metricsKey = currentMetrics.timestamp
    } else {
      // Use a combination of values that change frequently as key
      const cpuUsage = currentMetrics.cpu?.usagePercent ?? 0
      const memUsage = currentMetrics.memory?.used ?? 0
      metricsKey = `${cpuUsage.toFixed(2)}-${memUsage}`
    }
    
    // Check if this is a new metrics update
    if (lastMetricsTimestamp.current === metricsKey) {
      return
    }
    
    lastMetricsTimestamp.current = metricsKey
    
    // Append new metrics to history and trim old data based on time window
    setHistory(prev => {
      const newHistory = [...prev, currentMetrics]
      
      // Calculate time window based on selected time range
      const windowMs = timeRangeToMs[timeRange as Exclude<TimeRange, "custom">] ?? 10 * 60 * 1000
      const cutoffTime = Date.now() - windowMs
      
      // Filter out entries older than the time window
      const filteredHistory = newHistory.filter(m => {
        const timestamp = typeof m.timestamp === 'string' 
          ? new Date(m.timestamp).getTime() 
          : m.timestamp
        return timestamp >= cutoffTime
      })
      
      // Also limit to MAX_REALTIME_HISTORY as a safety cap
      if (filteredHistory.length > MAX_REALTIME_HISTORY) {
        return filteredHistory.slice(-MAX_REALTIME_HISTORY)
      }
      return filteredHistory
    })
    setLoading(false)
  }, [wsMetrics, agentId, isRealtimeMode, timeRange])

  // Fetch historical data from database
  const fetchHistory = useCallback(async () => {
    try {
      setLoading(true)
      let start: number
      let end: number
      let interval: string

      if (timeRange === "custom" && customStart && customEnd) {
        start = new Date(customStart).getTime()
        end = new Date(customEnd).getTime()
        const rangeMs = end - start
        if (rangeMs <= 60 * 60 * 1000) interval = "1m"
        else if (rangeMs <= 24 * 60 * 60 * 1000) interval = "15m"
        else interval = "1h"
      } else if (timeRange !== "custom") {
        const now = Date.now()
        const rangeMs = timeRangeToMs[timeRange]
        start = now - rangeMs
        end = now
        interval = timeRangeToInterval[timeRange]
      } else {
        return
      }
      
      const response = await api.get<Metrics[]>(
        `/metrics/history?agentId=${agentId}&start=${start}&end=${end}&interval=${interval}`
      )
      setHistory(response)
    } catch (e) {
      console.error("Failed to fetch metrics history:", e)
    } finally {
      setLoading(false)
    }
  }, [agentId, timeRange, customStart, customEnd])

  // Fetch historical data when time range changes or on mount
  // In real-time mode, we first load history then append new data
  // In history mode, we just show the history data
  useEffect(() => {
    // Always load historical data first for the selected time range
    fetchHistory()
    // Reset the last timestamp to allow new data to be added
    lastMetricsTimestamp.current = null
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [timeRange, agentId, customStart, customEnd])

  // Transform data for charts
  const cpuData: ChartDataPoint[] = useMemo(() => {
    return history.map((m) => ({
      timestamp: m.timestamp,
      value: m.cpu?.usagePercent || 0,
    }))
  }, [history])

  const memoryData: ChartDataPoint[] = useMemo(() => {
    if (!history.length) return []
    return history.map((m) => {
      const total = m.memory?.total || 1
      const used = m.memory?.used || 0
      return {
        timestamp: m.timestamp,
        value: (used / total) * 100,
      }
    })
  }, [history])

  const networkData: ChartDataPoint[] = useMemo(() => {
    return history.map((m) => {
      const totalRx = m.networks?.reduce((sum, n) => sum + (n.rxBytesPerSec || 0), 0) || 0
      const totalTx = m.networks?.reduce((sum, n) => sum + (n.txBytesPerSec || 0), 0) || 0
      return {
        timestamp: m.timestamp,
        value: totalRx, // Raw bytes, will be formatted by chart
        value2: totalTx,
      }
    })
  }, [history])

  const diskData: ChartDataPoint[] = useMemo(() => {
    return history.map((m) => {
      const totalRead = m.disks?.reduce((sum, d) => sum + (d.readBytesPerSec || 0), 0) || 0
      const totalWrite = m.disks?.reduce((sum, d) => sum + (d.writeBytesPerSec || 0), 0) || 0
      return {
        timestamp: m.timestamp,
        value: totalRead, // Raw bytes, will be formatted by chart
        value2: totalWrite,
      }
    })
  }, [history])

  // GPU usage data - aggregate all GPUs or show first GPU
  const gpuData: ChartDataPoint[] = useMemo(() => {
    // Check if any metrics have GPU data
    const hasGpu = history.some((m) => m.gpus && m.gpus.length > 0)
    if (!hasGpu) return []
    
    return history.map((m) => {
      if (!m.gpus || m.gpus.length === 0) {
        return { timestamp: m.timestamp, value: 0 }
      }
      // Use average GPU usage if multiple GPUs
      const avgUsage = m.gpus.reduce((sum, g) => sum + (g.usagePercent || 0), 0) / m.gpus.length
      const avgTemp = m.gpus.reduce((sum, g) => sum + (g.temperature || 0), 0) / m.gpus.length
      return {
        timestamp: m.timestamp,
        value: avgUsage,
        value2: avgTemp, // Temperature as secondary value
      }
    })
  }, [history])

  // Get GPU name for chart title
  const gpuName = useMemo(() => {
    const latestWithGpu = [...history].reverse().find((m) => m.gpus && m.gpus.length > 0)
    if (latestWithGpu?.gpus?.[0]?.name) {
      return latestWithGpu.gpus[0].name
    }
    return null
  }, [history])

  // Detect anomalies (CPU > 90% or Memory > 90%)
  const anomalies = useMemo(() => {
    const issues: string[] = []
    const recentCpu = cpuData.slice(-30)
    const highCpuCount = recentCpu.filter((d) => d.value > 90).length
    if (highCpuCount > 5) {
      issues.push(`CPU consistently high (${highCpuCount}/30 samples > 90%)`)
    }
    const recentMem = memoryData.slice(-30)
    const highMemCount = recentMem.filter((d) => d.value > 90).length
    if (highMemCount > 5) {
      issues.push(`Memory consistently high (${highMemCount}/30 samples > 90%)`)
    }
    return issues
  }, [cpuData, memoryData])

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={onBack}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h2 className="text-xl font-semibold">{agentName}</h2>
            <p className="text-sm text-[var(--color-muted-foreground)] flex items-center gap-2">
              {isRealtimeMode ? (
                <>
                  {wsStatus === 'connected' ? (
                    <Wifi className="h-3 w-3 text-green-500" />
                  ) : (
                    <WifiOff className="h-3 w-3 text-red-500" />
                  )}
                  <span>{t("metrics.realtime") || "实时"} - {history.length} {t("metrics.dataPoints") || "数据点"}</span>
                </>
              ) : (
                <span>{t("metrics.historicalData")} - {history.length} {t("metrics.dataPoints") || "数据点"}</span>
              )}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {/* Time Range Selector - Short ranges */}
          <div className="flex items-center gap-1 rounded-lg border border-[var(--color-border)] p-1">
            {(["5m", "10m", "30m", "1h", "6h"] as TimeRange[]).map((range) => (
              <button
                key={range}
                onClick={() => {
                  setTimeRange(range)
                  setShowCustomRange(false)
                }}
                className={`px-2 py-1 text-xs sm:text-sm rounded transition-colors ${
                  timeRange === range && !showCustomRange
                    ? "bg-[var(--color-primary)] text-[var(--color-primary-foreground)]"
                    : "hover:bg-[var(--color-accent)]"
                }`}
              >
                {range}
              </button>
            ))}
          </div>
          {/* Long ranges */}
          <div className="flex items-center gap-1 rounded-lg border border-[var(--color-border)] p-1">
            {(["1d", "7d", "30d"] as TimeRange[]).map((range) => (
              <button
                key={range}
                onClick={() => {
                  setTimeRange(range)
                  setShowCustomRange(false)
                  setAutoRefresh(false) // Disable auto-refresh for long ranges
                }}
                className={`px-2 py-1 text-xs sm:text-sm rounded transition-colors ${
                  timeRange === range && !showCustomRange
                    ? "bg-[var(--color-primary)] text-[var(--color-primary-foreground)]"
                    : "hover:bg-[var(--color-accent)]"
                }`}
              >
                {range}
              </button>
            ))}
          </div>
          {/* Custom Date Range */}
          <Button
            variant={showCustomRange ? "default" : "outline"}
            size="sm"
            onClick={() => setShowCustomRange(!showCustomRange)}
            className="gap-1"
          >
            <Calendar className="h-4 w-4" />
            <span className="hidden sm:inline">{t("metrics.custom") || "自定义"}</span>
          </Button>
          {/* Auto Refresh Toggle */}
          <Button
            variant={autoRefresh ? "default" : "outline"}
            size="sm"
            onClick={() => setAutoRefresh(!autoRefresh)}
            className="gap-1"
          >
            <RefreshCw className={`h-4 w-4 ${autoRefresh ? "animate-spin" : ""}`} />
            <span className="hidden sm:inline">Auto</span>
          </Button>
        </div>
      </div>

      {/* Custom Date Range Picker */}
      {showCustomRange && (
        <div className="flex flex-wrap items-center gap-3 p-3 rounded-lg border border-[var(--color-border)] bg-[var(--color-card)]">
          <div className="flex items-center gap-2">
            <label className="text-sm text-[var(--color-muted-foreground)]">{t("metrics.startDate") || "开始"}</label>
            <input
              type="datetime-local"
              value={customStart}
              onChange={(e) => setCustomStart(e.target.value)}
              className="px-2 py-1 text-sm rounded border border-[var(--color-border)] bg-transparent"
            />
          </div>
          <div className="flex items-center gap-2">
            <label className="text-sm text-[var(--color-muted-foreground)]">{t("metrics.endDate") || "结束"}</label>
            <input
              type="datetime-local"
              value={customEnd}
              onChange={(e) => setCustomEnd(e.target.value)}
              className="px-2 py-1 text-sm rounded border border-[var(--color-border)] bg-transparent"
            />
          </div>
          <Button
            size="sm"
            onClick={() => {
              if (customStart && customEnd) {
                setTimeRange("custom")
                fetchHistory()
              }
            }}
            disabled={!customStart || !customEnd}
          >
            {t("metrics.apply") || "应用"}
          </Button>
        </div>
      )}

      {/* Anomaly Alert */}
      {anomalies.length > 0 && (
        <div className="rounded-lg border border-yellow-500/50 bg-yellow-500/10 p-3 flex items-start gap-2">
          <AlertTriangle className="h-5 w-5 text-yellow-500 mt-0.5" />
          <div>
            <p className="font-medium text-yellow-500">{t("metrics.anomalyDetected")}</p>
            <ul className="text-sm text-[var(--color-muted-foreground)]">
              {anomalies.map((a, i) => (
                <li key={i}>• {a}</li>
              ))}
            </ul>
          </div>
        </div>
      )}

      {/* Loading */}
      {loading ? (
        <div className="flex items-center justify-center h-64">
          <RefreshCw className="h-8 w-8 animate-spin text-[var(--color-muted-foreground)]" />
        </div>
      ) : (
        /* Charts Grid */
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <MetricsChart
            data={cpuData}
            title={t("metrics.cpuUsage")}
            unit="%"
            color="#3b82f6"
            threshold={90}
            thresholdLabel="90%"
            showArea
            height={220}
            label="CPU"
          />
          <MetricsChart
            data={memoryData}
            title={t("metrics.memoryUsage")}
            unit="%"
            color="#8b5cf6"
            threshold={90}
            thresholdLabel="90%"
            showArea
            height={220}
            label="Memory"
          />
          <MetricsChart
            data={networkData}
            title={t("metrics.networkIO")}
            unit="B/s"
            color="#22c55e"
            color2="#f59e0b"
            height={220}
            label="RX"
            label2="TX"
          />
          <MetricsChart
            data={diskData}
            title={t("metrics.diskIO")}
            unit="B/s"
            color="#06b6d4"
            color2="#ec4899"
            height={220}
            label="Read"
            label2="Write"
          />
          {/* GPU Usage Chart - only shown when GPU data is available */}
          {gpuData.length > 0 && (
            <MetricsChart
              data={gpuData}
              title={gpuName ? `${t("metrics.gpuUsage")} (${gpuName})` : t("metrics.gpuUsage")}
              unit="%"
              unit2="°C"
              color="#f97316"
              color2="#ef4444"
              threshold={90}
              thresholdLabel="90%"
              showArea
              height={220}
              label={t("metrics.usage")}
              label2={t("metrics.temperature")}
            />
          )}
        </div>
      )}
    </div>
  )
}
