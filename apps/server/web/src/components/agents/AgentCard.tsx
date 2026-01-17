import { useTranslation } from "react-i18next"
import { 
  Cpu, MemoryStick, HardDrive, Network, Thermometer, 
  Terminal, ChevronDown, ChevronUp, Users, Info, BarChart3
} from "lucide-react"
import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Progress } from "@/components/ui/progress"
import { formatBytes, formatBytesPerSec, formatPercent, formatTime, formatUptime, getProgressColor, cn } from "@/lib/utils"
import type { Agent, Metrics } from "@/lib/api"
import { GpuCard } from "./GpuCard"
import { NpuCard } from "./NpuCard"
import { SystemInfoCard } from "./SystemInfoCard"
import { UserSessionsCard } from "./UserSessionsCard"

interface AgentCardProps {
  agent: Agent
  metrics?: Metrics
  onOpenShell?: (agentId: string) => void
  onViewMetrics?: (agentId: string) => void
}

export function AgentCard({ agent, metrics, onOpenShell, onViewMetrics }: AgentCardProps) {
  const { t } = useTranslation()
  const [expanded, setExpanded] = useState(false)

  const cpuUsage = metrics?.cpu?.usagePercent || 0
  const memUsage = metrics?.memory 
    ? (metrics.memory.used / metrics.memory.total) * 100 
    : 0

  return (
    <Card className="overflow-hidden">
      <CardHeader className="pb-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="h-3 w-3 rounded-full bg-green-500" />
            <div>
              <CardTitle className="text-lg">{agent.hostname}</CardTitle>
              <p className="text-xs text-[var(--color-muted-foreground)]">
                {agent.os}/{agent.arch}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Badge variant="secondary">{agent.version ? `v${agent.version}` : '--'}</Badge>
            {onViewMetrics && (
              <Button size="sm" variant="outline" onClick={() => onViewMetrics(agent.id)}>
                <BarChart3 className="mr-1 h-4 w-4" />
                {t("agent.viewMetrics")}
              </Button>
            )}
            {onOpenShell && (
              <Button 
                size="sm" 
                variant="outline" 
                onClick={() => onOpenShell(agent.id)}
                disabled={agent.permission === 0}
                title={agent.permission === 0 ? 'Read-only permission - shell access disabled' : ''}
              >
                <Terminal className="mr-1 h-4 w-4" />
                {t("agent.openShell")}
              </Button>
            )}
          </div>
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* CPU */}
        <div>
          <div className="flex items-center justify-between mb-1">
            <span className="text-sm flex items-center gap-1">
              <Cpu className="h-4 w-4" /> {t("metrics.cpu")}
            </span>
            <span className={cn("text-sm font-medium", cpuUsage > 80 ? "text-red-500" : "")}>
              {formatPercent(cpuUsage)}
            </span>
          </div>
          <Progress value={cpuUsage} indicatorClassName={getProgressColor(cpuUsage)} />
          {metrics?.cpu?.model && (
            <p className="text-xs text-[var(--color-muted-foreground)] mt-1 truncate">
              {metrics.cpu.model}
            </p>
          )}
        </div>

        {/* Memory */}
        <div>
          <div className="flex items-center justify-between mb-1">
            <span className="text-sm flex items-center gap-1">
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
          <div>
            <div className="text-sm flex items-center gap-1 mb-2">
              <HardDrive className="h-4 w-4" /> {t("metrics.disks")}
            </div>
            <div className="space-y-2">
              {metrics.disks.slice(0, expanded ? undefined : 2).map((disk) => {
                const usage = disk.total > 0 ? (disk.used / disk.total) * 100 : 0
                return (
                  <div key={disk.mountPoint} className="text-xs">
                    <div className="flex justify-between mb-1">
                      <span className="truncate max-w-[150px] text-[var(--color-muted-foreground)]">
                        {disk.mountPoint}
                      </span>
                      <span>{formatBytes(disk.used)} / {formatBytes(disk.total)}</span>
                    </div>
                    <Progress value={usage} className="h-1" indicatorClassName={getProgressColor(usage)} />
                  </div>
                )
              })}
            </div>
          </div>
        )}

        {/* Networks */}
        {metrics?.networks && metrics.networks.length > 0 && (
          <div>
            <div className="text-sm flex items-center gap-1 mb-2">
              <Network className="h-4 w-4" /> {t("metrics.networks")}
            </div>
            <div className="grid grid-cols-2 gap-2">
              {metrics.networks
                .filter(n => n.interfaceType !== "loopback" && n.interfaceType !== "virtual")
                .slice(0, expanded ? undefined : 2)
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

        {/* Expandable sections */}
        {expanded && (
          <>
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
          </>
        )}

        {/* Footer */}
        <div className="flex items-center justify-between pt-2 border-t border-[var(--color-border)]">
          <div className="text-xs text-[var(--color-muted-foreground)]">
            {t("agent.connectedAt")}: {formatTime(agent.connectedAt)}
          </div>
          <Button 
            variant="ghost" 
            size="sm" 
            onClick={() => setExpanded(!expanded)}
            className="h-6 px-2"
          >
            {expanded ? (
              <><ChevronUp className="h-4 w-4 mr-1" /> Less</>
            ) : (
              <><ChevronDown className="h-4 w-4 mr-1" /> More</>
            )}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}
