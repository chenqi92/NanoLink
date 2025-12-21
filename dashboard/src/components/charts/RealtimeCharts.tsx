import { useMemo } from 'react'
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Area,
  AreaChart,
} from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { formatBytes } from '@/lib/utils'

interface MetricsHistoryPoint {
  timestamp: number
  cpuUsage: number
  memoryUsage: number
  networkRx: number
  networkTx: number
}

interface RealtimeChartProps {
  data: MetricsHistoryPoint[]
}

export function CpuMemoryChart({ data }: RealtimeChartProps) {
  const chartData = useMemo(() => {
    return data.map((point, index) => ({
      time: index,
      cpu: point.cpuUsage,
      memory: point.memoryUsage,
    }))
  }, [data])

  return (
    <Card className="glass">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">CPU & Memory Usage</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="h-48">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={chartData}>
              <defs>
                <linearGradient id="cpuGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#3b82f6" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="memoryGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#22c55e" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#22c55e" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
              <XAxis dataKey="time" hide />
              <YAxis
                domain={[0, 100]}
                tick={{ fill: '#64748b', fontSize: 12 }}
                tickFormatter={(value) => `${value}%`}
                width={45}
              />
              <Tooltip
                contentStyle={{
                  backgroundColor: '#1e293b',
                  border: '1px solid #334155',
                  borderRadius: '8px',
                }}
                labelStyle={{ color: '#94a3b8' }}
                formatter={(value: number, name: string) => [
                  `${value.toFixed(1)}%`,
                  name === 'cpu' ? 'CPU' : 'Memory',
                ]}
              />
              <Area
                type="monotone"
                dataKey="cpu"
                stroke="#3b82f6"
                strokeWidth={2}
                fill="url(#cpuGradient)"
                dot={false}
              />
              <Area
                type="monotone"
                dataKey="memory"
                stroke="#22c55e"
                strokeWidth={2}
                fill="url(#memoryGradient)"
                dot={false}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
        <div className="flex justify-center gap-6 mt-2 text-xs">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-blue-500" />
            <span className="text-muted-foreground">CPU</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-emerald-500" />
            <span className="text-muted-foreground">Memory</span>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

export function NetworkChart({ data }: RealtimeChartProps) {
  const chartData = useMemo(() => {
    return data.map((point, index) => ({
      time: index,
      rx: point.networkRx,
      tx: point.networkTx,
    }))
  }, [data])

  const maxValue = useMemo(() => {
    const values = data.flatMap(p => [p.networkRx, p.networkTx])
    return Math.max(...values, 1024) // Minimum 1KB scale
  }, [data])

  return (
    <Card className="glass">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">Network Activity</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="h-48">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
              <XAxis dataKey="time" hide />
              <YAxis
                domain={[0, maxValue]}
                tick={{ fill: '#64748b', fontSize: 12 }}
                tickFormatter={(value) => formatBytes(value)}
                width={60}
              />
              <Tooltip
                contentStyle={{
                  backgroundColor: '#1e293b',
                  border: '1px solid #334155',
                  borderRadius: '8px',
                }}
                labelStyle={{ color: '#94a3b8' }}
                formatter={(value: number, name: string) => [
                  `${formatBytes(value)}/s`,
                  name === 'rx' ? 'Download' : 'Upload',
                ]}
              />
              <Line
                type="monotone"
                dataKey="rx"
                stroke="#22c55e"
                strokeWidth={2}
                dot={false}
              />
              <Line
                type="monotone"
                dataKey="tx"
                stroke="#3b82f6"
                strokeWidth={2}
                dot={false}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
        <div className="flex justify-center gap-6 mt-2 text-xs">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-emerald-500" />
            <span className="text-muted-foreground">Download (↓)</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-blue-500" />
            <span className="text-muted-foreground">Upload (↑)</span>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
