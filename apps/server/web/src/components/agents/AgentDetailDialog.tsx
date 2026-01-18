import { useTranslation } from "react-i18next"
import { useEffect, useState, useMemo, useCallback, useRef } from "react"
import { 
  X, Cpu, MemoryStick, HardDrive, Network, 
  Terminal, Loader2, Activity, BarChart3, RefreshCw
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Progress } from "@/components/ui/progress"
import { 
  formatBytes, formatBytesPerSec, formatPercent, 
  formatTime, getProgressColor, cn 
} from "@/lib/utils"
import { metricsApi, api, type Agent, type Metrics } from "@/lib/api"
import { useData } from "@/contexts/DataContext"
import { MetricsChart, type ChartDataPoint } from "@/components/charts/MetricsChart"
import { GpuCard } from "./GpuCard"
import { NpuCard } from "./NpuCard"
import { SystemInfoCard } from "./SystemInfoCard"
import { UserSessionsCard } from "./UserSessionsCard"

interface AgentDetailDialogProps {
  agent: Agent
  initialMetrics?: Metrics
  onClose: () => void
  onOpenShell?: (agentId: string) => void
}

type TabType = "realtime" | "charts"
type TimeRange = "5m" | "10m" | "30m" | "1h" | "6h"

const timeRangeToMs: Record<TimeRange, number> = {
  "5m": 5 * 60 * 1000,
  "10m": 10 * 60 * 1000,
  "30m": 30 * 60 * 1000,
  "1h": 60 * 60 * 1000,
  "6h": 6 * 60 * 60 * 1000,
}

const MAX_REALTIME_HISTORY = 300

