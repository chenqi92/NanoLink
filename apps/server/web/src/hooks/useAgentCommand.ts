import { useCallback, useEffect, useRef, useState } from "react"
import { commandsApi, type CommandResultData } from "@/lib/api"
import i18n from "@/i18n"

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

/**
 * Dispatch an agent command and poll for its structured result (imperative).
 * Throws on agent error or timeout.
 */
export async function runAgentCommand(agentId: string, type: string, opts: { target?: string; params?: Record<string, string> } = {}): Promise<CommandResultData> {
  const { commandId } = await commandsApi.send(agentId, { type, target: opts.target, params: opts.params })
  for (let i = 0; i < 30; i++) {
    await sleep(500)
    const res = await commandsApi.result(agentId, commandId)
    if (res && !("status" in res)) {
      const r = res as CommandResultData
      if (r.success === false && r.error) throw new Error(r.error)
      return r
    }
  }
  throw new Error(i18n.t("common.timeout"))
}

/**
 * Hook wrapper around runAgentCommand: auto-runs on mount/dep change.
 */
export function useAgentCommand(agentId: string, type: string, opts: { target?: string; params?: Record<string, string>; enabled?: boolean } = {}) {
  const { target, params, enabled = true } = opts
  const paramsKey = params ? JSON.stringify(params) : ""
  const [data, setData] = useState<CommandResultData | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<unknown>(null)
  const reqId = useRef(0)

  const run = useCallback(async () => {
    const myReq = ++reqId.current
    setLoading(true)
    setError(null)
    try {
      const result = await runAgentCommand(agentId, type, { target, params: paramsKey ? JSON.parse(paramsKey) : undefined })
      if (reqId.current !== myReq) return
      setData(result)
    } catch (e) {
      if (reqId.current !== myReq) return
      setError(e)
    } finally {
      if (reqId.current === myReq) setLoading(false)
    }
  }, [agentId, type, target, paramsKey])

  useEffect(() => {
    if (enabled) run()
  }, [run, enabled])

  return { data, loading, error, reload: run }
}
