import { useState, useEffect } from "react"
import { useTranslation } from "react-i18next"
import { Loader2 } from "lucide-react"
import "./i18n"
import "@/index.css"
import { useAuth } from "@/hooks/use-auth"
import { useAgents } from "@/hooks/use-agents"
import { useTheme } from "@/hooks/use-theme"
import { LoginForm } from "@/components/auth/LoginForm"
import { Header } from "@/components/layout/Header"
import { SummaryCards } from "@/components/dashboard/SummaryCards"
import { AgentCard } from "@/components/agents/AgentCard"
import { ShellDialog } from "@/components/shell/ShellDialog"
import { UserManagement } from "@/components/admin/UserManagement"
import { GroupManagement } from "@/components/admin/GroupManagement"
import { AgentMetricsView } from "@/components/charts/AgentMetricsView"

type View = "dashboard" | "users" | "groups" | "permissions" | "settings"

function App() {
  const { t } = useTranslation()
  const { user, isAuthenticated, loading: authLoading, logout, initAuth } = useAuth()
  const { agents, metrics, summary, loading: dataLoading, error } = useAgents()
  const { theme } = useTheme() // Initialize theme
  const [currentView, setCurrentView] = useState<View>("dashboard")
  const [shellAgent, setShellAgent] = useState<{ id: string; name: string } | null>(null)
  const [metricsAgent, setMetricsAgent] = useState<{ id: string; name: string } | null>(null)

  // Show loading
  if (authLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[var(--color-background)]">
        <div className="text-center">
          <Loader2 className="h-12 w-12 animate-spin text-blue-500 mx-auto" />
          <p className="mt-4 text-[var(--color-muted-foreground)]">{t("common.loading")}</p>
        </div>
      </div>
    )
  }

  // Show login
  if (!isAuthenticated) {
    return <LoginForm onSuccess={() => initAuth()} />
  }

  return (
    <div className="min-h-screen bg-[var(--color-background)]">
      <Header
        user={user}
        agentCount={agents.length}
        hasError={!!error}
        onLogout={logout}
        onNavigate={setCurrentView}
      />

      <main className="container mx-auto p-6">
        {error && (
          <div className="mb-6 rounded-lg bg-red-500/10 border border-red-500/50 p-4 text-red-500">
            {error}
          </div>
        )}

        {dataLoading ? (
          <div className="flex items-center justify-center h-64">
            <Loader2 className="h-12 w-12 animate-spin text-blue-500" />
          </div>
        ) : metricsAgent ? (
          /* Agent Metrics Detail View */
          <AgentMetricsView
            agentId={metricsAgent.id}
            agentName={metricsAgent.name}
            onBack={() => setMetricsAgent(null)}
          />
        ) : currentView === "dashboard" ? (
          <>
            <SummaryCards
              connectedAgents={summary.connectedAgents || agents.length}
              avgCpu={summary.avgCpuPercent}
              memoryPercent={summary.memoryPercent}
              totalMemory={summary.totalMemory}
              usedMemory={summary.usedMemory}
            />

            <h2 className="text-lg font-semibold mt-8 mb-4">{t("header.agents")}</h2>

            {agents.length === 0 ? (
              <div className="rounded-lg border border-[var(--color-border)] bg-[var(--color-card)] p-12 text-center">
                <p className="text-[var(--color-muted-foreground)]">{t("dashboard.noAgents")}</p>
                <p className="text-sm text-[var(--color-muted-foreground)] mt-2">
                  {t("dashboard.noAgentsDesc")}
                </p>
              </div>
            ) : (
              <div className="grid gap-6 md:grid-cols-2 xl:grid-cols-3">
                {agents.map((agent) => (
                  <AgentCard
                    key={agent.id}
                    agent={agent}
                    metrics={metrics[agent.id]}
                    onOpenShell={(id) => setShellAgent({ id, name: agent.hostname })}
                    onViewMetrics={(id) => setMetricsAgent({ id, name: agent.hostname })}
                  />
                ))}
              </div>
            )}
          </>
        ) : currentView === "users" ? (
          <UserManagement />
        ) : currentView === "groups" ? (
          <GroupManagement />
        ) : null}
      </main>

      {/* Shell Dialog */}
      {shellAgent && (
        <ShellDialog
          agentId={shellAgent.id}
          agentName={shellAgent.name}
          onClose={() => setShellAgent(null)}
        />
      )}
    </div>
  )
}

export default App
