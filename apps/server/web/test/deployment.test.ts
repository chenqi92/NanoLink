import assert from "node:assert/strict"
import test from "node:test"

import { findReconciledDeploymentTask } from "../src/lib/deployment.ts"

test("发布响应丢失后只认领本次新增且动作匹配的任务", () => {
  const tasks = [
    { id: "new-rollback", releaseId: "release-1", action: "rollback" as const },
    { id: "new-deploy", releaseId: "release-1", action: "deploy" as const },
    { id: "old-deploy", releaseId: "release-1", action: "deploy" as const },
  ]

  assert.equal(
    findReconciledDeploymentTask(tasks, new Set(["old-deploy"]), "release-1", "deploy")?.id,
    "new-deploy",
  )
  assert.equal(
    findReconciledDeploymentTask(tasks, new Set(tasks.map((task) => task.id)), "release-1", "deploy"),
    undefined,
  )
})
