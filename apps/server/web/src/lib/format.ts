// format.ts — formatting + tone helpers for the dashboard.

export type Tone = "ok" | "warn" | "crit" | ""

/** Tone class for a usage percentage (0-100). */
export function toneFor(pct: number): Tone {
  if (pct >= 90) return "crit"
  if (pct >= 75) return "warn"
  return ""
}

/** Tone for a temperature value (°C). */
export function tempTone(t: number): Tone {
  if (t >= 85) return "crit"
  if (t >= 70) return "warn"
  return ""
}

const UNITS = ["B", "KB", "MB", "GB", "TB", "PB"]

/** Human-readable byte count. */
export function formatBytes(bytes: number, digits = 1): string {
  if (!bytes || bytes < 0) return "0 B"
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), UNITS.length - 1)
  const v = bytes / Math.pow(1024, i)
  return `${v.toFixed(i === 0 ? 0 : digits)} ${UNITS[i]}`
}

/** Bytes/sec → human readable (e.g. "84.2 MB/s"). */
export function formatRate(bytesPerSec: number, digits = 1): string {
  return `${formatBytes(bytesPerSec, digits)}/s`
}

/** Bytes → GiB number (for compact GiB displays). */
export function toGiB(bytes: number): number {
  return bytes / 1024 ** 3
}

export function formatPercent(value: number, digits = 1): string {
  return `${(value ?? 0).toFixed(digits)}%`
}

/** Seconds → "47d 14h 22m". */
export function formatUptime(seconds: number): string {
  if (!seconds || seconds < 0) return "—"
  const d = Math.floor(seconds / 86400)
  const h = Math.floor((seconds % 86400) / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  if (d > 0) return `${d}d ${h}h ${m}m`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

/** Unix seconds → "12m ago" style relative time. */
export function timeAgo(unixSeconds: number): string {
  if (!unixSeconds) return "—"
  const now = Date.now() / 1000
  const diff = Math.max(0, now - unixSeconds)
  if (diff < 60) return `${Math.floor(diff)}s ago`
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
  return `${Math.floor(diff / 86400)}d ago`
}

/** ISO/RFC timestamp → relative time. */
export function timeAgoIso(iso: string): string {
  if (!iso) return "—"
  const t = new Date(iso).getTime()
  if (Number.isNaN(t)) return "—"
  return timeAgo(t / 1000)
}

/** Whether an agent is considered online (heartbeat < 60s). */
export function isOnline(lastHeartbeat: string): boolean {
  if (!lastHeartbeat) return false
  const t = new Date(lastHeartbeat).getTime()
  if (Number.isNaN(t)) return false
  return Date.now() - t < 60_000
}

export type AgentStatus = "online" | "offline" | "connecting"

export function agentStatus(lastHeartbeat: string): AgentStatus {
  return isOnline(lastHeartbeat) ? "online" : "offline"
}

/** Map a server OS string to an icon family. */
export function osFamily(os?: string): "linux" | "darwin" | "windows" {
  const s = (os || "").toLowerCase()
  if (s.includes("darwin") || s.includes("mac") || s.includes("apple") || s.includes("ios")) return "darwin"
  if (s.includes("win")) return "windows"
  return "linux"
}

export function clamp(v: number, lo = 0, hi = 100): number {
  return Math.max(lo, Math.min(hi, v))
}
