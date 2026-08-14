export interface PermissionTarget {
  id: string
  permissionLevel: number
}

export interface PermissionUser {
  isSuperAdmin: boolean
  groups?: { id: number }[]
}

export interface PermissionGroup {
  id: number
  agents?: { agentId: string; permissionLevel: number }[]
}

function clampLevel(level: number): number {
  return Math.max(0, Math.min(3, level))
}

/**
 * Resolve the permission that is actually usable on a node.
 *
 * Direct and group grants are combined using the server's "highest grant"
 * rule, then capped by the permission of the node's own connection token.
 */
export function effectiveAgentPermission(
  user: PermissionUser,
  agent: PermissionTarget,
  directLevel: number | undefined,
  groups: PermissionGroup[],
): number | undefined {
  const agentCeiling = clampLevel(agent.permissionLevel)
  if (user.isSuperAdmin) return agentCeiling

  const grants: number[] = []
  if (directLevel != null) grants.push(clampLevel(directLevel))

  const memberGroupIDs = new Set((user.groups ?? []).map((group) => group.id))
  for (const group of groups) {
    if (!memberGroupIDs.has(group.id)) continue
    for (const grant of group.agents ?? []) {
      if (grant.agentId === agent.id) grants.push(clampLevel(grant.permissionLevel))
    }
  }

  if (grants.length === 0) return undefined
  return Math.min(Math.max(...grants), agentCeiling)
}
