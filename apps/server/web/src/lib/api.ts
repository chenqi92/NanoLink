const API_BASE = "/api"

export interface ApiError {
  error: string
  status: number
  requiredLevel?: string
  [key: string]: unknown
}

export const SESSION_EXPIRED_EVENT = "nanolink:session-expired"

function apiError(payload: unknown, status: number, fallback: string): ApiError {
  const data = payload && typeof payload === "object" ? payload as Record<string, unknown> : {}
  return {
    ...data,
    error: typeof data.error === "string" && data.error ? data.error : fallback,
    status,
  }
}

function announceExpiredSession(url: string, payload?: unknown) {
  // Invalid credentials on the login/register forms are expected 401s. The
  // initial /me probe also runs before there is a known browser session.
  if (["/auth/login", "/auth/register", "/auth/me"].includes(url)) return
  const data = payload && typeof payload === "object" ? payload as Record<string, unknown> : {}
  if (url === "/auth/password" && data.error === "current password is incorrect") return
  if (typeof window !== "undefined") window.dispatchEvent(new Event(SESSION_EXPIRED_EVENT))
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
      const data = await response.json().catch(() => ({}))
      announceExpiredSession(url, data)
      throw apiError(data, 401, "Authentication required")
    }

    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      throw apiError(data, response.status, "Request failed")
    }

    return response.json()
  }

  async get<T>(url: string): Promise<T> {
    return this.fetch<T>(url)
  }

  async post<T>(url: string, body?: unknown, options: RequestInit = {}): Promise<T> {
    return this.fetch<T>(url, {
      ...options,
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

  async upload<T>(url: string, body: FormData): Promise<T> {
    const response = await fetch(`${API_BASE}${url}`, {
      method: "POST",
      body,
      credentials: "include",
    })
    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      if (response.status === 401) announceExpiredSession(url, data)
      throw apiError(data, response.status, "Upload failed")
    }
    return response.json()
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
  createdAt?: string
}

export interface BootstrapStatus {
  hasUsers: boolean
  registrationEnabled: boolean
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
  permissionLevel: number
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
  bootstrap: () => api.get<BootstrapStatus>("/auth/bootstrap"),
  login: (data: LoginRequest) => api.post<AuthResponse>("/auth/login", data),
  register: (data: RegisterRequest) => api.post<AuthResponse>("/auth/register", data),
  me: () => api.get<User>("/auth/me"),
  logout: () => api.post<{ message: string }>("/auth/logout"),
  changePassword: (currentPassword: string, newPassword: string) =>
    api.put<{ message: string }>("/auth/password", { currentPassword, newPassword }),
}

// Server info (public)
export interface ServerInfo {
  version: string
  serverUrl?: string
  wsUrl?: string
  grpcUrl?: string
  grpcPort?: number
  wsPort?: number
  agentHost?: string
  agentReleaseUrl?: string
  serverName?: string
  externalUrl?: string
  retentionDays?: number
  hourlyRetentionDays?: number
  dailyRetentionDays?: number
  tlsEnabled?: boolean
}
export const serverApi = {
  info: () => api.get<ServerInfo>("/server-info"),
  health: () => api.get<{ status: string; agentCount: number }>("/health"),
}

export interface ServerUpdateInfo {
  currentVersion: string
  latestVersion: string
  updateAvailable: boolean
  changelog?: string
  releaseDate?: string
  downloadUrl?: string
  source: string
  checkedAt: string
  deploymentMode: "docker" | "systemd" | "bare"
  canSelfUpdate: boolean
  blocker?: string
  upgradeCommand?: string
}

export const versionApi = {
  check: (refresh = false) => api.get<ServerUpdateInfo>(`/version/check${refresh ? "?refresh=true" : ""}`),
  apply: (expectVersion: string) => api.post<{ fromVersion: string; toVersion: string; restarting: boolean }>("/version/apply", { expectVersion }),
}

export const settingsApi = {
  get: () => api.get<Record<string, string>>("/settings"),
  update: (data: Record<string, string>) => api.put<Record<string, string>>("/settings", data),
}

export type LLMProvider =
  | "anthropic"
  | "openai"
  | "gemini"
  | "mistral"
  | "groq"
  | "openrouter"
  | "deepseek"
  | "zhipu"
  | "moonshot"
  | "qwen"
  | "minimax"
  | "baichuan"
  | "stepfun"
  | "siliconflow"
  | "hunyuan"
  | "ernie"
  | "openai-compatible"
export interface LLMSettings {
  enabled: boolean
  provider: LLMProvider
  model: string
  baseUrl: string
  maxTokens: number
  apiKeyConfigured: boolean
  apiKeySource: "stored" | "environment" | "none"
}
export interface LLMSettingsUpdate {
  enabled: boolean
  provider: LLMProvider
  model: string
  baseUrl: string
  maxTokens: number
  apiKey?: string
  clearApiKey?: boolean
}
export const llmSettingsApi = {
  get: () => api.get<LLMSettings>("/settings/llm"),
  update: (data: LLMSettingsUpdate) => api.put<LLMSettings>("/settings/llm", data),
  test: () => api.post<{ ok: boolean }>("/settings/llm/test"),
}

// Agent install config generation
export interface GeneratedConfig {
  configYaml: string
  installCommandUnix: string
  installCommandWindows: string
  generatedToken?: string
  serverId?: string
}

export type NASPlatform = "fnos" | "synology" | "ugos"
export type AgentArchitecture = "x86_64" | "arm64"
export type NASArchitecture = AgentArchitecture

export interface NASPackage {
  platform: NASPlatform
  arch: AgentArchitecture
  filename: string
  downloadUrl: string
  sha256?: string
}

export interface NASPackageManifest {
  version: string
  releaseUrl?: string
  packages: NASPackage[]
}

export const configApi = {
  generate: (body: { serverUrl?: string; token?: string; permission: number; tlsVerify: boolean; hostname?: string; shellEnabled: boolean; tlsCaCert?: string; tlsServerName?: string; tlsClientCert?: string; tlsClientKey?: string }) =>
    api.post<GeneratedConfig>("/config/generate", body),
  nasPackages: () => api.get<NASPackageManifest>("/config/nas-packages"),
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
  lastFiredAt?: string | null
}
export interface NotifyChannelModel {
  id: number
  kind: string
  name: string
  target: string
  enabled: boolean
  status?: string
  lastUsedAt?: string | null
}
export interface SilenceModel {
  id: number
  matcher: string
  reason?: string
  until: string
  createdBy?: string
  createdAt?: string
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
  testChannel: (id: number) => api.post(`/alerts/channels/${id}/test`),
  silences: () => api.get<SilenceModel[]>("/alerts/silences"),
  createSilence: (data: { matcher: string; reason?: string; durationMin: number }) => api.post("/alerts/silences", data),
  deleteSilence: (id: number) => api.delete(`/alerts/silences/${id}`),
}

// AI assistant findings (metric-derived) + optional external-LLM chat
export interface FindingDTO {
  kind: "anomaly" | "warn" | "info" | "ok"
  title: string
  detail: string
  agentId?: string
  actions: string[]
}
export interface ChatMessage {
  role: "user" | "assistant"
  content: string
}
export interface AssistantStatus {
  enabled: boolean
  configured: boolean
  provider: string
  model: string
}
export interface LLMProfile {
  id: number
  name: string
  provider: string
  model: string
  baseUrl: string
  maxTokens: number
  isActive: boolean
  apiKeyConfigured: boolean
  createdAt: string
  updatedAt: string
}

export interface ProviderInfo {
  id: string
  label: string
  defaultBaseUrl: string
  wire: string
  canListModels: boolean
  region: string
}

export interface ProviderModel {
  id: string
  displayName: string
}

export interface ChatResponse {
  reply: string
  model?: {
    profileId?: number
    profileName?: string
    provider: string
    model: string
  }
}

export interface McpToolDescriptor {
  name: string
  description: string
  inputSchema: Record<string, unknown>
}

export interface McpActivity {
  id: number
  toolName: string
  startedAt: string
  durationMs: number
  success: boolean
}

export interface McpOverview {
  enabled: boolean
  transport?: string
  state: "disabled" | "starting" | "running" | "stopped" | "unavailable"
  server: { name: string; version: string }
  protocolVersion: string
  tools: McpToolDescriptor[]
  activity: McpActivity[]
}

export interface LLMProfileInput {
  name: string
  provider: string
  model: string
  baseUrl?: string
  apiKey?: string
  maxTokens?: number
}

export const assistantApi = {
  findings: () => api.get<FindingDTO[]>("/assistant/findings"),
  status: () => api.get<AssistantStatus>("/assistant/status"),
  chat: (messages: ChatMessage[], profileId?: number, signal?: AbortSignal) => api.post<ChatResponse>("/assistant/chat", { messages, profileId }, { signal }),
  profiles: () => api.get<LLMProfile[]>("/assistant/profiles"),
}

export const mcpApi = {
  overview: () => api.get<McpOverview>("/mcp/overview"),
}

export const llmProfilesApi = {
  list: () => api.get<LLMProfile[]>("/settings/llm/profiles"),
  get: (id: number) => api.get<LLMProfile>(`/settings/llm/profiles/${id}`),
  create: (data: LLMProfileInput) => api.post<LLMProfile>("/settings/llm/profiles", data),
  update: (id: number, data: Partial<LLMProfileInput>) => api.put<LLMProfile>(`/settings/llm/profiles/${id}`, data),
  delete: (id: number) => api.delete(`/settings/llm/profiles/${id}`),
  activate: (id: number) => api.post(`/settings/llm/profiles/${id}/activate`),
  providers: () => api.get<{ providers: ProviderInfo[] }>("/settings/llm/providers"),
  listModels: (provider: string, baseURL?: string, apiKey?: string, profileId?: number) =>
    api.post<{ models: ProviderModel[] }>("/settings/llm/models", { provider, baseURL, apiKey, profileId }),
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
    return api.get<{ logs: AuditLog[]; total: number }>(`/audit/logs?${p.toString()}`)
  },
  stats: () => api.get<AuditStats>("/audit/stats"),
  recent: (limit = 50) => api.get<{ logs: AuditLog[] }>(`/audit/recent?limit=${limit}`),
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
  cpuPercent?: number
  memoryBytes?: number
  memoryLimit?: number
  ports?: string
  network?: string
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
export interface AgentServiceInfo {
  name: string
  status: string
  subState?: string
  description?: string
  uptime?: string
  restarts?: number
}
export interface AgentFileEntry {
  name: string
  isDir?: boolean
  size?: number
  modified?: number
}
export interface HealthCheckItemDTO {
  name: string
  passed: boolean
  message?: string
  durationMs?: number
}
export interface ConfigBackupDTO {
  path: string
  createdAt?: string
  size?: number
  checksum?: string
}
export interface AgentConfigResult {
  path?: string
  content?: string
  sanitized?: boolean
  valid?: boolean
  validationError?: string
  backups?: ConfigBackupDTO[]
}
export interface CommandResultData {
  commandId: string
  success: boolean
  output?: string
    error?: string
    /** Base64-encoded protobuf bytes, returned for chunked FILE_DOWNLOAD. */
    fileContent?: string
  processes?: AgentProcess[]
  containers?: AgentContainer[]
  packages?: AgentPackage[]
  scripts?: AgentScript[]
  services?: AgentServiceInfo[]
  files?: AgentFileEntry[]
  logResult?: AgentLogResult
  healthResult?: { healthy: boolean; checks?: HealthCheckItemDTO[] }
  configResult?: AgentConfigResult
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

// Application deployment
export interface DeploymentProject {
  id: number
  name: string
  type: "java" | "static"
  agentId: string
  targetId?: number | null
  deployPath: string
  extractArchive: boolean
  serviceName: string
  healthUrl: string
  keepReleases: number
  currentReleaseId?: string | null
  createdAt: string
  updatedAt: string
}

export interface DeploymentRelease {
  id: string
  projectId: number
  version: string
  artifactName: string
  keepArtifacts: number
  artifactSize: number
  sha256: string
  extract?: boolean
  stripTopLevel: boolean
  notes: string
  createdAt: string
}

export interface DeploymentTask {
  id: string
  projectId: number
  releaseId: string
  agentId: string
  commandId: string
  action: "deploy" | "rollback"
  status: "queued" | "running" | "success" | "failed"
  output: string
  error: string
  createdByName: string
  createdAt: string
  startedAt?: string
  finishedAt?: string
  release?: DeploymentRelease
  project?: DeploymentProject
}

export interface DeploymentProjectDetail extends DeploymentProject {
  releases: DeploymentRelease[]
  deployments: DeploymentTask[]
}

export interface DeploymentProjectInput {
  name: string
  type: "java" | "static"
  agentId: string
  targetId?: number | null
  deployPath: string
  extractArchive: boolean
  serviceName: string
  healthUrl: string
  keepReleases: number
}

export interface DeploymentUploadSession {
  id: string
  projectId: number
  version: string
  artifactName: string
  artifactSize: number
  uploadOffset: number
  chunkSize: number
  expiresAt: string
}

export interface DeploymentTarget {
  id: number
  name: string
  agentId: string
  host: string
  port: number
  username: string
  authType: "password" | "private_key"
  credentialConfigured: boolean
  sshKnownHosts?: string
  allowUnknownHost: boolean
  useSudo: boolean
  createdAt: string
  updatedAt: string
}

export interface DeploymentTargetInput {
  name: string
  agentId: string
  host: string
  port: number
  username: string
  authType: "password" | "private_key"
  credential: string
  sshKnownHosts: string
  allowUnknownHost: boolean
  useSudo: boolean
}

export interface EnvironmentScript {
  id: number
  name: string
  description: string
  targetId: number
  content?: string
  timeoutSeconds: number
  target?: DeploymentTarget
  createdAt: string
  updatedAt: string
}

export interface EnvironmentScriptInput {
  name: string
  description: string
  targetId: number
  content: string
  timeoutSeconds: number
}

export interface EnvironmentScriptRun {
  id: string
  scriptId: number
  targetId: number
  agentId: string
  commandId: string
  status: "queued" | "running" | "success" | "failed"
  output: string
  error: string
  createdAt: string
  startedAt?: string
  finishedAt?: string
  script?: EnvironmentScript
  target?: DeploymentTarget
}

async function deploymentUploadFetch<T>(url: string, options: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${url}`, { ...options, credentials: "include" })
  if (!response.ok) {
    const data = await response.json().catch(() => ({}))
    if (response.status === 401) announceExpiredSession(url, data)
    throw apiError(data, response.status, "Upload failed")
  }
  return response.json()
}

function retryDelay(attempt: number) {
  return new Promise((resolve) => window.setTimeout(resolve, Math.min(5000, 400 * 2 ** attempt)))
}

async function uploadDeploymentArtifact(
  projectId: number,
  version: string,
  notes: string,
  artifact: File,
  extract?: boolean,
  stripTopLevel = false,
  onProgress?: (uploaded: number, total: number) => void,
) {
  let session = await api.post<DeploymentUploadSession>(`/deployment-projects/${projectId}/upload-sessions`, {
    version,
    notes,
    artifactName: artifact.name,
    artifactSize: artifact.size,
    extract,
    stripTopLevel,
  })
  let offset = session.uploadOffset
  onProgress?.(offset, artifact.size)
  while (offset < artifact.size) {
    const end = Math.min(artifact.size, offset + session.chunkSize)
    let sent = false
    for (let attempt = 0; attempt < 5 && !sent; attempt++) {
      try {
        session = await deploymentUploadFetch<DeploymentUploadSession>(`/deployment-upload-sessions/${session.id}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/octet-stream", "Upload-Offset": String(offset) },
          body: artifact.slice(offset, end),
        })
        offset = session.uploadOffset
        sent = true
      } catch (error) {
        // The response may have been lost after the Server durably accepted the
        // chunk. Re-read the authoritative offset before retransmitting.
        try {
          session = await api.get<DeploymentUploadSession>(`/deployment-upload-sessions/${session.id}`)
          offset = session.uploadOffset
          if (offset >= end) sent = true
        } catch {
          // Preserve the original transfer error; the next retry may reconnect.
        }
        if (!sent) {
          if (attempt === 4) throw error
          await retryDelay(attempt)
        }
      }
    }
    onProgress?.(offset, artifact.size)
  }
  return api.post<DeploymentRelease>(`/deployment-upload-sessions/${session.id}/complete`)
}

