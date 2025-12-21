// Agent types
export interface Agent {
  agentId: string
  hostname: string
  os: string
  arch: string
  version: string
  lastMetrics: Metrics | null
}

// Metrics types
export interface Metrics {
  timestamp: number
  cpu: CpuMetrics
  memory: MemoryMetrics
  disks: DiskMetrics[]
  networks: NetworkMetrics[]
  gpus: GpuMetrics[]
  npus: NpuMetrics[]
  userSessions: UserSession[]
  loadAverage: number[]
  systemInfo: SystemInfo | null
}

export interface CpuMetrics {
  usagePercent: number
  coreCount: number
  perCoreUsage: number[]
  model: string
  vendor: string
  frequencyMhz: number
  frequencyMaxMhz: number
  physicalCores: number
  logicalCores: number
  architecture: string
  temperature: number
}

export interface MemoryMetrics {
  total: number
  used: number
  available: number
  usagePercent: number
  swapTotal: number
  swapUsed: number
  cached: number
  buffers: number
  memoryType: string
  memorySpeedMhz: number
}

export interface DiskMetrics {
  mountPoint: string
  device: string
  fsType: string
  total: number
  used: number
  available: number
  usagePercent: number
  readBytesPerSec: number
  writeBytesPerSec: number
  model: string
  serial: string
  diskType: string
  readIops: number
  writeIops: number
  temperature: number
  healthStatus: string
}

export interface NetworkMetrics {
  interface: string
  rxBytesPerSec: number
  txBytesPerSec: number
  rxPacketsPerSec: number
  txPacketsPerSec: number
  isUp: boolean
  macAddress: string
  ipAddresses: string[]
  speedMbps: number
  interfaceType: string
}

export interface GpuMetrics {
  index: number
  name: string
  vendor: string
  usagePercent: number
  memoryTotal: number
  memoryUsed: number
  temperature: number
  fanSpeedPercent: number
  powerWatts: number
  powerLimitWatts: number
  clockCoreMhz: number
  clockMemoryMhz: number
  driverVersion: string
  pcieGeneration: string
  encoderUsage: number
  decoderUsage: number
}

export interface NpuMetrics {
  index: number
  name: string
  vendor: string
  usagePercent: number
  memoryTotal: number
  memoryUsed: number
  temperature: number
  powerWatts: number
  driverVersion: string
}

export interface UserSession {
  username: string
  tty: string
  loginTime: number
  remoteHost: string
  idleSeconds: number
  sessionType: string
}

export interface SystemInfo {
  osName: string
  osVersion: string
  kernelVersion: string
  hostname: string
  bootTime: number
  uptimeSeconds: number
  motherboardModel: string
  motherboardVendor: string
  biosVersion: string
  systemModel: string
  systemVendor: string
}
