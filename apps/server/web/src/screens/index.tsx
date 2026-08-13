import { useRouter } from "@/store/router"
import { DashboardScreen } from "./DashboardScreen"
import { AgentsScreen } from "./AgentsScreen"
import { AgentDetailScreen } from "./AgentDetailScreen"
import { TokensScreen } from "./TokensScreen"
import { DevicesScreen } from "./DevicesScreen"
import { UsersScreen } from "./UsersScreen"
import { GroupsScreen } from "./GroupsScreen"
import { PermissionsScreen } from "./PermissionsScreen"
import { OperationsScreen } from "./OperationsScreen"
import { BuildsScreen } from "./BuildsScreen"
import { DeploymentsScreen } from "./DeploymentsScreen"
import { LogsScreen } from "./LogsScreen"
import { AuditScreen } from "./AuditScreen"
import { SettingsScreen } from "./SettingsScreen"
import { AlertsScreen } from "./AlertsScreen"
import { AlertConfigScreen } from "./AlertConfigScreen"
import { AssistantScreen } from "./AssistantScreen"
import { useAuth } from "@/contexts/AuthContext"
import { pageRequiresSuperAdmin } from "@/lib/access"
import { ContentState } from "@/components/shell/RequestState"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"

export function ScreenRouter() {
  const { route } = useRouter()
  const { navigate } = useRouter()
  const { user } = useAuth()
  const { t } = useTranslation()

  if (pageRequiresSuperAdmin(route.page) && !user?.isSuperAdmin) {
    return (
      <div style={{ flex: 1, overflow: "auto", padding: 24 }}>
        <ContentState
          kind="admin"
          eyebrow={t("access.restricted")}
          title={t("access.adminOnly")}
          description={t("access.adminOnlyDesc")}
          action={<button className="btn btn-sm" onClick={() => navigate("dashboard")}>{I.back({ size: 12 })}<span>{t("access.goDashboard")}</span></button>}
        />
      </div>
    )
  }

  switch (route.page) {
    case "dashboard":
      return <DashboardScreen />
    case "agents":
      return <AgentsScreen />
    case "agent-detail":
      return <AgentDetailScreen />
    case "alerts":
      return <AlertsScreen />
    case "alert-config":
      return <AlertConfigScreen />
    case "assistant":
      return <AssistantScreen />
    case "operations":
      return <OperationsScreen />
    case "builds":
      return <BuildsScreen />
    case "deployments":
      return <DeploymentsScreen />
    case "logs":
      return <LogsScreen />
    case "tokens":
      return <TokensScreen />
    case "devices":
      return <DevicesScreen />
    case "users":
      return <UsersScreen />
    case "groups":
      return <GroupsScreen />
    case "permissions":
      return <PermissionsScreen />
    case "audit":
      return <AuditScreen />
    case "settings":
      return <SettingsScreen />
    default:
      return <AssistantScreen />
  }
}
