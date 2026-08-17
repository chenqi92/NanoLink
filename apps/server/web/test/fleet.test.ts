import assert from "node:assert/strict"
import test from "node:test"

import { completedDeploymentSteps, eligibleFleetShellAgents, isServiceActive, reconcileAgentSelection } from "../src/lib/fleet.ts"

test("批量终端只包含在线且具备 L3 权限的 agent", () => {
  const now = Date.parse("2026-08-13T08:00:00Z")
  const agents = [
    { id: "ready", permissionLevel: 3, lastHeartbeat: "2026-08-13T07:59:30Z" },
    { id: "read-only", permissionLevel: 1, lastHeartbeat: "2026-08-13T07:59:30Z" },
    { id: "stale", permissionLevel: 3, lastHeartbeat: "2026-08-13T07:57:30Z" },
  ]

  assert.deepEqual(eligibleFleetShellAgents(agents, now).map((agent) => agent.id), ["ready"])
})

test("Agent 离线移除后切换到仍在线的节点", () => {
  const now = Date.parse("2026-08-13T08:00:00Z")
  const agents = [
    { id: "offline", lastHeartbeat: "2026-08-13T07:58:00Z" },
    { id: "online", lastHeartbeat: "2026-08-13T07:59:30Z" },
  ]

  assert.equal(reconcileAgentSelection("removed", agents, now), "online")
  assert.equal(reconcileAgentSelection("offline", agents, now), "offline")
  assert.equal(reconcileAgentSelection("removed", [], now), "")
})

test("inactive 服务不会被 active 子串误判为运行中", () => {
  assert.equal(isServiceActive("active", "running"), true)
  assert.equal(isServiceActive("inactive", "dead"), false)
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
