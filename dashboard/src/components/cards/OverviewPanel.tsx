import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'
import { cn, formatBytes, formatPercentage, formatUptime } from '@/lib/utils'
import type { Agent } from '@/types/metrics'
import { Cpu, MemoryStick, HardDrive, Network, Thermometer, Activity } from 'lucide-react'
import { CpuMemoryChart, NetworkChart } from '@/components/charts/RealtimeCharts'

interface MetricCardProps {
  title: string
  icon: React.ReactNode
  value: string
  subValue?: string
  progress?: number
  progressColor?: string
  children?: React.ReactNode
}

function MetricCard({ title, icon, value, subValue, progress, progressColor, children }: MetricCardProps) {
  return (
    <Card className="glass">
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
        <div className="text-primary">{icon}</div>
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{value}</div>
        {subValue && <p className="text-xs text-muted-foreground mt-1">{subValue}</p>}
        {typeof progress === 'number' && (
          <Progress
            value={progress}
            className="h-2 mt-3"
            indicatorClassName={progressColor}
          />
        )}
        {children}
      </CardContent>
    </Card>
  )
}

interface MetricsHistoryPoint {
  timestamp: number
  cpuUsage: number
  memoryUsage: number
  networkRx: number
  networkTx: number
}

interface OverviewPanelProps {
  agent: Agent
  metricsHistory?: MetricsHistoryPoint[]
}