export function AgentDetailDialog({ 
  agent, 
  initialMetrics,
  onClose, 
  onOpenShell,
}: AgentDetailDialogProps) {
  const { t } = useTranslation()
  const { metrics: wsMetrics } = useData()
  
  // Tab state
  const [activeTab, setActiveTab] = useState<TabType>("realtime")
  
  // Realtime metrics state
  const [metrics, setMetrics] = useState<Metrics | undefined>(initialMetrics)
  const [isLoading, setIsLoading] = useState(() => !initialMetrics)
  
  // Chart history state
  const [history, setHistory] = useState<Metrics[]>([])
  const [chartLoading, setChartLoading] = useState(false)
  const [timeRange, setTimeRange] = useState<TimeRange>("10m")
  const lastMetricsTimestamp = useRef<string | null>(null)

  // Fetch detailed metrics if not provided
  useEffect(() => {
    if (!initialMetrics) {
      metricsApi.get(agent.id)
        .then(setMetrics)
        .catch(console.error)
        .finally(() => setIsLoading(false))
    }
  }, [agent.id, initialMetrics])

  // Handle real-time WebSocket metrics updates for charts
  useEffect(() => {
    if (activeTab !== "charts") return
    
    const currentMetrics = wsMetrics[agent.id]
    if (!currentMetrics) return
    
    const metricsKey = currentMetrics.timestamp || 
      `${currentMetrics.cpu?.usagePercent ?? 0}-${currentMetrics.memory?.used ?? 0}`
    
    if (lastMetricsTimestamp.current === metricsKey) return
    lastMetricsTimestamp.current = metricsKey
    
    setHistory(prev => {
      const newHistory = [...prev, currentMetrics]
      const windowMs = timeRangeToMs[timeRange]
      const cutoffTime = Date.now() - windowMs
      
      const filtered = newHistory.filter(m => {
        const timestamp = typeof m.timestamp === 'string' 
          ? new Date(m.timestamp).getTime() 
          : m.timestamp
        return timestamp >= cutoffTime
      })
      
      return filtered.length > MAX_REALTIME_HISTORY 
        ? filtered.slice(-MAX_REALTIME_HISTORY) 
        : filtered
    })
  }, [wsMetrics, agent.id, activeTab, timeRange])

  // Fetch historical data when switching to charts tab or changing time range
  const fetchHistory = useCallback(async () => {
    try {
      setChartLoading(true)
      const now = Date.now()
      const rangeMs = timeRangeToMs[timeRange]
      const start = now - rangeMs
      
      const response = await api.get<Metrics[]>(
        `/metrics/history?agentId=${agent.id}&start=${start}&end=${now}&interval=auto`
      )
      setHistory(response)
      lastMetricsTimestamp.current = null
    } catch (e) {
      console.error("Failed to fetch metrics history:", e)
    } finally {
      setChartLoading(false)
    }
  }, [agent.id, timeRange])

  useEffect(() => {
    if (activeTab === "charts") {
      fetchHistory()
    }
  }, [activeTab, timeRange, fetchHistory])

  // Transform data for charts
  const cpuData: ChartDataPoint[] = useMemo(() => 
    history.map(m => ({ timestamp: m.timestamp, value: m.cpu?.usagePercent || 0 }))
  , [history])

  const memoryData: ChartDataPoint[] = useMemo(() => 
    history.map(m => {
      const total = m.memory?.total || 1
      const used = m.memory?.used || 0
      return { timestamp: m.timestamp, value: (used / total) * 100 }
    })
  , [history])

  const networkData: ChartDataPoint[] = useMemo(() => 
    history.map(m => {
      const totalRx = m.networks?.reduce((sum, n) => sum + (n.rxBytesPerSec || 0), 0) || 0
      const totalTx = m.networks?.reduce((sum, n) => sum + (n.txBytesPerSec || 0), 0) || 0
      return { timestamp: m.timestamp, value: totalRx, value2: totalTx }
    })
  , [history])

  const diskData: ChartDataPoint[] = useMemo(() => 
    history.map(m => {
      const totalRead = m.disks?.reduce((sum, d) => sum + (d.readBytesPerSec || 0), 0) || 0
      const totalWrite = m.disks?.reduce((sum, d) => sum + (d.writeBytesPerSec || 0), 0) || 0
      return { timestamp: m.timestamp, value: totalRead, value2: totalWrite }
    })
  , [history])

  const cpuUsage = metrics?.cpu?.usagePercent || 0
  const memUsage = metrics?.memory 
    ? (metrics.memory.used / metrics.memory.total) * 100 
    : 0

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
        onClick={onClose}
      />

      {/* Dialog */}
      <div className="relative bg-[var(--color-background)] rounded-lg shadow-xl border border-[var(--color-border)] w-[95vw] max-w-4xl max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-[var(--color-border)] shrink-0">
          <div className="flex items-center gap-3">
            <div className="h-3 w-3 rounded-full bg-green-500" />
            <div>
              <h2 className="font-semibold">{agent.hostname}</h2>
              <p className="text-xs text-[var(--color-muted-foreground)]">
                {agent.os}/{agent.arch}
              </p>
            </div>
            <Badge variant="secondary">{agent.version ? `v${agent.version}` : '--'}</Badge>
          </div>
          <div className="flex items-center gap-1">
            {onOpenShell && (
              <Button 
                size="sm" 
                variant="outline" 
                onClick={() => {
                  onOpenShell(agent.id)
                  onClose()
                }}
                disabled={agent.permission === 0}
                title={agent.permission === 0 ? 'Read-only permission - shell access disabled' : ''}
              >
                <Terminal className="mr-1 h-4 w-4" />
                {t("agent.openShell")}
              </Button>
            )}
            <Button variant="ghost" size="icon" onClick={onClose} title="Close">
              <X className="h-4 w-4" />
            </Button>
          </div>
        </div>

        {/* Tabs */}
        <div className="flex items-center gap-1 px-4 py-2 border-b border-[var(--color-border)] shrink-0">
          <button
            onClick={() => setActiveTab("realtime")}
            className={cn(
              "flex items-center gap-2 px-3 py-1.5 text-sm rounded-md transition-colors",
              activeTab === "realtime" 
                ? "bg-[var(--color-primary)] text-[var(--color-primary-foreground)]" 
                : "hover:bg-[var(--color-accent)]"
            )}
          >
            <Activity className="h-4 w-4" />
            {t("agent.realtimeData", "实时数据")}
          </button>
          <button
            onClick={() => setActiveTab("charts")}
            className={cn(
              "flex items-center gap-2 px-3 py-1.5 text-sm rounded-md transition-colors",
              activeTab === "charts" 
                ? "bg-[var(--color-primary)] text-[var(--color-primary-foreground)]" 
                : "hover:bg-[var(--color-accent)]"
            )}
          >
            <BarChart3 className="h-4 w-4" />
            {t("agent.historyCharts", "历史图表")}
          </button>
          
          {/* Time range selector for charts tab */}
          {activeTab === "charts" && (
            <div className="ml-auto flex items-center gap-1">
              {(["5m", "10m", "30m", "1h", "6h"] as TimeRange[]).map((range) => (
                <button
                  key={range}
                  onClick={() => setTimeRange(range)}
                  className={cn(
                    "px-2 py-1 text-xs rounded transition-colors",
                    timeRange === range
                      ? "bg-[var(--color-accent)] font-medium"
                      : "hover:bg-[var(--color-accent)]/50"
                  )}
                >
                  {range}
                </button>
              ))}
              <Button 
                variant="ghost" 
                size="icon" 
                className="h-6 w-6 ml-1"
                onClick={fetchHistory}
              >
                <RefreshCw className={cn("h-3 w-3", chartLoading && "animate-spin")} />
              </Button>
            </div>
          )}
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-4">
          {activeTab === "realtime" ? (
            // Realtime Data Tab
            isLoading ? (
              <div className="flex items-center justify-center h-32">
                <Loader2 className="h-8 w-8 animate-spin text-blue-500" />
              </div>
            ) : (
              <div className="space-y-4">
                {/* CPU */}
                <div className="rounded-lg border border-[var(--color-border)] p-4">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-sm font-medium flex items-center gap-2">
                      <Cpu className="h-4 w-4" /> {t("metrics.cpu")}
                    </span>
                    <span className={cn("text-sm font-medium", cpuUsage > 80 ? "text-red-500" : "")}>
                      {formatPercent(cpuUsage)}
                    </span>
                  </div>
                  <Progress value={cpuUsage} indicatorClassName={getProgressColor(cpuUsage)} />
                  {metrics?.cpu?.model && (
                    <p className="text-xs text-[var(--color-muted-foreground)] mt-2 truncate">
                      {metrics.cpu.model}
                    </p>
                  )}
                </div>

                {/* Memory */}
                <div className="rounded-lg border border-[var(--color-border)] p-4">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-sm font-medium flex items-center gap-2">
                      <MemoryStick className="h-4 w-4" /> {t("metrics.memory")}
                    </span>
                    <span className={cn("text-sm font-medium", memUsage > 80 ? "text-red-500" : "")}>
                      {formatPercent(memUsage)}
                      <span className="text-xs text-[var(--color-muted-foreground)] ml-1">
                        ({formatBytes(metrics?.memory?.used)} / {formatBytes(metrics?.memory?.total)})
                      </span>
                    </span>
                  </div>
                  <Progress value={memUsage} indicatorClassName={getProgressColor(memUsage)} />
                </div>

                {/* Disks */}
                {metrics?.disks && metrics.disks.length > 0 && (
                  <div className="rounded-lg border border-[var(--color-border)] p-4">
                    <div className="text-sm font-medium flex items-center gap-2 mb-3">
                      <HardDrive className="h-4 w-4" /> {t("metrics.disks")}
                    </div>
                    <div className="space-y-3">
                      {metrics.disks.map((disk) => {
                        const usage = disk.total > 0 ? (disk.used / disk.total) * 100 : 0
                        return (
                          <div key={disk.mountPoint} className="text-xs">
                            <div className="flex justify-between mb-1">
                              <span className="truncate max-w-[200px] text-[var(--color-muted-foreground)]">
                                {disk.mountPoint}
                              </span>
                              <span>{formatBytes(disk.used)} / {formatBytes(disk.total)}</span>
                            </div>
                            <Progress value={usage} className="h-1.5" indicatorClassName={getProgressColor(usage)} />
                          </div>
                        )
                      })}
                    </div>
                  </div>
                )}

                {/* Networks */}
                {metrics?.networks && metrics.networks.length > 0 && (
                  <div className="rounded-lg border border-[var(--color-border)] p-4">
                    <div className="text-sm font-medium flex items-center gap-2 mb-3">
                      <Network className="h-4 w-4" /> {t("metrics.networks")}
                    </div>
                    <div className="grid grid-cols-2 gap-2">
                      {metrics.networks
                        .filter(n => n.interfaceType !== "loopback" && n.interfaceType !== "virtual")
                        .map((net) => (
                          <div key={net.interface} className="rounded-lg bg-[var(--color-muted)] p-2">
                            <div className="flex items-center justify-between mb-1">
                              <span className="text-xs font-medium truncate">{net.interface}</span>
                              <div className={cn("h-2 w-2 rounded-full", net.isUp ? "bg-green-500" : "bg-red-500")} />
                            </div>
                            <div className="text-xs text-[var(--color-muted-foreground)]">
                              <div className="flex justify-between">
                                <span>↓</span>
                                <span className="text-green-500">{formatBytesPerSec(net.rxBytesPerSec)}</span>
                              </div>
                              <div className="flex justify-between">
                                <span>↑</span>
                                <span className="text-blue-500">{formatBytesPerSec(net.txBytesPerSec)}</span>
                              </div>
                            </div>
                          </div>
                        ))}
                    </div>
                  </div>
                )}

                {/* GPUs */}
                {metrics?.gpus && metrics.gpus.length > 0 && (
                  <GpuCard gpus={metrics.gpus} />
                )}

                {/* NPUs */}
                {metrics?.npus && metrics.npus.length > 0 && (
                  <NpuCard npus={metrics.npus} />
                )}

                {/* User Sessions */}
                {metrics?.userSessions && metrics.userSessions.length > 0 && (
                  <UserSessionsCard sessions={metrics.userSessions} />
                )}

                {/* System Info */}
                {metrics?.systemInfo && (
                  <SystemInfoCard systemInfo={metrics.systemInfo} />
                )}
              </div>
            )
          ) : (
            // Charts Tab
            chartLoading && history.length === 0 ? (
              <div className="flex items-center justify-center h-32">
                <Loader2 className="h-8 w-8 animate-spin text-blue-500" />
              </div>
            ) : (
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <MetricsChart
                  data={cpuData}
                  title={t("metrics.cpuUsage")}
                  unit="%"
                  color="#3b82f6"
                  threshold={90}
                  thresholdLabel="90%"
                  showArea
                  height={180}
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
                  height={180}
                  label="Memory"
                />
                <MetricsChart
                  data={networkData}
                  title={t("metrics.networkIO")}
                  unit="B/s"
                  color="#22c55e"
                  color2="#f59e0b"
                  height={180}
                  label="RX"
                  label2="TX"
                />
                <MetricsChart
                  data={diskData}
                  title={t("metrics.diskIO")}
                  unit="B/s"
                  color="#06b6d4"
                  color2="#ec4899"
                  height={180}
                  label="Read"
                  label2="Write"
                />
              </div>
            )
          )}
        </div>

        {/* Footer */}
        <div className="px-4 py-3 border-t border-[var(--color-border)] shrink-0">
          <div className="text-xs text-[var(--color-muted-foreground)]">
            {t("agent.connectedAt")}: {formatTime(agent.connectedAt)}
            {activeTab === "charts" && history.length > 0 && (
              <span className="ml-4">{history.length} {t("metrics.dataPoints", "数据点")}</span>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
