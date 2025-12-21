import { useEffect } from 'react'
import { useWebSocket } from '@/hooks/useWebSocket'
import { useMetricsHistory } from '@/hooks/useMetricsHistory'
import { AgentCard } from '@/components/cards/AgentCard'
import { OverviewPanel } from '@/components/cards/OverviewPanel'
import { Badge } from '@/components/ui/badge'
import { Cpu, Server } from 'lucide-react'

export default function App() {
  const { agents, selectedAgentId, selectAgent, connected } = useWebSocket()
  const { addMetricsPoint, getHistory } = useMetricsHistory()
  
  const agentList = Object.values(agents)
  const currentAgent = selectedAgentId ? agents[selectedAgentId] : null

  // Track metrics history for all agents
  useEffect(() => {
    agentList.forEach(agent => {
      if (agent.lastMetrics) {
        addMetricsPoint(agent.agentId, {
          cpu: agent.lastMetrics.cpu,
          memory: agent.lastMetrics.memory,
          networks: agent.lastMetrics.networks,
          timestamp: agent.lastMetrics.timestamp,
        })
      }
    })
  }, [agentList, addMetricsPoint])

  const metricsHistory = selectedAgentId ? getHistory(selectedAgentId) : []

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-50 glass border-b border-border">
        <div className="max-w-7xl mx-auto px-6 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-primary/20">
                <Cpu className="w-6 h-6 text-primary" />
              </div>
              <div>
                <h1 className="text-xl font-bold">NanoLink</h1>
                <p className="text-sm text-muted-foreground">Server Monitoring Dashboard</p>
              </div>
            </div>
            
            <div className="flex items-center gap-4">
              <Badge variant={connected ? "success" : "destructive"}>
                <span className={`w-2 h-2 rounded-full mr-2 ${connected ? 'bg-emerald-400 animate-pulse' : 'bg-red-400'}`} />
                {connected ? 'Connected' : 'Disconnected'}
              </Badge>
              <span className="text-sm text-muted-foreground">
                {agentList.length} agent{agentList.length !== 1 ? 's' : ''}
              </span>
            </div>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-6 py-8">
        {/* Agent Cards */}
        {agentList.length > 0 ? (
          <>
            <div className="mb-8">
              <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <Server className="w-5 h-5 text-primary" />
                Connected Agents
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
                {agentList.map(agent => (
                  <AgentCard
                    key={agent.agentId}
                    agent={agent}
                    selected={selectedAgentId === agent.agentId}
                    onClick={() => selectAgent(agent.agentId)}
                  />
                ))}
              </div>
            </div>

            {/* Agent Details */}
            {currentAgent && (
              <div>
                <h2 className="text-lg font-semibold mb-4">
                  {currentAgent.hostname} — Real-time Metrics
                </h2>
                <OverviewPanel agent={currentAgent} metricsHistory={metricsHistory} />
              </div>
            )}
          </>
        ) : (
          <div className="flex flex-col items-center justify-center py-20">
            <div className="p-6 rounded-full bg-muted mb-4">
              <Server className="w-12 h-12 text-muted-foreground" />
            </div>
            <h3 className="text-xl font-medium mb-2">No Agents Connected</h3>
            <p className="text-muted-foreground text-center max-w-md">
              Install the NanoLink agent on your servers to start monitoring.
              Once connected, they will appear here automatically.
            </p>
          </div>
        )}
      </main>
    </div>
  )
}
