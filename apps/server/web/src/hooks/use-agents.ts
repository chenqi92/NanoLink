import { useState, useEffect, useCallback, useRef } from "react"
import { agentsApi, metricsApi, type Agent, type Metrics, type Summary, api } from "@/lib/api"
import { useWebSocket, type WebSocketStatus } from "./use-websocket"

/**
 * Hook for real-time agent and metrics data using WebSocket with HTTP fallback
 */
export function useAgents() {
  const [agents, setAgents] = useState<Agent[]>([])
  const [metrics, setMetrics] = useState<Record<string, Metrics>>({})
  const [summary, setSummary] = useState<Summary>({
    connectedAgents: 0,
    avgCpuPercent: 0,
    memoryPercent: 0,
    totalMemory: 0,
    usedMemory: 0,
  })
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [connectionMode, setConnectionMode] = useState<'websocket' | 'polling'>('websocket')

  // Get token for WebSocket auth
  const token = api.getToken()

  // Track if initial data received via WebSocket
  const wsDataReceived = useRef(false)

  // WebSocket handlers
  const handleAgents = useCallback((newAgents: Agent[]) => {
    setAgents(newAgents)
    setLoading(false)
    wsDataReceived.current = true
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

  // Use WebSocket for real-time updates
  const { status: wsStatus } = useWebSocket({
    token,
    onAgents: handleAgents,
    onMetrics: handleMetrics,
    onAgentUpdate: handleAgentUpdate,
    onAgentOffline: handleAgentOffline,
    onSummary: handleSummary,
  })

  // Fallback to polling if WebSocket fails or disconnects
  const fetchData = useCallback(async () => {
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
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to fetch data")
    } finally {
      setLoading(false)
    }
  }, [])

  // Handle WebSocket status changes
  useEffect(() => {
    if (wsStatus === 'connected') {
      setConnectionMode('websocket')
      setError(null)
    } else if (wsStatus === 'error' || wsStatus === 'disconnected') {
      // Fall back to polling if WebSocket is not available
      if (!wsDataReceived.current) {
        setConnectionMode('polling')
        fetchData()
      }
    }
  }, [wsStatus, fetchData])

  // Polling fallback
  useEffect(() => {
    if (connectionMode === 'polling') {
      fetchData()
      const interval = setInterval(fetchData, 2000)
      return () => clearInterval(interval)
    }
  }, [connectionMode, fetchData])

  return { 
    agents, 
    metrics, 
    summary, 
    loading, 
    error, 
    refresh: fetchData,
    wsStatus,
    connectionMode,
  }
}

export function useAgent(agentId: string) {
  const [agent, setAgent] = useState<Agent | null>(null)
  const [metrics, setMetrics] = useState<Metrics | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchData = useCallback(async () => {
    if (!agentId) return
    try {
      const [agentData, metricsData] = await Promise.all([
        agentsApi.get(agentId),
        metricsApi.get(agentId),
      ])
      setAgent(agentData)
      setMetrics(metricsData)
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to fetch agent data")
    } finally {
      setLoading(false)
    }
  }, [agentId])

  useEffect(() => {
    fetchData()
    const interval = setInterval(fetchData, 2000)
    return () => clearInterval(interval)
  }, [fetchData])

  return { agent, metrics, loading, error, refresh: fetchData }
}
