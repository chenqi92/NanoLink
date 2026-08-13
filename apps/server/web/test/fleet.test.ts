import assert from "node:assert/strict"
import test from "node:test"

import { completedDeploymentSteps, eligibleFleetShellAgents } from "../src/lib/fleet.ts"

test("批量终端只包含在线且具备 L3 权限的 agent", () => {
  const now = Date.parse("2026-08-13T08:00:00Z")
  const agents = [
    { id: "ready", permissionLevel: 3, lastHeartbeat: "2026-08-13T07:59:30Z" },
    { id: "read-only", permissionLevel: 1, lastHeartbeat: "2026-08-13T07:59:30Z" },
    { id: "stale", permissionLevel: 3, lastHeartbeat: "2026-08-13T07:58:30Z" },
  ]

  assert.deepEqual(eligibleFleetShellAgents(agents, now).map((agent) => agent.id), ["ready"])
})

test("部署轨道仅把完成日志标记为已完成", () => {
  const steps = completedDeploymentSteps("[done] preflight\n[start] download\n[done] verify")

  assert.deepEqual([...steps], ["preflight", "verify"])
  assert.deepEqual([...completedDeploymentSteps("", true)], [
    "preflight",
    "download",
    "verify",
    "stage",
    "activate",
    "service",
    "health",
  ])
})
