// sampledata.ts — PREVIEW data for views whose live result channel is a backend TODO
// (operations / logs / alerts). These illustrate the design; they are clearly
// surfaced as preview data in the UI. Ported from design/nanolink/data-ops.jsx.

export interface AlertItem {
  id: string
  level: "crit" | "warn" | "info"
  title: string
  desc: string
  agent: string
  rule: string
  since: string
  ack: boolean
  ackBy?: string
  runbook?: string
}

export interface AlertRule {
  id: string
  name: string
  expr: string
  scope: string
  enabled: boolean
  severity: "crit" | "warn" | "info"
  channels: string[]
  lastFired: string
}

export interface NotifyChannel {
  id: string
  kind: string
  name: string
  target: string
  status: "ok" | "warn" | "crit"
  lastUsed: string
}

export interface LogLine {
  ts: string
  level: "info" | "warn" | "error" | "debug"
  src: string
  msg: string
  crit?: boolean
}

export interface PackageItem {
  name: string
  current: string
  latest: string | null
  security: boolean
  size: string
}

export interface ScriptItem {
  id: string
  name: string
  desc: string
  lang: string
  lines: number
  author: string
  lastRun: string
  lastResult: string
  scope: string
  danger?: boolean
}

export interface ConfigItem {
  path: string
  agent: string
  size: string
  mtime: string
  versions: number
  last: string
  validated: boolean
  warn?: string
}

export interface HealthCheck {
  id: string
  name: string
  target: string
  kind: string
  interval: string
  status: "ok" | "warn" | "crit"
  latency: string
  lastFail: string
}

export const SAMPLE_ALERTS: AlertItem[] = [
  { id: "al01", level: "crit", title: "db-primary-2 memory pressure", desc: "Used 91% · swap rising 1.8 → 2.4 GiB · 12 min", agent: "db-primary-2", rule: "mem.used > 90%", since: "12m", ack: false, runbook: "https://runbook/db-mem" },
  { id: "al02", level: "crit", title: "rpi-monitor-7 offline", desc: "Last heartbeat 3h 12m ago · previously reported memory pressure", agent: "rpi-monitor-7", rule: "agent.heartbeat > 30s", since: "3h 12m", ack: false },
  { id: "al03", level: "warn", title: "/var/lib/postgresql at 93%", desc: "At current write rate, ~4 days remaining · archive WAL", agent: "db-primary-2", rule: "disk.use > 90%", since: "14m", ack: true, ackBy: "priya.r" },
  { id: "al04", level: "warn", title: "ml-train-04 GPU 0 sustained load", desc: "H100 util 96% · 38 min · VRAM 96%", agent: "ml-train-04", rule: "gpu.use > 90% for 30m", since: "38m", ack: false },
  { id: "al05", level: "warn", title: "web-edge-12 / at 88%", desc: "Alpine root partition 88% · crossed 80% threshold", agent: "web-edge-12", rule: "disk.use > 85%", since: "2h", ack: true, ackBy: "marco.silva" },
  { id: "al06", level: "info", title: "New agent joined: edge-nyc-04", desc: "Handshaking · token verified · syncing config", agent: "edge-nyc-04", rule: "agent.joined", since: "44s", ack: false },
  { id: "al07", level: "warn", title: "edge-sgp-01 CPU avg 87%", desc: "5-min moving average above threshold · A100 inference busy", agent: "edge-sgp-01", rule: "cpu.avg5m > 85%", since: "26m", ack: true, ackBy: "alice.zhao" },
]

export const SAMPLE_ALERT_RULES: AlertRule[] = [
  { id: "r1", name: "Sustained high CPU", expr: "cpu.use > 85% for 5m", scope: "all prod", enabled: true, severity: "warn", channels: ["slack", "email"], lastFired: "26m ago" },
  { id: "r2", name: "Memory near exhaustion", expr: "mem.use > 90%", scope: "db-*", enabled: true, severity: "crit", channels: ["slack", "pagerduty"], lastFired: "12m ago" },
  { id: "r3", name: "Disk usage", expr: "disk.use > 85%", scope: "all", enabled: true, severity: "warn", channels: ["slack"], lastFired: "14m ago" },
  { id: "r4", name: "Sustained GPU load", expr: "gpu.use > 90% for 30m", scope: "ml-* / edge-jetson-*", enabled: true, severity: "warn", channels: ["slack"], lastFired: "38m ago" },
  { id: "r5", name: "Agent offline", expr: "agent.heartbeat > 30s", scope: "all", enabled: true, severity: "crit", channels: ["slack", "pagerduty", "email"], lastFired: "3h ago" },
  { id: "r9", name: "Privilege escalation attempts", expr: "audit.error = 'permission denied' > 3/h", scope: "global", enabled: true, severity: "crit", channels: ["slack", "email"], lastFired: "1h ago" },
]

