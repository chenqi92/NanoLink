import { useState, useCallback, useRef } from 'react'

interface MetricsHistoryPoint {
  timestamp: number
  cpuUsage: number
  memoryUsage: number
  networkRx: number
  networkTx: number
}

const MAX_HISTORY_POINTS = 60

export function useMetricsHistory() {
  const [history, setHistory] = useState<Record<string, MetricsHistoryPoint[]>>({})
  const lastTimestampRef = useRef<Record<string, number>>({})

  const addMetricsPoint = useCallback((agentId: string, metrics: {
    cpu?: { usagePercent?: number }
    memory?: { used?: number; total?: number }
    networks?: Array<{ rxBytesPerSec?: number; txBytesPerSec?: number }>
    timestamp?: number
  }) => {
    if (!metrics) return

    const timestamp = metrics.timestamp || Date.now()
    
    // Skip if same timestamp
    if (lastTimestampRef.current[agentId] === timestamp) return
    lastTimestampRef.current[agentId] = timestamp

    const cpuUsage = metrics.cpu?.usagePercent || 0
    const memoryUsage = metrics.memory?.total && metrics.memory?.used
      ? (metrics.memory.used / metrics.memory.total) * 100
      : 0
    const networkRx = metrics.networks?.[0]?.rxBytesPerSec || 0
    const networkTx = metrics.networks?.[0]?.txBytesPerSec || 0

    setHistory(prev => {
      const agentHistory = prev[agentId] || []
      const newPoint: MetricsHistoryPoint = {
        timestamp,
        cpuUsage,
        memoryUsage,
        networkRx,
        networkTx,
      }
      
      const updated = [...agentHistory, newPoint]
      if (updated.length > MAX_HISTORY_POINTS) {
        updated.shift()
      }
      
      return { ...prev, [agentId]: updated }
    })
  }, [])

  const clearHistory = useCallback((agentId: string) => {
    setHistory(prev => {
      const updated = { ...prev }
      delete updated[agentId]
      return updated
    })
    delete lastTimestampRef.current[agentId]
  }, [])

  const getHistory = useCallback((agentId: string) => {
    return history[agentId] || []
  }, [history])

  return { addMetricsPoint, clearHistory, getHistory }
}
