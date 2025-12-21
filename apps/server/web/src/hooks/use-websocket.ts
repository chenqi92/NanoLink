import { useEffect, useRef, useCallback, useState } from 'react'
import type { Agent, Metrics } from '@/lib/api'

export type WebSocketStatus = 'connecting' | 'connected' | 'disconnected' | 'error'

interface DashboardMessage {
  type: 'agents' | 'metrics' | 'agent_update' | 'agent_offline' | 'summary' | 'pong'
  timestamp: number
  data?: unknown
}

interface Summary {
  connectedAgents: number
  avgCpuPercent: number
  memoryPercent: number
  totalMemory: number
  usedMemory: number
}

interface UseWebSocketOptions {
  token: string | null
  onAgents?: (agents: Agent[]) => void
  onMetrics?: (metrics: Record<string, Metrics>) => void
  onAgentUpdate?: (agentId: string, agent: Agent) => void
  onAgentOffline?: (agentId: string) => void
  onSummary?: (summary: Summary) => void
  reconnectInterval?: number
}

export function useWebSocket({
  token,
  onAgents,
  onMetrics,
  onAgentUpdate,
  onAgentOffline,
  onSummary,
  reconnectInterval = 3000,
}: UseWebSocketOptions) {
  const [status, setStatus] = useState<WebSocketStatus>('disconnected')
  const wsRef = useRef<WebSocket | null>(null)
  const reconnectTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const pingIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null)
  
  // Store callbacks in refs to avoid dependency changes
  const onAgentsRef = useRef(onAgents)
  const onMetricsRef = useRef(onMetrics)
  const onAgentUpdateRef = useRef(onAgentUpdate)
  const onAgentOfflineRef = useRef(onAgentOffline)
  const onSummaryRef = useRef(onSummary)
  
  // Update refs when callbacks change
  useEffect(() => {
    onAgentsRef.current = onAgents
    onMetricsRef.current = onMetrics
    onAgentUpdateRef.current = onAgentUpdate
    onAgentOfflineRef.current = onAgentOffline
    onSummaryRef.current = onSummary
  }, [onAgents, onMetrics, onAgentUpdate, onAgentOffline, onSummary])

  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current)
      reconnectTimeoutRef.current = null
    }
    if (pingIntervalRef.current) {
      clearInterval(pingIntervalRef.current)
      pingIntervalRef.current = null
    }
    if (wsRef.current) {
      wsRef.current.close(1000, 'User disconnect')
      wsRef.current = null
    }
    setStatus('disconnected')
  }, [])

  const connect = useCallback(() => {
    if (!token) {
      setStatus('disconnected')
      return
    }

    // Clean up existing connection
    if (wsRef.current) {
      wsRef.current.close()
    }

    setStatus('connecting')

    // Build WebSocket URL
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const host = window.location.host
    const wsUrl = `${protocol}//${host}/ws/dashboard?token=${encodeURIComponent(token)}`

    console.log('[WS] Connecting to:', wsUrl)
    const ws = new WebSocket(wsUrl)
    wsRef.current = ws

    ws.onopen = () => {
      console.log('[WS] Dashboard WebSocket connected')
      setStatus('connected')

      // Start ping interval to keep connection alive
      pingIntervalRef.current = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'ping', timestamp: Date.now() }))
        }
      }, 30000)
    }

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data) as DashboardMessage

        switch (msg.type) {
          case 'agents':
            if (onAgentsRef.current && Array.isArray(msg.data)) {
              onAgentsRef.current(msg.data as Agent[])
            }
            break

          case 'metrics':
            if (onMetricsRef.current && typeof msg.data === 'object' && msg.data !== null) {
              // Handle both full metrics update and single-agent update
              const data = msg.data as Record<string, unknown>
              if ('agentId' in data && 'metrics' in data) {
                // Single agent metrics update
                const agentId = data.agentId as string
                const metrics = data.metrics as Metrics
                onMetricsRef.current({ [agentId]: metrics })
              } else {
                // Full metrics update
                onMetricsRef.current(data as Record<string, Metrics>)
              }
            }
            break

          case 'agent_update':
            if (onAgentUpdateRef.current && typeof msg.data === 'object' && msg.data !== null) {
              const agent = msg.data as Agent
              onAgentUpdateRef.current(agent.id, agent)
            }
            break

          case 'agent_offline':
            if (onAgentOfflineRef.current && typeof msg.data === 'string') {
              onAgentOfflineRef.current(msg.data)
            }
            break

          case 'summary':
            if (onSummaryRef.current && typeof msg.data === 'object') {
              onSummaryRef.current(msg.data as Summary)
            }
            break

          case 'pong':
            // Heartbeat response, ignore
            break
        }
      } catch (e) {
        console.error('[WS] Failed to parse message:', e)
      }
    }

    ws.onerror = (error) => {
      console.error('[WS] WebSocket error:', error)
      setStatus('error')
    }

    ws.onclose = (event) => {
      console.log('[WS] WebSocket closed:', event.code, event.reason)
      setStatus('disconnected')

      // Clear ping interval
      if (pingIntervalRef.current) {
        clearInterval(pingIntervalRef.current)
        pingIntervalRef.current = null
      }

      // Attempt to reconnect if not intentionally closed
      if (token && event.code !== 1000) {
        reconnectTimeoutRef.current = setTimeout(() => {
          console.log('[WS] Attempting to reconnect...')
          connect()
        }, reconnectInterval)
      }
    }
  }, [token, reconnectInterval]) // Only depend on token and reconnectInterval

  // Connect when token changes
  useEffect(() => {
    if (token) {
      connect()
    } else {
      disconnect()
    }

    return () => {
      disconnect()
    }
  }, [token]) // Only depend on token, not connect/disconnect

  return {
    status,
    connect,
    disconnect,
  }
}