export const SAMPLE_CHANNELS: NotifyChannel[] = [
  { id: "c1", kind: "slack", name: "#ops-alerts", target: "hooks.slack.com/T01...", status: "ok", lastUsed: "12m ago" },
  { id: "c2", kind: "pagerduty", name: "Primary on-call", target: "PagerDuty service: ABCDE12", status: "ok", lastUsed: "3h ago" },
  { id: "c3", kind: "email", name: "Ops mailing list", target: "ops@nano.io", status: "ok", lastUsed: "1h ago" },
  { id: "c4", kind: "webhook", name: "Internal incident bot", target: "https://incidents.nano.io/hook", status: "warn", lastUsed: "yesterday" },
  { id: "c5", kind: "sms", name: "Critical SMS", target: "+1-555-0188 (Twilio)", status: "ok", lastUsed: "—" },
]

export const SAMPLE_LOGS: LogLine[] = [
  { ts: "14:32:18.412", level: "info", src: "nginx", msg: '10.0.4.18 "GET /api/agents HTTP/2.0" 200 2412 "-" "nanolink-go-client/0.9.4"' },
  { ts: "14:32:18.488", level: "info", src: "nano-server", msg: "ws-dashboard: client subscribed agents=*" },
  { ts: "14:32:19.012", level: "info", src: "nginx", msg: '120.85.4.18 "GET /api/agents/agt_01HXK9P/metrics HTTP/2.0" 200 8412' },
  { ts: "14:32:19.142", level: "warn", src: "nano-server", msg: "db-primary-2: mem usage > 90% (91.2%) — trigger=mem-pressure-rule" },
  { ts: "14:32:19.144", level: "info", src: "nano-server", msg: "alert.fire id=al01 rule=mem-pressure agents=[db-primary-2]" },
  { ts: "14:32:19.222", level: "info", src: "notify", msg: "slack: posted to #ops-alerts (id=al01)" },
  { ts: "14:32:19.244", level: "info", src: "audit", msg: 'shell.exec user=alice.zhao agent=edge-sgp-01 cmd="docker logs nginx --tail 200" ok=true' },
  { ts: "14:32:19.314", level: "info", src: "grpc-stream", msg: "agt_01HXK9Q heartbeat ok seq=98412 lag=4ms" },
  { ts: "14:32:19.412", level: "info", src: "grpc-stream", msg: "agt_01HXK9P metrics-batch n=124 cpu_avg=87.4 mem_avg=71.2" },
  { ts: "14:32:19.512", level: "info", src: "audit", msg: "service.restart user=priya.r agent=db-primary-2 svc=postgresql.service ok=true" },
  { ts: "14:32:19.612", level: "info", src: "ws-shell", msg: "session opened user=alice.zhao agent=agt_01HXK9P pty=174x42" },
  { ts: "14:32:19.722", level: "error", src: "grpc-stream", msg: "agt_01HXK9W timeout — last_seen=3h12m ago — marking offline", crit: true },
  { ts: "14:32:19.788", level: "info", src: "notify", msg: "pagerduty: incident created id=PD-2026-0526-1432 severity=critical" },
  { ts: "14:32:20.011", level: "warn", src: "nano-server", msg: "ml-train-04: gpu0 use sustained 96% for 38m — trigger=gpu-sustained" },
  { ts: "14:32:20.122", level: "debug", src: "metrics", msg: "rollup: 1m → 5m bucket completed (124 series, 14ms)" },
]

export const SAMPLE_PACKAGES: PackageItem[] = [
  { name: "linux-image-6.8.0-49-generic", current: "6.8.0-49.49", latest: "6.8.0-50.50", security: true, size: "12.4 MB" },
  { name: "openssl", current: "3.0.13-0ubuntu3.4", latest: "3.0.13-0ubuntu3.5", security: true, size: "1.8 MB" },
  { name: "curl", current: "8.5.0-2ubuntu10.4", latest: "8.5.0-2ubuntu10.5", security: false, size: "262 KB" },
  { name: "docker-ce", current: "27.3.1", latest: "27.4.0", security: false, size: "88 MB" },
  { name: "postgresql-16", current: "16.4-1.pgdg22.04+1", latest: "16.5-1.pgdg22.04+1", security: false, size: "44 MB" },
  { name: "nginx", current: "1.27.1-1~jammy", latest: null, security: false, size: "1.2 MB" },
  { name: "openssh-server", current: "1:9.6p1-3ubuntu13.5", latest: "1:9.6p1-3ubuntu13.6", security: true, size: "488 KB" },
  { name: "systemd", current: "255.4-1ubuntu8.4", latest: "255.4-1ubuntu8.5", security: false, size: "4.2 MB" },
]