export const deploymentsApi = {
  projects: () => api.get<DeploymentProject[]>("/deployment-projects"),
  project: (id: number) => api.get<DeploymentProjectDetail>(`/deployment-projects/${id}`),
  createProject: (body: DeploymentProjectInput) => api.post<DeploymentProject>("/deployment-projects", body),
  updateProject: (id: number, body: DeploymentProjectInput) => api.put<DeploymentProject>(`/deployment-projects/${id}`, body),
  uploadRelease: (projectId: number, version: string, notes: string, artifact: File, extract?: boolean, stripTopLevel = false, onProgress?: (uploaded: number, total: number) => void) =>
    uploadDeploymentArtifact(projectId, version, notes, artifact, extract, stripTopLevel, onProgress),
  uploadDirectory: (projectId: number, version: string, notes: string, files: File[]) => {
    const form = new FormData()
    form.set("version", version)
    form.set("notes", notes)
    form.set("uploadKind", "directory")
    form.set("extract", "true")
    for (const file of files) {
      form.append("files", file, file.name)
      form.append("paths", file.webkitRelativePath)
    }
    return api.upload<DeploymentRelease>(`/deployment-projects/${projectId}/releases`, form)
  },
  deploy: (projectId: number, releaseId: string) => api.post<DeploymentTask>(`/deployment-projects/${projectId}/releases/${releaseId}/deploy`),
  rollback: (projectId: number, releaseId: string) => api.post<DeploymentTask>(`/deployment-projects/${projectId}/releases/${releaseId}/rollback`),
  task: (taskId: string) => api.get<DeploymentTask>(`/deployment-tasks/${taskId}`),
  targets: () => api.get<DeploymentTarget[]>("/deployment-targets"),
  createTarget: (body: DeploymentTargetInput) => api.post<DeploymentTarget>("/deployment-targets", body),
  updateTarget: (id: number, body: DeploymentTargetInput) => api.put<DeploymentTarget>(`/deployment-targets/${id}`, body),
  deleteTarget: (id: number) => api.delete(`/deployment-targets/${id}`),
  environmentScripts: () => api.get<EnvironmentScript[]>("/environment-scripts"),
  environmentScript: (id: number) => api.get<EnvironmentScript>(`/environment-scripts/${id}`),
  createEnvironmentScript: (body: EnvironmentScriptInput) => api.post<EnvironmentScript>("/environment-scripts", body),
  updateEnvironmentScript: (id: number, body: EnvironmentScriptInput) => api.put<EnvironmentScript>(`/environment-scripts/${id}`, body),
  deleteEnvironmentScript: (id: number) => api.delete(`/environment-scripts/${id}`),
  runEnvironmentScript: (id: number) => api.post<EnvironmentScriptRun>(`/environment-scripts/${id}/run`),
  environmentScriptRun: (id: string) => api.get<EnvironmentScriptRun>(`/environment-script-runs/${id}`),
}

