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
        // Create a new object to trigger Vue reactivity
        const updatedAgents = { ...agents.value }
        let hasUpdates = false
        Object.entries(metricsMap).forEach(([agentId, metrics]) => {
          if (updatedAgents[agentId]) {
            updatedAgents[agentId] = {
              ...updatedAgents[agentId],
              lastMetrics: transformMetrics(metrics)
            }
            hasUpdates = true
          }
        })
        // Only update if we have changes to avoid unnecessary reactivity
        if (hasUpdates) {
          agents.value = updatedAgents
        }
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

  // Transform API metrics to dashboard format with complete data
  const transformMetrics = (metrics) => {
    if (!metrics) return null

    const cpu = metrics.cpu || {}
    const memory = metrics.memory || {}

    return {
      timestamp: new Date(metrics.timestamp).getTime(),
      cpu: {
        usagePercent: cpu.usagePercent || 0,
        coreCount: cpu.coreCount || 0,
        perCoreUsage: cpu.perCoreUsage || [],
        model: cpu.model || '',
        vendor: cpu.vendor || '',
        frequencyMhz: cpu.frequencyMhz || 0,
        frequencyMaxMhz: cpu.frequencyMaxMhz || 0,
        physicalCores: cpu.physicalCores || 0,
        logicalCores: cpu.logicalCores || 0,
        architecture: cpu.architecture || '',
        temperature: cpu.temperature || 0
      },
      memory: {
        total: memory.total || 0,
        used: memory.used || 0,
        available: memory.available || 0,
        usagePercent: memory.usagePercent || 0,
        swapTotal: memory.swapTotal || 0,
        swapUsed: memory.swapUsed || 0,
        cached: memory.cached || 0,
        buffers: memory.buffers || 0,
        memoryType: memory.memoryType || '',
        memorySpeedMhz: memory.memorySpeedMhz || 0
      },
      disks: (metrics.disks || []).map(d => ({
        mountPoint: d.mountPoint,
        device: d.device,
        fsType: d.fsType,
        total: d.total,
        used: d.used,
        available: d.available,
        usagePercent: d.usagePercent,
        readBytesPerSec: d.readBytesPerSec || 0,
        writeBytesPerSec: d.writeBytesPerSec || 0,
        model: d.model || '',
        serial: d.serial || '',
        diskType: d.diskType || '',
        readIops: d.readIops || 0,
        writeIops: d.writeIops || 0,
        temperature: d.temperature || 0,
        healthStatus: d.healthStatus || ''
      })),
      networks: (metrics.networks || []).map(n => ({
        interface: n.interfaceName,
        rxBytesPerSec: n.rxBytesPerSec || 0,
        txBytesPerSec: n.txBytesPerSec || 0,
        rxPacketsPerSec: n.rxPacketsPerSec || 0,
        txPacketsPerSec: n.txPacketsPerSec || 0,
        isUp: n.isUp,
        macAddress: n.macAddress || '',
        ipAddresses: n.ipAddresses || [],
        speedMbps: n.speedMbps || 0,
        interfaceType: n.interfaceType || ''
      })),
      loadAverage: metrics.loadAverage || [0, 0, 0],
      systemInfo: metrics.systemInfo ? {
        osName: metrics.systemInfo.osName || '',
        osVersion: metrics.systemInfo.osVersion || '',
        kernelVersion: metrics.systemInfo.kernelVersion || '',
        hostname: metrics.systemInfo.hostname || '',
        bootTime: metrics.systemInfo.bootTime || 0,
        uptimeSeconds: metrics.systemInfo.uptimeSeconds || 0,
        motherboardModel: metrics.systemInfo.motherboardModel || '',
        motherboardVendor: metrics.systemInfo.motherboardVendor || '',
        biosVersion: metrics.systemInfo.biosVersion || '',
        systemModel: metrics.systemInfo.systemModel || '',
        systemVendor: metrics.systemInfo.systemVendor || ''
      } : null,
      gpus: (metrics.gpus || []).map(g => ({
        index: g.index,
        name: g.name || '',
        vendor: g.vendor || '',
        usagePercent: g.usagePercent || 0,
        memoryTotal: g.memoryTotal || 0,
        memoryUsed: g.memoryUsed || 0,
        temperature: g.temperature || 0,
        fanSpeedPercent: g.fanSpeedPercent || 0,
        powerWatts: g.powerWatts || 0,
        powerLimitWatts: g.powerLimitWatts || 0,
        clockCoreMhz: g.clockCoreMhz || 0,
        clockMemoryMhz: g.clockMemoryMhz || 0,
        driverVersion: g.driverVersion || '',
        pcieGeneration: g.pcieGeneration || '',
        encoderUsage: g.encoderUsage || 0,
        decoderUsage: g.decoderUsage || 0
      })),
      userSessions: (metrics.userSessions || []).map(s => ({
        username: s.username || '',
        tty: s.tty || '',
        loginTime: s.loginTime || 0,
        remoteHost: s.remoteHost || '',
        idleSeconds: s.idleSeconds || 0,
        sessionType: s.sessionType || ''
      })),
      npus: (metrics.npus || []).map(n => ({
        index: n.index,
        name: n.name || '',
        vendor: n.vendor || '',
        usagePercent: n.usagePercent || 0,
        memoryTotal: n.memoryTotal || 0,
        memoryUsed: n.memoryUsed || 0,
        temperature: n.temperature || 0,
        powerWatts: n.powerWatts || 0,
        driverVersion: n.driverVersion || ''
      }))
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
