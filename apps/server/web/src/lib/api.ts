const API_BASE = "/api"

export interface ApiError {
  error: string
  status: number
}

class ApiClient {
  private getHeaders(): HeadersInit {
    return {
      "Content-Type": "application/json",
    }
  }

  async fetch<T>(url: string, options: RequestInit = {}): Promise<T> {
    const response = await fetch(`${API_BASE}${url}`, {
      ...options,
      credentials: "include",
      headers: {
        ...this.getHeaders(),
        ...options.headers,
      },
    })

    if (response.status === 401) {
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
  diskPercent: number
  totalDisk: number
  usedDisk: number
}

// API endpoints
export const authApi = {
  login: (data: LoginRequest) => api.post<AuthResponse>("/auth/login", data),
  register: (data: RegisterRequest) => api.post<AuthResponse>("/auth/register", data),
  me: () => api.get<User>("/auth/me"),
  logout: () => api.post<{ message: string }>("/auth/logout"),
  changePassword: (newPassword: string) => api.put<{ message: string }>("/auth/password", { newPassword }),
}

// Server info (public)
export interface ServerInfo {
  version: string
  serverUrl?: string
  wsUrl?: string
  grpcPort?: number
  wsPort?: number
}
export const serverApi = {
  info: () => api.get<ServerInfo>("/server-info"),
  health: () => api.get<{ status: string; agentCount: number }>("/health"),
}

// Agent install config generation
export interface GeneratedConfig {
  configYaml: string
  installCommandUnix: string
  installCommandWindows: string
  generatedToken?: string
  serverId?: string
}
export const configApi = {
  generate: (body: { serverUrl?: string; permission: number; tlsVerify: boolean; hostname?: string; shellEnabled: boolean }) =>
    api.post<GeneratedConfig>("/config/generate", body),
}

// Audit
export interface AuditLog {
  id: number
  timestamp: string | number
  userId: number
  agentId: string
  commandId: string
  durationMs: number
  username: string
  agentHostname: string
  commandType: string
  target: string
  params: string
  success: boolean
  error?: string
  ipAddress: string
}
export interface AuditStats {
  totalCommands: number
  successRate: number
  topUsers?: { username: string; count: number }[]
  topAgents?: { hostname: string; count: number }[]
}
export interface AuditQuery {
  userId?: number
  agentId?: string
  commandType?: string
  success?: boolean
  limit?: number
  offset?: number
}
// Alerts
export interface AlertInstanceDTO {
  id: string
  level: "crit" | "warn" | "info"
  title: string
  desc: string
  agent: string
  rule: string
  since: string
  ack: boolean
  ackBy?: string
  value?: number
}
export interface AlertRuleModel {
  id: number
  name: string
  metric: string
  operator: string
  threshold: number
  durationSec: number
  severity: string
  scope: string
  enabled: boolean
}
export interface NotifyChannelModel {
  id: number
  kind: string
  name: string
  target: string
  enabled: boolean
}
export const alertsApi = {
  list: (status?: string) => api.get<AlertInstanceDTO[]>(`/alerts${status ? `?status=${status}` : ""}`),
  ack: (id: string) => api.post(`/alerts/ack/${id}`),
  rules: () => api.get<AlertRuleModel[]>("/alerts/rules"),
  createRule: (data: { name: string; metric: string; operator?: string; threshold?: number; severity?: string; scope?: string; enabled?: boolean }) => api.post("/alerts/rules", data),
  updateRule: (id: number, data: Record<string, unknown>) => api.put(`/alerts/rules/${id}`, data),
  deleteRule: (id: number) => api.delete(`/alerts/rules/${id}`),
  channels: () => api.get<NotifyChannelModel[]>("/alerts/channels"),
  createChannel: (data: { kind: string; name: string; target?: string }) => api.post("/alerts/channels", data),
  deleteChannel: (id: number) => api.delete(`/alerts/channels/${id}`),
}

export const auditApi = {
  logs: (q: AuditQuery = {}) => {
    const p = new URLSearchParams()
    if (q.userId != null) p.set("userId", String(q.userId))
    if (q.agentId) p.set("agentId", q.agentId)
    if (q.commandType) p.set("commandType", q.commandType)
    if (q.success != null) p.set("success", String(q.success))
    p.set("limit", String(q.limit ?? 100))
    if (q.offset) p.set("offset", String(q.offset))
    return api.get<{ data: AuditLog[]; total: number }>(`/audit/logs?${p.toString()}`)
  },
  stats: () => api.get<AuditStats>("/audit/stats"),
  recent: (limit = 50) => api.get<AuditLog[]>(`/audit/recent?limit=${limit}`),
}

export const agentsApi = {
  list: () => api.get<Agent[]>("/agents"),
  get: (id: string) => api.get<Agent>(`/agents/${id}`),
  sendCommand: (id: string, command: string) =>
    api.post<{ status: string }>(`/agents/${id}/command`, { type: "shell", command }),
}

// Structured command results (protojson camelCase) returned by the agent
export interface AgentProcess {
  pid: number
  name: string
  user: string
  cpuPercent: number
  memoryBytes: number
  status: string
  startTime: number
}
export interface AgentContainer {
  id: string
  name: string
  image: string
  status: string
  state: string
  created: string
}
export interface AgentPackage {
  name: string
  version: string
  description?: string
  architecture?: string
  installedSize?: number
  updateAvailable?: boolean
  newVersion?: string
  repository?: string
  packageManager?: string
}
export interface AgentLogEntry {
  timestamp?: string
  level?: string
  source?: string
  message: string
}
export interface AgentLogResult {
  lines?: AgentLogEntry[]
  totalLines?: number
  logSource?: string
}
export interface AgentScript {
  name: string
  description?: string
  category?: string
  requiredArgs?: string[]
  requiredPermission?: number
  fileSize?: number
  lastModified?: string
  signatureVerified?: boolean
}
export interface CommandResultData {
  commandId: string
  success: boolean
  output?: string
  error?: string
  processes?: AgentProcess[]
  containers?: AgentContainer[]
  packages?: AgentPackage[]
  scripts?: AgentScript[]
  logResult?: AgentLogResult
}

export const commandsApi = {
  send: (agentId: string, body: { type: string; target?: string; params?: Record<string, string> }) =>
    api.post<{ status: string; commandId: string }>(`/agents/${agentId}/command`, body),
  dataRequest: (agentId: string, requestType: string, target?: string) =>
    api.post<{ success: boolean; message?: string }>(`/agents/${agentId}/data-request`, { requestType, target }),
  result: (agentId: string, commandId: string) =>
    api.get<CommandResultData | { status: "pending" }>(`/agents/${agentId}/command/${commandId}/result`),
}

export const metricsApi = {
  all: () => api.get<Record<string, Metrics>>("/metrics"),
  get: (agentId: string) => api.get<Metrics>(`/agents/${agentId}/metrics`),
  summary: () => api.get<Summary>("/summary"),
  history: (agentId: string, start: number, end: number, interval: string) =>
    api.get<Metrics[]>(`/metrics/history?agentId=${agentId}&start=${start}&end=${end}&interval=${interval}`),
}

// Agent Token types and API
export interface AgentToken {
  id: number
  tokenHint: string
  name: string
  agentId?: string
  hostname?: string
  os?: string
  arch?: string
  version?: string
  lastIp?: string
  permission: number
  sortOrder: number
  isOnline: boolean
  createdAt: number
  firstSeenAt?: number
  lastSeenAt?: number
  expiresAt?: number
}

export interface CreateAgentTokenRequest {
  name: string
  permission: number
}

export interface CreateAgentTokenResponse extends AgentToken {
  token: string // Full token, only returned on creation
}

export const agentTokensApi = {
  list: () => api.get<AgentToken[]>("/agent-tokens"),
  create: (data: CreateAgentTokenRequest) => api.post<CreateAgentTokenResponse>("/agent-tokens", data),
  update: (id: number, data: { name: string; permission: number }) => api.put(`/agent-tokens/${id}`, data),
  delete: (id: number) => api.delete(`/agent-tokens/${id}`),
  regenerate: (id: number) => api.post<{ token: string }>(`/agent-tokens/${id}/regenerate`),
  reorder: (order: number[]) => api.put("/agent-tokens/reorder", { order }),
}

// ─── Users ─────────────────────────────────────────────────
export interface UserGroupRef {
  id: number
  name: string
}

export interface UserDetail extends User {
  groups?: UserGroupRef[]
}

export const usersApi = {
  list: () => api.get<UserDetail[]>("/users"),
  get: (id: number) => api.get<UserDetail>(`/users/${id}`),
  create: (data: { username: string; password: string; email?: string; groupIds?: number[] }) => api.post<UserDetail>("/users", data),
  update: (id: number, data: { email?: string; groupIds?: number[] }) => api.put(`/users/${id}`, data),
  delete: (id: number) => api.delete(`/users/${id}`),
  setPassword: (id: number, data: { newPassword: string; currentPassword?: string; forceChange?: boolean }) => api.put(`/users/${id}/password`, data),
}

// ─── Groups ────────────────────────────────────────────────
export interface Group {
  id: number
  name: string
  description?: string
  userCount?: number
}

export interface GroupDetail extends Group {
  users?: UserDetail[]
}

export const groupsApi = {
  list: () => api.get<Group[]>("/groups"),
  get: (id: number) => api.get<GroupDetail>(`/groups/${id}`),
  create: (data: { name: string; description?: string }) => api.post<Group>("/groups", data),
  update: (id: number, data: { name?: string; description?: string }) => api.put(`/groups/${id}`, data),
  delete: (id: number) => api.delete(`/groups/${id}`),
  addUser: (id: number, userId: number) => api.post(`/groups/${id}/users`, { userId }),
  removeUser: (id: number, userId: number) => api.delete(`/groups/${id}/users/${userId}`),
}

// ─── Devices ───────────────────────────────────────────────
export interface DeviceToken {
  id: number
  deviceName: string
  deviceType: string
  deviceOs: string
  permissionLevel: number
  isActive: boolean
  lastUsedAt?: string | number
  lastIp?: string
  createdBy?: number | string
  createdAt: string | number
}

export interface DevicePairing {
  qrData: string
  pairingCode: string
  device: DeviceToken
}

export const devicesApi = {
  list: () => api.get<DeviceToken[]>("/devices"),
  get: (id: number) => api.get<DeviceToken>(`/devices/${id}`),
  createToken: (serverName?: string) => api.post<DevicePairing>("/devices/token", { serverName }),
  update: (id: number, data: { deviceName?: string; permissionLevel?: number; isActive?: boolean }) =>
    api.fetch<DeviceToken>(`/devices/${id}`, { method: "PATCH", body: JSON.stringify(data) }),
  delete: (id: number) => api.delete(`/devices/${id}`),
}

// ─── Permissions ───────────────────────────────────────────
export interface UserPermission {
  agentId: string
  permissionLevel: number
}

export const permissionsApi = {
  forUser: (userId: number) => api.get<UserPermission[]>(`/permissions/${userId}`),
  set: (userId: number, agentId: string, permissionLevel: number) => api.post("/permissions", { userId, agentId, permissionLevel }),
  remove: (userId: number, agentId: string) => api.delete(`/permissions/${userId}/${agentId}`),
  check: (userId: number, agentId: string, requiredLevel: number) => api.post<{ canExecute: boolean; reason?: string }>("/permissions/check", { userId, agentId, requiredLevel }),
  assignAgentGroup: (agentId: string, groupId: number, permissionLevel: number) => api.post("/agents/groups", { agentId, groupId, permissionLevel }),
  removeAgentGroup: (agentId: string, groupId: number) => api.delete(`/agents/${agentId}/groups/${groupId}`),
}
