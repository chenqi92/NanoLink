import { useState, useEffect, useCallback } from "react"
import { agentsApi, metricsApi, type Agent, type Metrics, type Summary } from "@/lib/api"

export function useAgents() {
  const [agents, setAgents] = useState<Agent[]>([])
  const [metrics, setMetrics] = useState<Record<string, Metrics>>({})
  const [summary, setSummary] = useState<Summary>({
    connectedAgents: 0,
    avgCpuPercent: 0,
    memoryPercent: 0,
    totalMemory: 0,
    usedMemory: 0,
  })
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchData = useCallback(async () => {
    try {
      const [agentsData, metricsData, summaryData] = await Promise.all([
        agentsApi.list(),
        metricsApi.all(),
        metricsApi.summary(),
      ])
      setAgents(agentsData)
      setMetrics(metricsData)
      setSummary(summaryData)
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to fetch data")
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchData()
    const interval = setInterval(fetchData, 2000)
    return () => clearInterval(interval)
  }, [fetchData])

  return { agents, metrics, summary, loading, error, refresh: fetchData }
}

export function useAgent(agentId: string) {
  const [agent, setAgent] = useState<Agent | null>(null)
  const [metrics, setMetrics] = useState<Metrics | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchData = useCallback(async () => {
    if (!agentId) return
    try {
      const [agentData, metricsData] = await Promise.all([
        agentsApi.get(agentId),
        metricsApi.get(agentId),
      ])
      setAgent(agentData)
      setMetrics(metricsData)
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to fetch agent data")
    } finally {
      setLoading(false)
    }
  }, [agentId])

  useEffect(() => {
    fetchData()
    const interval = setInterval(fetchData, 2000)
    return () => clearInterval(interval)
  }, [fetchData])

  return { agent, metrics, loading, error, refresh: fetchData }
}
