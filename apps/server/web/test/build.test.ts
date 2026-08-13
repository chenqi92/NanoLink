import assert from "node:assert/strict"
import test from "node:test"

import { cleanRunOutput, parseStageStates } from "../src/lib/build.ts"

test("构建控制台保留过程日志并隐藏阶段状态协议", () => {
  const output = [
    "[done] prepare workspace run-1",
    "[stage:start] package 打包",
    "[log] creating archive",
    "[stage:done] package 打包",
    "[done] upload site.tar.gz",
  ].join("\n")

  assert.equal(cleanRunOutput(output), [
    "[done] prepare workspace run-1",
    "creating archive",
    "[done] upload site.tar.gz",
  ].join("\n"))
  assert.equal(parseStageStates(output).get("package"), "done")
})
