import React, { createContext, useContext, useCallback, useEffect, useState, useRef } from 'react'
import { agentsApi, metricsApi, type Agent, type Metrics, type Summary } from '@/lib/api'
import { useAuth } from './AuthContext'
import { useWebSocket, type WebSocketStatus } from '@/hooks/use-websocket'

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
  const { token, isAuthenticated } = useAuth()

  const [agents, setAgents] = useState<Agent[]>([])
  const [metrics, setMetrics] = useState<Record<string, Metrics>>({})
  const [summary, setSummary] = useState<Summary>({
    connectedAgents: 0,
    avgCpuPercent: 0,
    memoryPercent: 0,
    totalMemory: 0,
    usedMemory: 0,
  })
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [connectionMode, setConnectionMode] = useState<'websocket' | 'polling'>('websocket')

  const wsDataReceived = useRef(false)

  const handleAgents = useCallback((newAgents: Agent[]) => {
    setAgents(newAgents)
    setIsLoading(false)
    wsDataReceived.current = true
    setError(null)
  }, [])

  const handleMetrics = useCallback((newMetrics: Record<string, Metrics>) => {
    setMetrics(prev => ({ ...prev, ...newMetrics }))
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
    token: isAuthenticated ? token : null,
    onAgents: handleAgents,
    onMetrics: handleMetrics,
    onAgentUpdate: handleAgentUpdate,
    onAgentOffline: handleAgentOffline,
    onSummary: handleSummary,
  })

  const refresh = useCallback(async () => {
    if (!isAuthenticated) {
      setError('Not authenticated')
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
      const errorMsg = err instanceof Error ? err.message : 'Failed to fetch data'
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
      if (!wsDataReceived.current) {
        setConnectionMode('polling')
        refresh()
      }
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
      })
      wsDataReceived.current = false
      setIsLoading(true)
      setError(null)
    }
  }, [isAuthenticated])

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
