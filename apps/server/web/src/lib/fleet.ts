export const DEPLOYMENT_STEPS = ["preflight", "download", "verify", "stage", "activate", "service", "health"] as const

interface FleetAgent {
  permissionLevel: number
  lastHeartbeat: string
}

export function isRecentlyOnline(lastHeartbeat: string, now = Date.now()): boolean {
  const timestamp = Date.parse(lastHeartbeat)
  return Number.isFinite(timestamp) && now - timestamp < 60_000
}

export function eligibleFleetShellAgents<T extends FleetAgent>(agents: T[], now = Date.now()): T[] {
  return agents.filter((agent) => agent.permissionLevel >= 3 && isRecentlyOnline(agent.lastHeartbeat, now))
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
