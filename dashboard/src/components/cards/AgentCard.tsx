import { cn, formatBytes, formatPercentage } from '@/lib/utils'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Progress } from '@/components/ui/progress'
import type { Agent } from '@/types/metrics'
import { Monitor, Server, Apple, Terminal } from 'lucide-react'

interface AgentCardProps {
  agent: Agent
  selected: boolean
  onClick: () => void
}

function getOsIcon(os: string) {
  const lower = os?.toLowerCase() || ''
  if (lower.includes('linux')) return <Terminal className="w-5 h-5" />
  if (lower.includes('darwin') || lower.includes('mac')) return <Apple className="w-5 h-5" />
  if (lower.includes('windows')) return <Monitor className="w-5 h-5" />
  return <Server className="w-5 h-5" />
}

export function AgentCard({ agent, selected, onClick }: AgentCardProps) {
  const metrics = agent.lastMetrics
  const cpuUsage = metrics?.cpu?.usagePercent || 0
  const memUsage = metrics?.memory?.total
    ? (metrics.memory.used / metrics.memory.total) * 100
    : 0

  return (
    <Card
      className={cn(
        "cursor-pointer transition-all duration-200 hover:border-primary/50",
        selected && "border-primary ring-2 ring-primary/20 bg-primary/5"
      )}
      onClick={onClick}
    >
      <CardContent className="p-4">
        {/* Header */}
        <div className="flex items-start justify-between mb-3">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-primary/10 text-primary">
              {getOsIcon(agent.os)}
            </div>
            <div>
              <h3 className="font-semibold text-foreground truncate max-w-[140px]">
                {agent.hostname || 'Unknown'}
              </h3>
              <p className="text-xs text-muted-foreground">
                {agent.os}/{agent.arch}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Badge variant="success" className="text-[10px]">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 mr-1 animate-pulse" />
              Online
            </Badge>
          </div>
        </div>

        {/* CPU Model */}
        {metrics?.cpu?.model && (
          <p className="text-xs text-muted-foreground truncate mb-3" title={metrics.cpu.model}>
            {metrics.cpu.model.replace('Intel(R) Core(TM)', 'Intel').replace('AMD Ryzen', 'Ryzen').substring(0, 35)}
          </p>
        )}

        {/* Metrics */}
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <div className="flex justify-between text-xs">
              <span className="text-muted-foreground">CPU</span>
              <span className="font-medium">{formatPercentage(cpuUsage)}</span>
            </div>
            <Progress
              value={cpuUsage}
              className="h-1.5"
              indicatorClassName={cn(
                cpuUsage > 80 ? "bg-destructive" : cpuUsage > 60 ? "bg-amber-500" : "bg-primary"
              )}
            />
          </div>
          <div className="space-y-1.5">
            <div className="flex justify-between text-xs">
              <span className="text-muted-foreground">Memory</span>
              <span className="font-medium">{formatPercentage(memUsage)}</span>
            </div>
            <Progress
              value={memUsage}
              className="h-1.5"
              indicatorClassName={cn(
                memUsage > 80 ? "bg-destructive" : memUsage > 60 ? "bg-amber-500" : "bg-emerald-500"
              )}
            />
          </div>
        </div>

        {/* GPU (if available) */}
        {metrics?.gpus && metrics.gpus.length > 0 && (
          <div className="mt-3 pt-3 border-t border-border">
            <div className="flex items-center justify-between text-xs">
              <span className="text-muted-foreground truncate max-w-[120px]" title={metrics.gpus[0].name}>
                {metrics.gpus[0].name?.replace('NVIDIA ', '').replace('GeForce ', '').substring(0, 20)}
              </span>
              <span className="font-medium">{formatPercentage(metrics.gpus[0].usagePercent)}</span>
            </div>
          </div>
        )}

        {/* Footer */}
        <div className="mt-3 pt-3 border-t border-border flex items-center justify-between text-xs text-muted-foreground">
          <span>v{agent.version || '0.1.0'}</span>
          <span>{formatBytes(metrics?.memory?.total || 0)}</span>
        </div>
      </CardContent>
    </Card>
  )
}
