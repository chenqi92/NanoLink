export type BuildStageState = "active" | "done" | "failed" | "warning"

export function parseStageStates(output: string) {
  const states = new Map<string, BuildStageState>()
  for (const line of output.split("\n")) {
    const match = line.match(/^\[stage:(start|done|failed|warning|canceled)\]\s+(\S+)/)
    if (!match) continue
    states.set(match[2], match[1] === "start" ? "active" : match[1] === "canceled" ? "failed" : match[1] as BuildStageState)
  }
  return states
}

export function cleanRunOutput(output: string) {
  return output
    .split("\n")
    .filter((line) => line && !line.startsWith("[stage:"))
    .map((line) => line.replace(/^\[log\]\s?/, ""))
    .join("\n")
}