// Automated build pipelines
export interface BuildStage {
  id: string
  name: string
  command: string
  needs: string[]
  allowFailure: boolean
  timeoutSeconds: number
}

export interface BuildVariable {
  name: string
  value?: string
  secret: boolean
  required: boolean
}

export interface BuildSourceAuth {
  type: "none" | "basic" | "ssh"
  username?: string
  password?: string
  credentialConfigured?: boolean
  sshPublicKey?: string
  sshKnownHosts?: string
}

export interface BuildPipeline {
  id: number
  name: string
  description: string
  agentId: string
  sourceType: "git" | "url" | "upload"
  sourceUrl: string
  sourceRef: string
  sourceAuth: BuildSourceAuth
  runnerType: "docker" | "host"
  containerImage: string
  stages: BuildStage[]
  variables: BuildVariable[]
  artifactPattern: string
  artifactName: string
  keepArtifacts: number
  publishProjectId?: number | null
  timeoutSeconds: number
  schedule: string
  enabled: boolean
  webhookTokenHint?: string
  webhookToken?: string
  lastRunAt?: string
  createdAt: string
  updatedAt: string
  runs?: BuildRun[]
}

export type BuildPipelineInput = Omit<BuildPipeline, "id" | "createdAt" | "updatedAt" | "lastRunAt" | "runs" | "webhookToken" | "webhookTokenHint">

