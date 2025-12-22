import { useState, useCallback, useRef, useEffect } from 'react'

interface MetricsHistoryPoint {
  timestamp: number
  cpuUsage: number
  memoryUsage: number
  networkRx: number
  networkTx: number
}

const MAX_HISTORY_POINTS = 60
const STATE_UPDATE_INTERVAL = 1000 // Update state at most once per second

export function useMetricsHistory() {
  const [history, setHistory] = useState<Record<string, MetricsHistoryPoint[]>>({})
  const lastTimestampRef = useRef<Record<string, number>>({})
  
  // Use ref for mutable history to avoid triggering renders on every update
  const historyRef = useRef<Record<string, MetricsHistoryPoint[]>>({})
  const pendingUpdateRef = useRef(false)
  const updateTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Sync ref to state periodically (throttled)
  const flushToState = useCallback(() => {
    setHistory({ ...historyRef.current })
    pendingUpdateRef.current = false
  }, [])

  // Schedule a state update if not already pending
  const scheduleStateUpdate = useCallback(() => {
    if (pendingUpdateRef.current) return
    pendingUpdateRef.current = true
    
    if (updateTimerRef.current) {
      clearTimeout(updateTimerRef.current)
    }
    updateTimerRef.current = setTimeout(flushToState, STATE_UPDATE_INTERVAL)
  }, [flushToState])

  // Cleanup timer on unmount
  useEffect(() => {
    return () => {
      if (updateTimerRef.current) {
        clearTimeout(updateTimerRef.current)
      }
    }
  }, [])

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
    // Sum all network interfaces traffic
    const networkRx = (metrics.networks || []).reduce((sum, n) => sum + (n.rxBytesPerSec || 0), 0)
    const networkTx = (metrics.networks || []).reduce((sum, n) => sum + (n.txBytesPerSec || 0), 0)

    const newPoint: MetricsHistoryPoint = {
      timestamp,
      cpuUsage,
      memoryUsage,
      networkRx,
      networkTx,
    }

    // Update ref (no re-render)
    const agentHistory = historyRef.current[agentId] || []
    const updated = [...agentHistory, newPoint]
    if (updated.length > MAX_HISTORY_POINTS) {
      updated.shift()
    }
    historyRef.current[agentId] = updated

    // Schedule throttled state update
    scheduleStateUpdate()
  }, [scheduleStateUpdate])

  const clearHistory = useCallback((agentId: string) => {
    delete historyRef.current[agentId]
    delete lastTimestampRef.current[agentId]
    scheduleStateUpdate()
  }, [scheduleStateUpdate])

  const getHistory = useCallback((agentId: string) => {
    // Return from state for consistency with React's rendering
    return history[agentId] || []
  }, [history])

  return { addMetricsPoint, clearHistory, getHistory }
}
