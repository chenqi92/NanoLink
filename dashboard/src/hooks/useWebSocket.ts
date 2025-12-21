import { useState, useEffect, useCallback, useRef } from 'react'
import type { Agent, Metrics } from '@/types/metrics'

interface UseWebSocketReturn {
  agents: Record<string, Agent>
  selectedAgentId: string | null
  selectAgent: (id: string) => void
  connected: boolean
}

// Transform API metrics to dashboard format
function transformMetrics(metrics: Record<string, unknown>): Metrics {
  const cpu = (metrics.cpu || {}) as Record<string, unknown>
  const memory = (metrics.memory || {}) as Record<string, unknown>
  
  return {
    timestamp: new Date(metrics.timestamp as string).getTime(),
    cpu: {
      usagePercent: (cpu.usagePercent as number) || 0,
      coreCount: (cpu.coreCount as number) || 0,
      perCoreUsage: (cpu.perCoreUsage as number[]) || [],
      model: (cpu.model as string) || '',
      vendor: (cpu.vendor as string) || '',
      frequencyMhz: (cpu.frequencyMhz as number) || 0,
      frequencyMaxMhz: (cpu.frequencyMaxMhz as number) || 0,
      physicalCores: (cpu.physicalCores as number) || 0,
      logicalCores: (cpu.logicalCores as number) || 0,
      architecture: (cpu.architecture as string) || '',
      temperature: (cpu.temperature as number) || 0,
    },
    memory: {
      total: (memory.total as number) || 0,
      used: (memory.used as number) || 0,
      available: (memory.available as number) || 0,
      usagePercent: (memory.usagePercent as number) || 0,
      swapTotal: (memory.swapTotal as number) || 0,
      swapUsed: (memory.swapUsed as number) || 0,
      cached: (memory.cached as number) || 0,
      buffers: (memory.buffers as number) || 0,
      memoryType: (memory.memoryType as string) || '',
      memorySpeedMhz: (memory.memorySpeedMhz as number) || 0,
    },
    disks: ((metrics.disks as Record<string, unknown>[]) || []).map(d => ({
      mountPoint: (d.mountPoint as string) || '',
      device: (d.device as string) || '',
      fsType: (d.fsType as string) || '',
      total: (d.total as number) || 0,
      used: (d.used as number) || 0,
      available: (d.available as number) || 0,
      usagePercent: (d.usagePercent as number) || 0,
      readBytesPerSec: (d.readBytesPerSec as number) || 0,
      writeBytesPerSec: (d.writeBytesPerSec as number) || 0,
      model: (d.model as string) || '',
      serial: (d.serial as string) || '',
      diskType: (d.diskType as string) || '',
      readIops: (d.readIops as number) || 0,
      writeIops: (d.writeIops as number) || 0,
      temperature: (d.temperature as number) || 0,
      healthStatus: (d.healthStatus as string) || '',
    })),
    networks: ((metrics.networks as Record<string, unknown>[]) || []).map(n => ({
      interface: (n.interfaceName as string) || '',
      rxBytesPerSec: (n.rxBytesPerSec as number) || 0,
      txBytesPerSec: (n.txBytesPerSec as number) || 0,
      rxPacketsPerSec: (n.rxPacketsPerSec as number) || 0,
      txPacketsPerSec: (n.txPacketsPerSec as number) || 0,
      isUp: (n.isUp as boolean) || false,
      macAddress: (n.macAddress as string) || '',
      ipAddresses: (n.ipAddresses as string[]) || [],
      speedMbps: (n.speedMbps as number) || 0,
      interfaceType: (n.interfaceType as string) || '',
    })),
    gpus: ((metrics.gpus as Record<string, unknown>[]) || []).map(g => ({
      index: (g.index as number) || 0,
      name: (g.name as string) || '',
      vendor: (g.vendor as string) || '',
      usagePercent: (g.usagePercent as number) || 0,
      memoryTotal: (g.memoryTotal as number) || 0,
      memoryUsed: (g.memoryUsed as number) || 0,
      temperature: (g.temperature as number) || 0,
      fanSpeedPercent: (g.fanSpeedPercent as number) || 0,
      powerWatts: (g.powerWatts as number) || 0,
      powerLimitWatts: (g.powerLimitWatts as number) || 0,
      clockCoreMhz: (g.clockCoreMhz as number) || 0,
      clockMemoryMhz: (g.clockMemoryMhz as number) || 0,
      driverVersion: (g.driverVersion as string) || '',
      pcieGeneration: (g.pcieGeneration as string) || '',
      encoderUsage: (g.encoderUsage as number) || 0,
      decoderUsage: (g.decoderUsage as number) || 0,
    })),
    npus: ((metrics.npus as Record<string, unknown>[]) || []).map(n => ({
      index: (n.index as number) || 0,
      name: (n.name as string) || '',
      vendor: (n.vendor as string) || '',
      usagePercent: (n.usagePercent as number) || 0,
      memoryTotal: (n.memoryTotal as number) || 0,
      memoryUsed: (n.memoryUsed as number) || 0,
      temperature: (n.temperature as number) || 0,
      powerWatts: (n.powerWatts as number) || 0,
      driverVersion: (n.driverVersion as string) || '',
    })),
    userSessions: ((metrics.userSessions as Record<string, unknown>[]) || []).map(s => ({
      username: (s.username as string) || '',
      tty: (s.tty as string) || '',
      loginTime: (s.loginTime as number) || 0,
      remoteHost: (s.remoteHost as string) || '',
      idleSeconds: (s.idleSeconds as number) || 0,
      sessionType: (s.sessionType as string) || '',
    })),
    loadAverage: (metrics.loadAverage as number[]) || [0, 0, 0],
    systemInfo: metrics.systemInfo ? {
      osName: ((metrics.systemInfo as Record<string, unknown>).osName as string) || '',
      osVersion: ((metrics.systemInfo as Record<string, unknown>).osVersion as string) || '',
      kernelVersion: ((metrics.systemInfo as Record<string, unknown>).kernelVersion as string) || '',
      hostname: ((metrics.systemInfo as Record<string, unknown>).hostname as string) || '',
      bootTime: ((metrics.systemInfo as Record<string, unknown>).bootTime as number) || 0,
      uptimeSeconds: ((metrics.systemInfo as Record<string, unknown>).uptimeSeconds as number) || 0,
      motherboardModel: ((metrics.systemInfo as Record<string, unknown>).motherboardModel as string) || '',
      motherboardVendor: ((metrics.systemInfo as Record<string, unknown>).motherboardVendor as string) || '',
      biosVersion: ((metrics.systemInfo as Record<string, unknown>).biosVersion as string) || '',
      systemModel: ((metrics.systemInfo as Record<string, unknown>).systemModel as string) || '',
      systemVendor: ((metrics.systemInfo as Record<string, unknown>).systemVendor as string) || '',
    } : null,
  }
}

