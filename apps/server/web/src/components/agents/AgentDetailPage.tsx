import { useState } from "react"
import { useTranslation } from "react-i18next"
import { 
  ArrowLeft, Activity, BarChart3, Terminal as TerminalIcon,
  Settings, Cpu, MemoryStick, HardDrive, Network
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Progress } from "@/components/ui/progress"
import { 
  formatBytes, formatBytesPerSec, formatPercent, 
  formatTime, getProgressColor, cn 
} from "@/lib/utils"
import { Terminal } from "@/components/shell/Terminal"
import { TerminalSettingsDialog, loadTerminalSettings, type TerminalSettings } from "@/components/shell/TerminalSettings"
import { AgentMetricsView } from "@/components/charts/AgentMetricsView"
import { GpuCard } from "./GpuCard"
import { NpuCard } from "./NpuCard"
import { SystemInfoCard } from "./SystemInfoCard"
import { UserSessionsCard } from "./UserSessionsCard"
import { useData } from "@/contexts/DataContext"
import type { Agent, Metrics } from "@/lib/api"

interface AgentDetailPageProps {
  agent: Agent
  initialMetrics?: Metrics
  onBack: () => void
}

type TabType = "realtime" | "charts" | "terminal"

export function AgentDetailPage({ 
  agent, 
  initialMetrics,
  onBack,
}: AgentDetailPageProps) {
  const { t } = useTranslation()
  const { metrics: allMetrics } = useData()
  
  // Use real-time metrics from context, fallback to initial
  const metrics = allMetrics[agent.id] || initialMetrics
  
  // Tab state
  const [activeTab, setActiveTab] = useState<TabType>("realtime")
  
  // Terminal settings
  const [showTerminalSettings, setShowTerminalSettings] = useState(false)
  const [terminalSettings, setTerminalSettings] = useState<TerminalSettings>(loadTerminalSettings)
  const [terminalKey, setTerminalKey] = useState(0)

  const handleSettingsChange = (newSettings: TerminalSettings) => {
    setTerminalSettings(newSettings)
    setTerminalKey((k) => k + 1)
  }

  const cpuUsage = metrics?.cpu?.usagePercent || 0
  const memUsage = metrics?.memory 
    ? (metrics.memory.used / metrics.memory.total) * 100 
    : 0

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={onBack}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div className="h-3 w-3 rounded-full bg-green-500" />
          <div>
            <h2 className="text-xl font-semibold">{agent.hostname}</h2>
            <p className="text-sm text-[var(--color-muted-foreground)]">
              {agent.os}/{agent.arch}
            </p>
          </div>
          <Badge variant="secondary">{agent.version ? `v${agent.version}` : '--'}</Badge>
        </div>
        
        {/* Terminal settings button (only visible on terminal tab) */}
        {activeTab === "terminal" && (
          <Button
            variant="outline"
            size="sm"
            onClick={() => setShowTerminalSettings(true)}
          >
            <Settings className="h-4 w-4 mr-1" />
            {t("shell.settings", "Settings")}
          </Button>
        )}
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-1 border-b border-[var(--color-border)] pb-px">
        <button
          onClick={() => setActiveTab("realtime")}
          className={cn(
            "flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-t-md transition-colors border-b-2",
            activeTab === "realtime" 
              ? "border-blue-500 text-blue-500 bg-blue-500/10" 
              : "border-transparent hover:bg-[var(--color-accent)]"
          )}
        >
          <Activity className="h-4 w-4" />
          {t("agent.realtimeData", "实时数据")}
        </button>
        <button
          onClick={() => setActiveTab("charts")}
          className={cn(
            "flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-t-md transition-colors border-b-2",
            activeTab === "charts" 
              ? "border-blue-500 text-blue-500 bg-blue-500/10" 
              : "border-transparent hover:bg-[var(--color-accent)]"
          )}
        >
          <BarChart3 className="h-4 w-4" />
          {t("agent.historyCharts", "历史图表")}
        </button>
        <button
          onClick={() => setActiveTab("terminal")}
          disabled={agent.permission === 0}
          className={cn(
            "flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-t-md transition-colors border-b-2",
            activeTab === "terminal" 
              ? "border-blue-500 text-blue-500 bg-blue-500/10" 
              : "border-transparent hover:bg-[var(--color-accent)]",
            agent.permission === 0 && "opacity-50 cursor-not-allowed"
          )}
          title={agent.permission === 0 ? t("shell.readOnlyDisabled", "Read-only mode - terminal disabled") : ""}
        >
          <TerminalIcon className="h-4 w-4" />
          {t("shell.terminal", "终端")}
        </button>
      </div>

      {/* Tab Content */}
      <div className="min-h-[500px]">
        {activeTab === "realtime" && (
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
                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
                  {metrics.networks
                    .filter(n => n.interfaceType !== "loopback" && n.interfaceType !== "virtual")
                    .map((net) => (
                      <div key={net.interface} className="rounded-lg bg-[var(--color-muted)] p-2">
                        <div className="flex items-center justify-between mb-1">
                          <span className="text-xs font-medium truncate">{net.interface}</span>
                          <div className={cn("h-2 w-2 rounded-full", net.isUp ? "bg-green-500" : "bg-red-500")} />
                        </div>
                        {/* IP Addresses */}
                        {net.ipAddresses && net.ipAddresses.length > 0 && (
                          <div className="text-xs text-[var(--color-muted-foreground)] mb-1 truncate" title={net.ipAddresses.join(", ")}>
                            {net.ipAddresses.filter(ip => !ip.includes(":")).slice(0, 1).join(", ") || net.ipAddresses[0]}
                          </div>
                        )}
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
              <SystemInfoCard systemInfo={metrics.systemInfo} networks={metrics.networks} />
            )}

            {/* Footer */}
            <div className="text-xs text-[var(--color-muted-foreground)]">
              {t("agent.connectedAt")}: {formatTime(agent.connectedAt)}
            </div>
          </div>
        )}

        {activeTab === "charts" && (
          /* Full AgentMetricsView with all time range options */
          <AgentMetricsView
            agentId={agent.id}
            agentName={agent.hostname}
            onBack={() => setActiveTab("realtime")}
            embedded={true}
          />
        )}

        {activeTab === "terminal" && (
          <div className="rounded-lg border border-[var(--color-border)] h-[600px] overflow-hidden">
            <Terminal 
              key={terminalKey} 
              agentId={agent.id} 
              settings={terminalSettings} 
            />
          </div>
        )}
      </div>

      {/* Terminal Settings Dialog */}
      <TerminalSettingsDialog
        open={showTerminalSettings}
        onClose={() => setShowTerminalSettings(false)}
        settings={terminalSettings}
        onSettingsChange={handleSettingsChange}
      />
    </div>
  )
}
