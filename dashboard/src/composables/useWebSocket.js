import { ref, reactive } from 'vue'

const connected = ref(false)
const agents = ref({})
const selectedAgent = ref(null)
let ws = null
let reconnectTimer = null

export function useWebSocket() {
  const connect = () => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/ws`

    console.log('Connecting to WebSocket:', wsUrl)

    ws = new WebSocket(wsUrl)

    ws.onopen = () => {
      console.log('WebSocket connected')
      connected.value = true
      if (reconnectTimer) {
        clearTimeout(reconnectTimer)
        reconnectTimer = null
      }
    }

    ws.onclose = () => {
      console.log('WebSocket disconnected')
      connected.value = false
      scheduleReconnect()
    }

    ws.onerror = (error) => {
      console.error('WebSocket error:', error)
    }

    ws.onmessage = (event) => {
      handleMessage(event.data)
    }

    // Also poll API for agents
    pollAgents()
  }

  const scheduleReconnect = () => {
    if (reconnectTimer) return
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null
      connect()
    }, 3000)
  }

  const handleMessage = async (data) => {
    // Handle binary protobuf messages
    if (data instanceof Blob) {
      const buffer = await data.arrayBuffer()
      // Parse protobuf (simplified)
      // In production, use proper protobuf parsing
    }
  }

  const pollAgents = () => {
    const fetchAgents = async () => {
      try {
        const response = await fetch('/api/agents')
        const data = await response.json()
        if (data.agents) {
          const newAgents = {}
          data.agents.forEach(agent => {
            newAgents[agent.agentId] = {
              ...agent,
              lastMetrics: agents.value[agent.agentId]?.lastMetrics || null
            }
          })
          agents.value = newAgents

          // Auto-select first agent if none selected
          if (!selectedAgent.value && data.agents.length > 0) {
            selectedAgent.value = data.agents[0].agentId
          }
        }
      } catch (error) {
        console.error('Failed to fetch agents:', error)
      }
    }

    const fetchMetrics = async () => {
      try {
        const response = await fetch('/api/metrics')
        const metricsMap = await response.json()
        // metricsMap is { agentId: metrics }
        Object.entries(metricsMap).forEach(([agentId, metrics]) => {
          if (agents.value[agentId]) {
            agents.value[agentId].lastMetrics = transformMetrics(metrics)
          }
        })
      } catch (error) {
        console.error('Failed to fetch metrics:', error)
      }
    }

    fetchAgents()
    setInterval(fetchAgents, 5000)

    // Fetch real metrics from API
    fetchMetrics()
    setInterval(fetchMetrics, 2000)
  }

  // Transform API metrics to dashboard format
  const transformMetrics = (metrics) => {
    if (!metrics) return null
    return {
      timestamp: new Date(metrics.timestamp).getTime(),
      cpu: {
        usagePercent: metrics.cpuUsage || 0,
        coreCount: metrics.cpuCores || 0,
        perCoreUsage: []
      },
      memory: {
        total: metrics.memoryTotal || 0,
        used: metrics.memoryUsed || 0,
        available: (metrics.memoryTotal || 0) - (metrics.memoryUsed || 0),
        usagePercent: metrics.memoryUsage || 0
      },
      disks: (metrics.disks || []).map(d => ({
        mountPoint: d.mountPoint,
        device: d.device,
        total: d.total,
        used: d.used,
        usagePercent: d.usagePercent,
        readBytesPerSec: d.readBytesPerSec || 0,
        writeBytesPerSec: d.writeBytesPerSec || 0
      })),
      networks: (metrics.networks || []).map(n => ({
        interface: n.interfaceName,
        rxBytesPerSec: n.rxBytesPerSec || 0,
        txBytesPerSec: n.txBytesPerSec || 0,
        isUp: n.isUp
      })),
      loadAverage: metrics.loadAverage || [0, 0, 0]
    }
  }

  const generateDemoMetrics = () => ({
    timestamp: Date.now(),
    cpu: {
      usagePercent: 15 + Math.random() * 40,
      coreCount: 8,
      perCoreUsage: Array(8).fill(0).map(() => Math.random() * 100)
    },
    memory: {
      total: 16 * 1024 * 1024 * 1024,
      used: (6 + Math.random() * 4) * 1024 * 1024 * 1024,
      available: 8 * 1024 * 1024 * 1024,
      swapTotal: 8 * 1024 * 1024 * 1024,
      swapUsed: Math.random() * 1024 * 1024 * 1024
    },
    disks: [{
      mountPoint: '/',
      device: '/dev/sda1',
      fsType: 'ext4',
      total: 500 * 1024 * 1024 * 1024,
      used: (150 + Math.random() * 50) * 1024 * 1024 * 1024,
      available: 300 * 1024 * 1024 * 1024,
      readBytesPerSec: Math.random() * 50 * 1024 * 1024,
      writeBytesPerSec: Math.random() * 30 * 1024 * 1024
    }],
    networks: [{
      interface: 'eth0',
      rxBytesPerSec: Math.random() * 10 * 1024 * 1024,
      txBytesPerSec: Math.random() * 5 * 1024 * 1024,
      rxPacketsPerSec: Math.random() * 10000,
      txPacketsPerSec: Math.random() * 5000,
      isUp: true
    }],
    loadAverage: [1.5 + Math.random(), 1.2 + Math.random(), 0.8 + Math.random()]
  })

  const selectAgent = (agentId) => {
    selectedAgent.value = agentId
  }

  const sendCommand = async (agentId, command) => {
    // Send command via WebSocket
    // In production, properly serialize to protobuf
    console.log('Sending command to', agentId, command)
  }

  return {
    connected,
    agents,
    selectedAgent,
    connect,
    selectAgent,
    sendCommand
  }
}
