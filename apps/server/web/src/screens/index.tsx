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
import { DeploymentsScreen } from "./DeploymentsScreen"
import { LogsScreen } from "./LogsScreen"
import { AuditScreen } from "./AuditScreen"
import { SettingsScreen } from "./SettingsScreen"
import { AlertsScreen } from "./AlertsScreen"
import { AlertConfigScreen } from "./AlertConfigScreen"
import { AssistantScreen } from "./AssistantScreen"

export function ScreenRouter() {
  const { route } = useRouter()

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
      return <DashboardScreen />
  }
}
