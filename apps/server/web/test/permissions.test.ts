import test from "node:test"
import assert from "node:assert/strict"
import { effectiveAgentPermission } from "../src/lib/permissions.ts"

test("超级管理员权限仍受节点令牌上限约束", () => {
  const level = effectiveAgentPermission(
    { isSuperAdmin: true },
    { id: "readonly", permissionLevel: 0 },
    undefined,
    [],
  )
  assert.equal(level, 0)
})

test("用户组只授权选中的节点并受节点上限约束", () => {
  const user = { isSuperAdmin: false, groups: [{ id: 7 }] }
  const groups = [{
    id: 7,
    agents: [
      { agentId: "selected", permissionLevel: 3 },
      { agentId: "limited", permissionLevel: 3 },
    ],
  }]

  assert.equal(effectiveAgentPermission(user, { id: "selected", permissionLevel: 3 }, undefined, groups), 3)
  assert.equal(effectiveAgentPermission(user, { id: "limited", permissionLevel: 1 }, undefined, groups), 1)
  assert.equal(effectiveAgentPermission(user, { id: "outside", permissionLevel: 3 }, undefined, groups), undefined)
})
