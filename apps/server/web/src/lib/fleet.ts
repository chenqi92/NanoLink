import { AGENT_ONLINE_WINDOW_MS } from "./format.ts"

export const DEPLOYMENT_STEPS = ["preflight", "download", "verify", "stage", "activate", "service", "health"] as const

interface FleetAgent {
  permissionLevel: number
  lastHeartbeat: string
}

interface SelectableAgent {
  id: string
  lastHeartbeat: string
}

export function isRecentlyOnline(lastHeartbeat: string, now = Date.now()): boolean {
  const timestamp = Date.parse(lastHeartbeat)
  return Number.isFinite(timestamp) && now - timestamp < AGENT_ONLINE_WINDOW_MS
}

export function eligibleFleetShellAgents<T extends FleetAgent>(agents: T[], now = Date.now()): T[] {
  return agents.filter((agent) => agent.permissionLevel >= 3 && isRecentlyOnline(agent.lastHeartbeat, now))
}

export function reconcileAgentSelection<T extends SelectableAgent>(value: string, agents: T[], now = Date.now()): string {
  if (agents.length === 0) return ""
  if (agents.some((agent) => agent.id === value)) return value
  return (agents.find((agent) => isRecentlyOnline(agent.lastHeartbeat, now)) || agents[0]).id
}

export function isServiceActive(status: string, subState = ""): boolean {
  return /^(active|running)$/i.test(status.trim()) || /^running$/i.test(subState.trim())
}

export function completedDeploymentSteps(output: string, succeeded = false): Set<string> {
  if (succeeded) return new Set(DEPLOYMENT_STEPS)
  const completed = new Set<string>()
  for (const line of output.split("\n")) {
    if (!line.startsWith("[done]")) continue
    for (const step of DEPLOYMENT_STEPS) {
      if (line.includes(step)) completed.add(step)
    }
  }
  return completed
}