export const SAMPLE_SCRIPTS: ScriptItem[] = [
  { id: "sc1", name: "cleanup-old-logs.sh", desc: "Compress & archive logs older than 14 days", lang: "bash", lines: 42, author: "alice.zhao", lastRun: "2h ago", lastResult: "ok", scope: "all" },
  { id: "sc2", name: "rotate-postgres-wal.sh", desc: "Archive WAL to S3, prune local copies", lang: "bash", lines: 88, author: "priya.r", lastRun: "12h ago", lastResult: "ok", scope: "db-*" },
  { id: "sc3", name: "gpu-health-check.py", desc: "Check NVIDIA GPU temp / ECC / fallen-off-bus", lang: "python", lines: 124, author: "ml-trainer", lastRun: "1d ago", lastResult: "fail", scope: "ml-* / edge-jetson-*" },
  { id: "sc4", name: "renew-letsencrypt.sh", desc: "Renew certs + nginx reload", lang: "bash", lines: 22, author: "marco.silva", lastRun: "12d ago", lastResult: "ok", scope: "web-*" },
  { id: "sc5", name: "smartctl-report.sh", desc: "S.M.A.R.T health report to Slack", lang: "bash", lines: 64, author: "alice.zhao", lastRun: "44m ago", lastResult: "ok", scope: "all" },
  { id: "sc7", name: "k8s-drain-node.sh", desc: "K8s drain + cordon for maintenance", lang: "bash", lines: 18, author: "alice.zhao", lastRun: "—", lastResult: "—", scope: "all", danger: true },
]

export const SAMPLE_CONFIGS: ConfigItem[] = [
  { path: "/etc/nginx/nginx.conf", agent: "web-edge-12", size: "4.2 KB", mtime: "14m ago", versions: 12, last: "marco.silva", validated: true },
  { path: "/etc/postgresql/16/main/postgresql.conf", agent: "db-primary-2", size: "44 KB", mtime: "2h ago", versions: 8, last: "priya.r", validated: true },
  { path: "/etc/prometheus/prometheus.yml", agent: "edge-sgp-01", size: "1.8 KB", mtime: "1d ago", versions: 24, last: "marco.silva", validated: true },
  { path: "/etc/vector/vector.toml", agent: "edge-sgp-01", size: "8.4 KB", mtime: "3d ago", versions: 6, last: "alice.zhao", validated: false, warn: "vector restarted 4×" },
  { path: "/etc/wireguard/wg0.conf", agent: "edge-sgp-01", size: "812 B", mtime: "62d ago", versions: 2, last: "alice.zhao", validated: true },
  { path: "/etc/fail2ban/jail.local", agent: "web-edge-12", size: "2.4 KB", mtime: "7d ago", versions: 4, last: "marco.silva", validated: true },
]

export const SAMPLE_HEALTH: HealthCheck[] = [
  { id: "h1", name: "DB primary reachable", target: "db-primary-2:5432", kind: "tcp", interval: "30s", status: "ok", latency: "0.4 ms", lastFail: "—" },
  { id: "h2", name: "API /healthz", target: "https://api.nano.io/healthz", kind: "https", interval: "10s", status: "ok", latency: "12 ms", lastFail: "2 days ago" },
  { id: "h3", name: "Redis ping", target: "redis-cache:6379", kind: "tcp", interval: "30s", status: "ok", latency: "0.1 ms", lastFail: "—" },
  { id: "h4", name: "External: GitHub API", target: "https://api.github.com", kind: "https", interval: "1m", status: "warn", latency: "412 ms", lastFail: "44m ago" },
  { id: "h5", name: "DNS resolution", target: "cloudflare-dns 1.1.1.1", kind: "dns", interval: "1m", status: "ok", latency: "8 ms", lastFail: "—" },
  { id: "h7", name: "Loki ingester", target: "loki-edge:3100/ready", kind: "https", interval: "30s", status: "crit", latency: "—", lastFail: "now" },
  { id: "h8", name: "Cert: *.nano.io", target: "TLS cert expiry", kind: "tls", interval: "1h", status: "ok", latency: "expires in 112 days", lastFail: "—" },
]
