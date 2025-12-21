const API_BASE = "/api"

export interface ApiError {
  error: string
  status: number
}

class ApiClient {
  private token: string | null = null

  setToken(token: string | null) {
    this.token = token
    if (token) {
      localStorage.setItem("nanolink_token", token)
    } else {
      localStorage.removeItem("nanolink_token")
    }
  }

  getToken(): string | null {
    if (!this.token) {
      this.token = localStorage.getItem("nanolink_token")
    }
    return this.token
  }

  private getHeaders(): HeadersInit {
    const headers: HeadersInit = {
      "Content-Type": "application/json",
    }
    const token = this.getToken()
    if (token) {
      headers["Authorization"] = `Bearer ${token}`
    }
    return headers
  }

  async fetch<T>(url: string, options: RequestInit = {}): Promise<T> {
    const response = await fetch(`${API_BASE}${url}`, {
      ...options,
      headers: {
        ...this.getHeaders(),
        ...options.headers,
      },
    })

    if (response.status === 401) {
      this.setToken(null)
      window.location.href = "/"
      throw { error: "Authentication required", status: 401 } as ApiError
    }

    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      throw { error: data.error || "Request failed", status: response.status } as ApiError
    }

    return response.json()
  }

  async get<T>(url: string): Promise<T> {
    return this.fetch<T>(url)
  }

  async post<T>(url: string, body?: unknown): Promise<T> {
    return this.fetch<T>(url, {
      method: "POST",
      body: body ? JSON.stringify(body) : undefined,
    })
  }

  async put<T>(url: string, body?: unknown): Promise<T> {
    return this.fetch<T>(url, {
      method: "PUT",
      body: body ? JSON.stringify(body) : undefined,
    })
  }

  async delete<T>(url: string): Promise<T> {
    return this.fetch<T>(url, { method: "DELETE" })
  }
}

export const api = new ApiClient()

// Auth API
export interface LoginRequest {
  username: string
  password: string
}

export interface RegisterRequest {
  username: string
  password: string
  email?: string
}

export interface AuthResponse {
  token: string
  user: User
}

export interface User {
  id: number
  username: string
  email?: string
  isSuperAdmin: boolean
  createdAt: string
}

// Agent types
export interface Agent {
  id: string
  hostname: string
  os: string
  arch: string
  version: string
  connectedAt: string
  lastHeartbeat: string
  permission: number
}

// Metrics types
export interface Metrics {
  agentId: string
  timestamp: string
  cpu: CpuMetrics
  memory: MemoryMetrics
  disks: DiskMetrics[]
  networks: NetworkMetrics[]
  gpus: GpuMetrics[]
  npus: NpuMetrics[]
  userSessions: UserSession[]
  systemInfo?: SystemInfo
  loadAverage: number[]
}

export interface CpuMetrics {
  usagePercent: number
  coreCount: number
  perCoreUsage: number[]
  loadAverage: number[]
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

export interface Summary {
  connectedAgents: number
  avgCpuPercent: number
  memoryPercent: number
  totalMemory: number
  usedMemory: number
}

// API endpoints
export const authApi = {
  login: (data: LoginRequest) => api.post<AuthResponse>("/auth/login", data),
  register: (data: RegisterRequest) => api.post<AuthResponse>("/auth/register", data),
  me: () => api.get<User>("/auth/me"),
}

export const agentsApi = {
  list: () => api.get<Agent[]>("/agents"),
  get: (id: string) => api.get<Agent>(`/agents/${id}`),
  sendCommand: (id: string, command: string) =>
    api.post<{ status: string }>(`/agents/${id}/command`, { type: "shell", command }),
}

export const metricsApi = {
  all: () => api.get<Record<string, Metrics>>("/metrics"),
  get: (agentId: string) => api.get<Metrics>(`/agents/${agentId}/metrics`),
  summary: () => api.get<Summary>("/summary"),
}

export const usersApi = {
  list: () => api.get<User[]>("/users"),
  delete: (id: number) => api.delete(`/users/${id}`),
}
