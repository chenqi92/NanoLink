import { useState } from "react"
import { useTranslation } from "react-i18next"
import { Loader2, Plus } from "lucide-react"
import "./i18n"
import "@/index.css"
import { useAuth } from "@/contexts/AuthContext"
import { useData } from "@/contexts/DataContext"
import { useTheme } from "@/hooks/use-theme"
import { LoginForm } from "@/components/auth/LoginForm"
import { Header } from "@/components/layout/Header"
import { SummaryCards } from "@/components/dashboard/SummaryCards"
import { AgentCard } from "@/components/agents/AgentCard"
import { ShellDialog } from "@/components/shell/ShellDialog"
import { UserManagement } from "@/components/admin/UserManagement"
import { GroupManagement } from "@/components/admin/GroupManagement"
import { AgentMetricsView } from "@/components/charts/AgentMetricsView"
import { AddAgentWizard } from "@/components/agents/AddAgentWizard"
import { Button } from "@/components/ui/button"

type View = "dashboard" | "users" | "groups" | "permissions" | "settings"

function App() {
  const { t } = useTranslation()
  const { isAuthenticated, isLoading: authLoading } = useAuth()
  const { agents, metrics, summary, isLoading: dataLoading, error } = useData()
  useTheme() // Initialize theme
  const [currentView, setCurrentView] = useState<View>("dashboard")
  const [shellAgent, setShellAgent] = useState<{ id: string; name: string } | null>(null)
  const [metricsAgent, setMetricsAgent] = useState<{ id: string; name: string } | null>(null)
  const [showAddAgentWizard, setShowAddAgentWizard] = useState(false)

  // Show loading while checking authentication
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

  // Show login form when not authenticated
  if (!isAuthenticated) {
    return <LoginForm />
  }

  return (
    <div className="min-h-screen bg-[var(--color-background)]">
      <Header onNavigate={setCurrentView} />

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

            <div className="flex items-center justify-between mt-8 mb-4">
              <h2 className="text-lg font-semibold">{t("header.agents")}</h2>
              <Button onClick={() => setShowAddAgentWizard(true)}>
                <Plus className="w-4 h-4 mr-2" />
                {t("wizard.addAgent", "Add Agent")}
              </Button>
            </div>

            {agents.length === 0 ? (
              <div className="rounded-lg border border-[var(--color-border)] bg-[var(--color-card)] p-12 text-center">
                <p className="text-[var(--color-muted-foreground)]">{t("dashboard.noAgents")}</p>
                <p className="text-sm text-[var(--color-muted-foreground)] mt-2">
                  {t("dashboard.noAgentsDesc")}
                </p>
                <Button className="mt-4" onClick={() => setShowAddAgentWizard(true)}>
                  <Plus className="w-4 h-4 mr-2" />
                  {t("wizard.addAgent", "Add Agent")}
                </Button>
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

      {/* Add Agent Wizard */}
      {showAddAgentWizard && (
        <AddAgentWizard onClose={() => setShowAddAgentWizard(false)} />
      )}
    </div>
  )
}

export default App
