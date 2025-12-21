import { useState, useEffect, useCallback, useMemo } from "react"
import { useTranslation } from "react-i18next"
import { ArrowLeft, RefreshCw, Clock, AlertTriangle } from "lucide-react"
import { Button } from "@/components/ui/button"
import { MetricsChart, type ChartDataPoint } from "./MetricsChart"
import { api, type Metrics } from "@/lib/api"

interface AgentMetricsViewProps {
  agentId: string
  agentName: string
  onBack: () => void
}

type TimeRange = "5m" | "10m" | "30m" | "1h"

const timeRangeToLimit: Record<TimeRange, number> = {
  "5m": 300,
  "10m": 600,
  "30m": 1800,
  "1h": 3600,
}

export function AgentMetricsView({ agentId, agentName, onBack }: AgentMetricsViewProps) {
  const { t } = useTranslation()
  const [history, setHistory] = useState<Metrics[]>([])
  const [loading, setLoading] = useState(true)
  const [timeRange, setTimeRange] = useState<TimeRange>("10m")
  const [autoRefresh, setAutoRefresh] = useState(true)

  const fetchHistory = useCallback(async () => {
    try {
      const limit = timeRangeToLimit[timeRange]
      const response = await api.get<Metrics[]>(`/metrics/history?agentId=${agentId}&limit=${limit}`)
      setHistory(response)
    } catch (e) {
      console.error("Failed to fetch metrics history:", e)
    } finally {
      setLoading(false)
    }
  }, [agentId, timeRange])

  useEffect(() => {
    fetchHistory()
    if (autoRefresh) {
      const interval = setInterval(fetchHistory, 2000)
      return () => clearInterval(interval)
    }
  }, [fetchHistory, autoRefresh])

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
        value: totalRx / (1024 * 1024), // MB/s
        value2: totalTx / (1024 * 1024), // MB/s
      }
    })
  }, [history])

  const diskData: ChartDataPoint[] = useMemo(() => {
    return history.map((m) => {
      const totalRead = m.disks?.reduce((sum, d) => sum + (d.readBytesPerSec || 0), 0) || 0
      const totalWrite = m.disks?.reduce((sum, d) => sum + (d.writeBytesPerSec || 0), 0) || 0
      return {
        timestamp: m.timestamp,
        value: totalRead / (1024 * 1024), // MB/s
        value2: totalWrite / (1024 * 1024), // MB/s
      }
    })
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
            <p className="text-sm text-[var(--color-muted-foreground)]">
              {t("metrics.historicalData")} - {history.length} data points
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {/* Time Range Selector */}
          <div className="flex items-center gap-1 rounded-lg border border-[var(--color-border)] p-1">
            {(["5m", "10m", "30m", "1h"] as TimeRange[]).map((range) => (
              <button
                key={range}
                onClick={() => setTimeRange(range)}
                className={`px-3 py-1 text-sm rounded transition-colors ${
                  timeRange === range
                    ? "bg-[var(--color-primary)] text-[var(--color-primary-foreground)]"
                    : "hover:bg-[var(--color-accent)]"
                }`}
              >
                {range}
              </button>
            ))}
          </div>
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
          <Button variant="outline" size="sm" onClick={fetchHistory}>
            <Clock className="h-4 w-4" />
          </Button>
        </div>
      </div>

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
            unit="MB/s"
            color="#22c55e"
            color2="#f59e0b"
            height={220}
            label="RX"
            label2="TX"
          />
          <MetricsChart
            data={diskData}
            title={t("metrics.diskIO")}
            unit="MB/s"
            color="#06b6d4"
            color2="#ec4899"
            height={220}
            label="Read"
            label2="Write"
          />
        </div>
      )}
    </div>
  )
}
