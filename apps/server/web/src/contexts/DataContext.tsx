import React, { createContext, useContext, useCallback, useEffect, useState, useRef } from 'react'
import { agentsApi, metricsApi, agentTokensApi, type Agent, type Metrics, type Summary, type AgentToken } from '@/lib/api'
import { useAuth } from './AuthContext'
import { useWebSocket, type WebSocketStatus } from '@/hooks/use-websocket'
import i18n from '@/i18n'

interface DataContextValue {
  agents: Agent[]
  metrics: Record<string, Metrics>
  summary: Summary
  isLoading: boolean
  error: string | null
  connectionMode: 'websocket' | 'polling'
  wsStatus: WebSocketStatus

  refresh: () => Promise<void>
  clearError: () => void
}

const DataContext = createContext<DataContextValue | undefined>(undefined)

export function DataProvider({ children }: { children: React.ReactNode }) {
  const { isAuthenticated, user } = useAuth()

  const [agents, setAgents] = useState<Agent[]>([])
  const [agentOrder, setAgentOrder] = useState<Map<string, number>>(new Map()) // AgentID -> SortOrder
  const [metrics, setMetrics] = useState<Record<string, Metrics>>({})
  const [summary, setSummary] = useState<Summary>({
    connectedAgents: 0,
    avgCpuPercent: 0,
    memoryPercent: 0,
    totalMemory: 0,
    usedMemory: 0,
    diskPercent: 0,
    totalDisk: 0,
    usedDisk: 0,
  })
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [connectionMode, setConnectionMode] = useState<'websocket' | 'polling'>('websocket')

  const wsDataReceived = useRef(false)

  // Fetch agent order from database
  const fetchAgentOrder = useCallback(async () => {
    try {
      const tokens = (await agentTokensApi.list(1, 500)).items
      const orderMap = new Map<string, number>()
      tokens.forEach((t: AgentToken) => {
        if (t.agentId) {
          orderMap.set(t.agentId, t.sortOrder)
        }
      })
      setAgentOrder(orderMap)
    } catch (e) {
      console.error('Failed to fetch agent order:', e)
    }
  }, [])

  // Sort agents by database order
  const sortAgentsByDBOrder = useCallback((agentList: Agent[]): Agent[] => {
    if (agentOrder.size === 0) return agentList
    return [...agentList].sort((a, b) => {
      const orderA = agentOrder.get(a.id) ?? 999999
      const orderB = agentOrder.get(b.id) ?? 999999
      return orderA - orderB
    })
  }, [agentOrder])

  const handleAgents = useCallback((newAgents: Agent[]) => {
    setAgents(sortAgentsByDBOrder(newAgents))
    setIsLoading(false)
    wsDataReceived.current = true
    setError(null)
  }, [sortAgentsByDBOrder])

  const handleMetrics = useCallback((newMetrics: Record<string, Metrics>) => {
    setMetrics(prev => ({ ...prev, ...newMetrics }))
    // Receiving metrics for an agent means it is alive. The agent list (with
    // lastHeartbeat) is pushed far less often than metrics, so without this the
    // heartbeat ages past the 60s window between pushes and the node flaps
    // offline even while data keeps streaming. Keep it fresh on every tick.
    const ids = Object.keys(newMetrics)
    if (ids.length) {
      const now = new Date().toISOString()
      setAgents(prev => prev.map(a => (ids.includes(a.id) ? { ...a, lastHeartbeat: now } : a)))
    }
  }, [])

  const handleAgentUpdate = useCallback((agentId: string, agent: Agent) => {
    setAgents(prev => {
      const index = prev.findIndex(a => a.id === agentId)
      if (index >= 0) {
        const updated = [...prev]
        updated[index] = agent
        return updated
      }
      return [...prev, agent]
    })
  }, [])

  const handleAgentOffline = useCallback((agentId: string) => {
    setAgents(prev => prev.filter(a => a.id !== agentId))
    setMetrics(prev => {
      const updated = { ...prev }
      delete updated[agentId]
      return updated
    })
  }, [])

  const handleSummary = useCallback((newSummary: Summary) => {
    setSummary(newSummary)
  }, [])

  // Only connect WebSocket when authenticated
  const { status: wsStatus } = useWebSocket({
    enabled: isAuthenticated,
    onAgents: handleAgents,
    onMetrics: handleMetrics,
    onAgentUpdate: handleAgentUpdate,
    onAgentOffline: handleAgentOffline,
    onSummary: handleSummary,
  })

  const refresh = useCallback(async () => {
    if (!isAuthenticated) {
      setError(i18n.t('access.sessionExpired'))
      return
    }

    setIsLoading(true)
    try {
      const [agentsData, metricsData, summaryData] = await Promise.all([
        agentsApi.list(),
        metricsApi.all(),
        metricsApi.summary(),
      ])
      setAgents(agentsData)
      setMetrics(metricsData)
      setSummary(summaryData)
      setError(null)
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : i18n.t('access.requestFailedDesc')
      setError(errorMsg)
    } finally {
      setIsLoading(false)
    }
  }, [isAuthenticated])

  // Handle WebSocket status changes
  useEffect(() => {
    if (!isAuthenticated) {
      setIsLoading(false)
      return
    }

    if (wsStatus === 'connected') {
      setConnectionMode('websocket')
      setError(null)
    } else if (wsStatus === 'error' || wsStatus === 'disconnected') {
      // Fall back to polling whenever the WS is down — including a mid-session
      // drop after it had delivered data. Previously this only triggered when no
      // WS data had ever arrived, so a dropped connection that failed to
      // reconnect left the dashboard frozen. When the WS reconnects, the
      // 'connected' branch switches back to websocket and clears the interval.
      setConnectionMode('polling')
      refresh()
    }
  }, [wsStatus, isAuthenticated, refresh])

  // Polling fallback
  useEffect(() => {
    if (!isAuthenticated) return

    if (connectionMode === 'polling') {
      const interval = setInterval(refresh, 2000)
      return () => clearInterval(interval)
    }
  }, [connectionMode, isAuthenticated, refresh])

  // Reset state when authentication changes
  useEffect(() => {
    if (!isAuthenticated) {
      setAgents([])
      setMetrics({})
      setSummary({
        connectedAgents: 0,
        avgCpuPercent: 0,
        memoryPercent: 0,
        totalMemory: 0,
        usedMemory: 0,
        diskPercent: 0,
        totalDisk: 0,
        usedDisk: 0,
      })
      wsDataReceived.current = false
      setIsLoading(true)
      setError(null)
      setAgentOrder(new Map())
    } else if (user?.isSuperAdmin) {
      // Fetch agent order when authenticated
      fetchAgentOrder()
    }
  }, [isAuthenticated, user?.isSuperAdmin, fetchAgentOrder])

  const clearError = useCallback(() => {
    setError(null)
  }, [])

  const value: DataContextValue = {
    agents,
    metrics,
    summary,
    isLoading,
    error,
    connectionMode,
    wsStatus,
    refresh,
    clearError,
  }

  return <DataContext.Provider value={value}>{children}</DataContext.Provider>
}

export function useData() {
  const context = useContext(DataContext)
  if (!context) {
    throw new Error('useData must be used within DataProvider')
  }
  return context
}