export function OverviewPanel({ agent, metricsHistory = [] }: OverviewPanelProps) {
  const metrics = agent.lastMetrics
  if (!metrics) {
    return (
      <div className="flex items-center justify-center h-64 text-muted-foreground">
        <p>Waiting for metrics data...</p>
      </div>
    )
  }

  const cpuUsage = metrics.cpu.usagePercent
  const memUsage = metrics.memory.total > 0 ? (metrics.memory.used / metrics.memory.total) * 100 : 0
  const mainDisk = metrics.disks[0]
  const diskUsage = mainDisk ? mainDisk.usagePercent : 0
  const network = metrics.networks[0]

  return (
    <div className="space-y-6">
      {/* Real-time Charts */}
      {metricsHistory.length > 0 && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <CpuMemoryChart data={metricsHistory} />
          <NetworkChart data={metricsHistory} />
        </div>
      )}

      {/* Quick Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <MetricCard
          title="CPU Usage"
          icon={<Cpu className="w-4 h-4" />}
          value={formatPercentage(cpuUsage)}
          subValue={`${metrics.cpu.coreCount} cores @ ${(metrics.cpu.frequencyMhz / 1000).toFixed(1)} GHz`}
          progress={cpuUsage}
          progressColor={cn(
            cpuUsage > 80 ? "bg-destructive" : cpuUsage > 60 ? "bg-amber-500" : "bg-primary"
          )}
        />

        <MetricCard
          title="Memory"
          icon={<MemoryStick className="w-4 h-4" />}
          value={formatPercentage(memUsage)}
          subValue={`${formatBytes(metrics.memory.used)} / ${formatBytes(metrics.memory.total)}`}
          progress={memUsage}
          progressColor={cn(
            memUsage > 80 ? "bg-destructive" : memUsage > 60 ? "bg-amber-500" : "bg-emerald-500"
          )}
        />

        <MetricCard
          title="Disk"
          icon={<HardDrive className="w-4 h-4" />}
          value={formatPercentage(diskUsage)}
          subValue={mainDisk ? `${formatBytes(mainDisk.used)} / ${formatBytes(mainDisk.total)}` : '--'}
          progress={diskUsage}
          progressColor={cn(
            diskUsage > 90 ? "bg-destructive" : diskUsage > 75 ? "bg-amber-500" : "bg-cyan-500"
          )}
        />

        <MetricCard
          title="Network"
          icon={<Network className="w-4 h-4" />}
          value={network ? formatBytes(network.rxBytesPerSec) + '/s' : '--'}
          subValue={network ? `↑ ${formatBytes(network.txBytesPerSec)}/s` : '--'}
        />
      </div>

      {/* System Info */}
      {metrics.systemInfo && (
        <Card className="glass">
          <CardHeader>
            <CardTitle className="text-sm font-medium">System Information</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div>
                <p className="text-muted-foreground">Hostname</p>
                <p className="font-medium">{metrics.systemInfo.hostname}</p>
              </div>
              <div>
                <p className="text-muted-foreground">OS</p>
                <p className="font-medium">{metrics.systemInfo.osName} {metrics.systemInfo.osVersion}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Kernel</p>
                <p className="font-medium truncate" title={metrics.systemInfo.kernelVersion}>
                  {metrics.systemInfo.kernelVersion}
                </p>
              </div>
              <div>
                <p className="text-muted-foreground">Uptime</p>
                <p className="font-medium">{formatUptime(metrics.systemInfo.uptimeSeconds)}</p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* GPU Cards */}
      {metrics.gpus.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {metrics.gpus.map((gpu, i) => (
            <Card key={i} className="glass">
              <CardHeader className="pb-2">
                <div className="flex items-center justify-between">
                  <CardTitle className="text-sm font-medium">{gpu.name}</CardTitle>
                  {gpu.temperature > 0 && (
                    <div className={cn(
                      "flex items-center gap-1 text-sm",
                      gpu.temperature > 80 ? "text-destructive" : 
                      gpu.temperature > 60 ? "text-amber-500" : "text-emerald-500"
                    )}>
                      <Thermometer className="w-4 h-4" />
                      {gpu.temperature}°C
                    </div>
                  )}
                </div>
              </CardHeader>
              <CardContent>
                <div className="space-y-3">
                  <div>
                    <div className="flex justify-between text-sm mb-1">
                      <span className="text-muted-foreground">GPU Usage</span>
                      <span>{formatPercentage(gpu.usagePercent)}</span>
                    </div>
                    <Progress value={gpu.usagePercent} className="h-2" indicatorClassName="bg-emerald-500" />
                  </div>
                  <div>
                    <div className="flex justify-between text-sm mb-1">
                      <span className="text-muted-foreground">VRAM</span>
                      <span>{formatBytes(gpu.memoryUsed)} / {formatBytes(gpu.memoryTotal)}</span>
                    </div>
                    <Progress 
                      value={gpu.memoryTotal > 0 ? (gpu.memoryUsed / gpu.memoryTotal) * 100 : 0} 
                      className="h-2" 
                      indicatorClassName="bg-purple-500" 
                    />
                  </div>
                  <div className="grid grid-cols-3 gap-2 text-xs pt-2 border-t border-border">
                    <div>
                      <p className="text-muted-foreground">Power</p>
                      <p>{gpu.powerWatts}W</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Clock</p>
                      <p>{gpu.clockCoreMhz} MHz</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Fan</p>
                      <p>{gpu.fanSpeedPercent}%</p>
                    </div>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Disks */}
      {metrics.disks.length > 0 && (
        <Card className="glass">
          <CardHeader>
            <CardTitle className="text-sm font-medium">Storage</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {metrics.disks.map((disk, i) => (
                <div key={i}>
                  <div className="flex items-center justify-between text-sm mb-2">
                    <div className="flex items-center gap-2">
                      <HardDrive className="w-4 h-4 text-muted-foreground" />
                      <span className="font-medium">{disk.mountPoint}</span>
                      <span className="text-xs text-muted-foreground">({disk.fsType})</span>
                    </div>
                    <span>{formatBytes(disk.used)} / {formatBytes(disk.total)}</span>
                  </div>
                  <Progress 
                    value={disk.usagePercent} 
                    className="h-2"
                    indicatorClassName={cn(
                      disk.usagePercent > 90 ? "bg-destructive" : 
                      disk.usagePercent > 75 ? "bg-amber-500" : "bg-cyan-500"
                    )}
                  />
                  {(disk.readBytesPerSec > 0 || disk.writeBytesPerSec > 0) && (
                    <div className="flex gap-4 mt-1 text-xs text-muted-foreground">
                      <span>↓ {formatBytes(disk.readBytesPerSec)}/s</span>
                      <span>↑ {formatBytes(disk.writeBytesPerSec)}/s</span>
                    </div>
                  )}
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* User Sessions */}
      {metrics.userSessions.length > 0 && (
        <Card className="glass">
          <CardHeader>
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <Activity className="w-4 h-4" />
              Active Sessions ({metrics.userSessions.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
              {metrics.userSessions.map((session, i) => (
                <div key={i} className="p-3 rounded-lg bg-secondary/50">
                  <div className="flex items-center justify-between">
                    <span className="font-medium">{session.username}</span>
                    <span className="text-xs text-muted-foreground">{session.tty}</span>
                  </div>
                  {session.remoteHost && (
                    <p className="text-xs text-muted-foreground mt-1">{session.remoteHost}</p>
                  )}
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