export function useWebSocket(): UseWebSocketReturn {
  const [agents, setAgents] = useState<Record<string, Agent>>({})
  const [selectedAgentId, setSelectedAgentId] = useState<string | null>(null)
  const [connected, setConnected] = useState(false)
  const wsRef = useRef<WebSocket | null>(null)
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const initialFetchDone = useRef(false)

  const fetchInitialData = useCallback(async () => {
    try {
      const agentsResponse = await fetch('/api/agents')
      const agentsData = await agentsResponse.json()
      
      const newAgents: Record<string, Agent> = {}
      if (agentsData.agents) {
        agentsData.agents.forEach((agent: Record<string, unknown>) => {
          newAgents[agent.agentId as string] = {
            agentId: agent.agentId as string,
            hostname: agent.hostname as string,
            os: agent.os as string,
            arch: agent.arch as string,
            version: agent.version as string,
            lastMetrics: null,
          }
        })
      }

      // Fetch metrics
      const metricsResponse = await fetch('/api/metrics')
      const metricsMap = await metricsResponse.json()
      
      Object.entries(metricsMap).forEach(([agentId, metrics]) => {
        if (newAgents[agentId]) {
          newAgents[agentId].lastMetrics = transformMetrics(metrics as Record<string, unknown>)
        }
      })

      setAgents(newAgents)
      
      // Auto-select first agent
      const firstAgentId = Object.keys(newAgents)[0]
      if (firstAgentId && !selectedAgentId) {
        setSelectedAgentId(firstAgentId)
      }
    } catch (error) {
      console.error('[WebSocket] Failed to fetch initial data:', error)
    }
  }, [selectedAgentId])

  const connect = useCallback(() => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/ws`
    
    const ws = new WebSocket(wsUrl)
    wsRef.current = ws

    ws.onopen = () => {
      setConnected(true)
      if (reconnectTimerRef.current) {
        clearTimeout(reconnectTimerRef.current)
        reconnectTimerRef.current = null
      }
      if (!initialFetchDone.current) {
        fetchInitialData()
        initialFetchDone.current = true
      }
    }

    ws.onclose = () => {
      setConnected(false)
      reconnectTimerRef.current = setTimeout(connect, 3000)
    }

    ws.onerror = (error) => {
      console.error('[WebSocket] Error:', error)
    }

    ws.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data)
        
        if (message.type === 'metrics') {
          setAgents(prev => {
            if (!prev[message.agentId]) return prev
            return {
              ...prev,
              [message.agentId]: {
                ...prev[message.agentId],
                lastMetrics: transformMetrics(message.metrics),
              }
            }
          })
        } else if (message.type === 'agent_connect') {
          const agent = message.agent
          setAgents(prev => ({
            ...prev,
            [agent.agentId]: {
              agentId: agent.agentId,
              hostname: agent.hostname,
              os: agent.os,
              arch: agent.arch,
              version: agent.version,
              lastMetrics: null,
            }
          }))
        } else if (message.type === 'agent_disconnect') {
          setAgents(prev => {
            const updated = { ...prev }
            delete updated[message.agent.agentId]
            return updated
          })
        }
      } catch (error) {
        console.error('[WebSocket] Failed to parse message:', error)
      }
    }

    // Fetch data even if WebSocket fails
    setTimeout(() => {
      if (!initialFetchDone.current) {
        fetchInitialData()
        initialFetchDone.current = true
      }
    }, 1000)
  }, [fetchInitialData])

  useEffect(() => {
    connect()
    return () => {
      wsRef.current?.close()
      if (reconnectTimerRef.current) {
        clearTimeout(reconnectTimerRef.current)
      }
    }
  }, [connect])

  const selectAgent = useCallback((id: string) => {
    setSelectedAgentId(id)
  }, [])

  return { agents, selectedAgentId, selectAgent, connected }
}