export interface BuildArtifact {
  id: string
  runId: string
  name: string
  size: number
  sha256: string
  deploymentReleaseId?: string | null
  createdAt: string
}

export interface BuildRun {
  id: string
  pipelineId: number
  runNumber: number
  agentId: string
  commandId: string
  status: "queued" | "running" | "success" | "failed" | "canceled"
  trigger: "manual" | "webhook" | "schedule"
  version: string
  sourceType: "git" | "url" | "upload"
  sourceUrl: string
  sourceRef: string
  sourceName: string
  sourceSize: number
  sourceSha256: string
  runnerType: "docker" | "host"
  containerImage: string
  artifactPattern: string
  artifactName: string
  publishProjectId?: number | null
  timeoutSeconds: number
  output: string
  error: string
  createdByName: string
  createdAt: string
  startedAt?: string
  finishedAt?: string
  artifact?: BuildArtifact
  pipeline?: BuildPipeline
}

export const buildsApi = {
  pipelines: () => api.get<BuildPipeline[]>("/build-pipelines"),
  pipeline: (id: number) => api.get<BuildPipeline>(`/build-pipelines/${id}`),
  createPipeline: (body: BuildPipelineInput) => api.post<BuildPipeline>("/build-pipelines", body),
  updatePipeline: (id: number, body: BuildPipelineInput) => api.put<BuildPipeline>(`/build-pipelines/${id}`, body),
  rotateWebhookToken: (id: number) => api.post<{ webhookToken: string; webhookTokenHint: string }>(`/build-pipelines/${id}/webhook-token`),
  rotateSshKey: (id: number) => api.post<BuildSourceAuth>(`/build-pipelines/${id}/ssh-key`),
  run: (id: number, version?: string) => api.post<BuildRun>(`/build-pipelines/${id}/run`, { version }),
  uploadAndRun: (id: number, version: string, source: File) => {
    const form = new FormData()
    form.set("version", version)
    form.set("source", source)
    return api.upload<BuildRun>(`/build-pipelines/${id}/upload-run`, form)
  },
  runs: (pipelineId?: number, limit = 50) => api.get<BuildRun[]>(`/build-runs?limit=${limit}${pipelineId ? `&pipelineId=${pipelineId}` : ""}`),
  runDetail: (id: string) => api.get<BuildRun>(`/build-runs/${id}`),
  cancelRun: (id: string) => api.post<BuildRun>(`/build-runs/${id}/cancel`),
  artifactDownloadUrl: (artifactId: string) => `/api/build-artifacts/${artifactId}/download`,
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

export interface AgentTokenList {
  items: AgentToken[]
  total: number
  online: number
  l3: number
  page: number
  pageSize: number
}

export const agentTokensApi = {
  list: (page = 1, pageSize = 100) =>
    api.get<AgentTokenList>(`/agent-tokens?page=${page}&pageSize=${pageSize}`),
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
  perm?: number
  scope?: string
  userCount?: number
  agents?: GroupAgentGrant[]
}

export interface GroupAgentGrant {
  agentId: string
  permissionLevel: number
}

export interface GroupDetail extends Group {
  users?: UserDetail[]
}

export const groupsApi = {
  list: () => api.get<Group[]>("/groups"),
  get: (id: number) => api.get<GroupDetail>(`/groups/${id}`),
  create: (data: { name: string; description?: string; perm?: number; agentIds?: string[] }) => api.post<Group>("/groups", data),
  update: (id: number, data: { name?: string; description?: string; perm?: number; agentIds?: string[] }) => api.put(`/groups/${id}`, data),
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
