import { useTranslation } from "react-i18next"
import { Cpu, MemoryStick, Eye } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Progress } from "@/components/ui/progress"
import { formatPercent, formatTime, getProgressColor, cn } from "@/lib/utils"
import type { Agent, Metrics } from "@/lib/api"

interface AgentCardCompactProps {
  agent: Agent
  metrics?: Metrics
  onViewDetails: (agent: Agent) => void
}

export function AgentCardCompact({ agent, metrics, onViewDetails }: AgentCardCompactProps) {
  const { t } = useTranslation()

  const cpuUsage = metrics?.cpu?.usagePercent || 0
  const memUsage = metrics?.memory 
    ? (metrics.memory.used / metrics.memory.total) * 100 
    : 0

  return (
    <Card 
      className="overflow-hidden cursor-pointer transition-all hover:shadow-lg hover:border-blue-500/50"
      onClick={() => onViewDetails(agent)}
    >
      <CardHeader className="pb-2 pt-3 px-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 min-w-0">
            <div className="h-2.5 w-2.5 rounded-full bg-green-500 flex-shrink-0" />
            <div className="min-w-0">
              <CardTitle className="text-base truncate">{agent.hostname}</CardTitle>
              <p className="text-xs text-[var(--color-muted-foreground)] truncate">
                {agent.os}/{agent.arch}
              </p>
            </div>
          </div>
          <Badge variant="secondary" className="flex-shrink-0 text-xs">
            {agent.version ? `v${agent.version}` : '--'}
          </Badge>
        </div>
      </CardHeader>

      <CardContent className="px-4 pb-3 pt-2">
        {/* Compact metrics row */}
        <div className="grid grid-cols-2 gap-3">
          {/* CPU */}
          <div>
            <div className="flex items-center justify-between mb-1">
              <span className="text-xs flex items-center gap-1 text-[var(--color-muted-foreground)]">
                <Cpu className="h-3 w-3" /> {t("metrics.cpu")}
              </span>
              <span className={cn("text-xs font-medium", cpuUsage > 80 ? "text-red-500" : "")}>
                {formatPercent(cpuUsage)}
              </span>
            </div>
            <Progress value={cpuUsage} className="h-1.5" indicatorClassName={getProgressColor(cpuUsage)} />
          </div>

          {/* Memory */}
          <div>
            <div className="flex items-center justify-between mb-1">
              <span className="text-xs flex items-center gap-1 text-[var(--color-muted-foreground)]">
                <MemoryStick className="h-3 w-3" /> {t("metrics.memory")}
              </span>
              <span className={cn("text-xs font-medium", memUsage > 80 ? "text-red-500" : "")}>
                {formatPercent(memUsage)}
              </span>
            </div>
            <Progress value={memUsage} className="h-1.5" indicatorClassName={getProgressColor(memUsage)} />
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between mt-3 pt-2 border-t border-[var(--color-border)]">
          <span className="text-xs text-[var(--color-muted-foreground)] truncate">
            {formatTime(agent.connectedAt)}
          </span>
          <Button 
            variant="ghost" 
            size="sm" 
            className="h-6 px-2 text-xs"
            onClick={(e) => {
              e.stopPropagation()
              onViewDetails(agent)
            }}
          >
            <Eye className="h-3 w-3 mr-1" />
            {t("agent.viewDetails", "Details")}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}
