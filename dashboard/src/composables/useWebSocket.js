import { ref } from 'vue'

const connected = ref(false)
const agents = ref({})
const selectedAgent = ref(null)
let ws = null
let reconnectTimer = null
let initialFetchDone = false

export function useWebSocket() {
  const connect = () => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/ws`

    console.log('[WebSocket] Connecting to:', wsUrl)

    ws = new WebSocket(wsUrl)

    ws.onopen = () => {
      console.log('[WebSocket] Connected')
      connected.value = true
      if (reconnectTimer) {
        clearTimeout(reconnectTimer)
        reconnectTimer = null
      }

      // Fetch initial data once connected
      if (!initialFetchDone) {
        fetchInitialData()
        initialFetchDone = true
      }
    }

    ws.onclose = () => {
      console.log('[WebSocket] Disconnected')
      connected.value = false
      scheduleReconnect()
    }

    ws.onerror = (error) => {
      console.error('[WebSocket] Error:', error)
    }

    ws.onmessage = (event) => {
      handleMessage(event.data)
    }

    // Fetch initial data even if WebSocket fails
    setTimeout(() => {
      if (!initialFetchDone) {
        fetchInitialData()
        initialFetchDone = true
      }
    }, 1000)
  }

  const scheduleReconnect = () => {
    if (reconnectTimer) return
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null
      connect()
    }, 3000)
  }

  const handleMessage = (data) => {
    try {
      const message = JSON.parse(data)
      console.log('[WebSocket] Received:', message.type)

      switch (message.type) {
        case 'metrics':
          handleMetricsUpdate(message.agentId, message.metrics)
          break
        case 'agent_connect':
          handleAgentConnect(message.agent)
          break
        case 'agent_disconnect':
          handleAgentDisconnect(message.agent)
          break
        default:
          console.warn('[WebSocket] Unknown message type:', message.type)
      }
    } catch (error) {
      console.error('[WebSocket] Failed to parse message:', error)
    }
  }

  const handleMetricsUpdate = (agentId, metrics) => {
    if (!agents.value[agentId]) {
      console.warn('[WebSocket] Received metrics for unknown agent:', agentId)
      return
    }

    // Update agent metrics
    const updatedAgents = { ...agents.value }
    updatedAgents[agentId] = {
      ...updatedAgents[agentId],
      lastMetrics: transformMetrics(metrics)
    }
    agents.value = updatedAgents
  }

  const handleAgentConnect = (agent) => {
    console.log('[WebSocket] Agent connected:', agent.hostname)
    const updatedAgents = { ...agents.value }
    updatedAgents[agent.agentId] = {
      ...agent,
      lastMetrics: null
    }
    agents.value = updatedAgents

    // Auto-select if first agent
    if (!selectedAgent.value) {
      selectedAgent.value = agent.agentId
    }
  }

  const handleAgentDisconnect = (agent) => {
    console.log('[WebSocket] Agent disconnected:', agent.hostname)
    const updatedAgents = { ...agents.value }
    delete updatedAgents[agent.agentId]
    agents.value = updatedAgents

    // Deselect if this was the selected agent
    if (selectedAgent.value === agent.agentId) {
      const remaining = Object.keys(agents.value)
      selectedAgent.value = remaining.length > 0 ? remaining[0] : null
    }
  }

  const fetchInitialData = async () => {
    console.log('[WebSocket] Fetching initial data...')

    try {
      // Fetch agents
      const agentsResponse = await fetch('/api/agents')
      const agentsData = await agentsResponse.json()

      if (agentsData.agents) {
        const newAgents = {}
        agentsData.agents.forEach(agent => {
          newAgents[agent.agentId] = {
            ...agent,
            lastMetrics: null
          }
        })
        agents.value = newAgents

        // Auto-select first agent
        if (!selectedAgent.value && agentsData.agents.length > 0) {
          selectedAgent.value = agentsData.agents[0].agentId
          console.log('[WebSocket] Auto-selected agent:', selectedAgent.value)
        }
      }

      // Fetch initial metrics
      const metricsResponse = await fetch('/api/metrics')
      const metricsMap = await metricsResponse.json()

      const updatedAgents = { ...agents.value }
      Object.entries(metricsMap).forEach(([agentId, metrics]) => {
        if (updatedAgents[agentId]) {
          updatedAgents[agentId] = {
            ...updatedAgents[agentId],
            lastMetrics: transformMetrics(metrics)
          }
        }
      })
      agents.value = updatedAgents

      console.log('[WebSocket] Initial data loaded:', Object.keys(agents.value).length, 'agents')
    } catch (error) {
      console.error('[WebSocket] Failed to fetch initial data:', error)
    }
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

  const selectAgent = (agentId) => {
    console.log('[WebSocket] selectAgent:', agentId)
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
