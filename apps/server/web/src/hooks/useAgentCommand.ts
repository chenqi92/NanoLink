import { useCallback, useEffect, useRef, useState } from "react"
import { commandsApi, type CommandResultData } from "@/lib/api"

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

/**
 * Dispatches an agent command and polls for its structured result.
 * The agent executes asynchronously; the server caches the result and we poll
 * GET /agents/:id/command/:commandId/result until it arrives (or times out).
 */
export function useAgentCommand(agentId: string, type: string, opts: { target?: string; params?: Record<string, string>; enabled?: boolean } = {}) {
  const { target, params, enabled = true } = opts
  const paramsKey = params ? JSON.stringify(params) : ""
  const [data, setData] = useState<CommandResultData | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const reqId = useRef(0)

  const run = useCallback(async () => {
    const myReq = ++reqId.current
    setLoading(true)
    setError(null)
    try {
      const { commandId } = await commandsApi.send(agentId, { type, target, params: paramsKey ? JSON.parse(paramsKey) : undefined })
      let res: CommandResultData | { status: "pending" } | null = null
      for (let i = 0; i < 30; i++) {
        await sleep(500)
        if (reqId.current !== myReq) return // superseded
        res = await commandsApi.result(agentId, commandId)
        if (!res || !("status" in res) || res.status !== "pending") break
      }
      if (reqId.current !== myReq) return
      if (!res || ("status" in res && res.status === "pending")) throw new Error("timeout")
      const result = res as CommandResultData
      if (result.success === false && result.error) throw new Error(result.error)
      setData(result)
    } catch (e) {
      if (reqId.current !== myReq) return
      const msg = typeof e === "object" && e && "error" in e ? String((e as { error: unknown }).error) : e instanceof Error ? e.message : "failed"
      setError(msg)
    } finally {
      if (reqId.current === myReq) setLoading(false)
    }
  }, [agentId, type, target, paramsKey])

  useEffect(() => {
    if (enabled) run()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [run, enabled])

  return { data, loading, error, reload: run }
}
