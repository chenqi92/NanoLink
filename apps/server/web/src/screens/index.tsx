import { useTranslation } from "react-i18next"
import { useRouter } from "@/store/router"
import { Placeholder } from "./Placeholder"
import { DashboardScreen } from "./DashboardScreen"
import { AgentsScreen } from "./AgentsScreen"
import { AgentDetailScreen } from "./AgentDetailScreen"
import { TokensScreen } from "./TokensScreen"
import { DevicesScreen } from "./DevicesScreen"
import { UsersScreen } from "./UsersScreen"
import { GroupsScreen } from "./GroupsScreen"
import { PermissionsScreen } from "./PermissionsScreen"

// Screens are progressively replaced with real implementations across the
// redesign nodes. Until then they render a Placeholder.
export function ScreenRouter() {
  const { t } = useTranslation()
  const { route } = useRouter()

  switch (route.page) {
    case "dashboard":
      return <DashboardScreen />
    case "agents":
      return <AgentsScreen />
    case "agent-detail":
      return <AgentDetailScreen />
    case "alerts":
      return <Placeholder title={t("nav.alerts")} />
    case "assistant":
      return <Placeholder title={t("nav.assistant")} />
    case "operations":
      return <Placeholder title={t("nav.operations")} />
    case "logs":
      return <Placeholder title={t("nav.logs")} />
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
      return <Placeholder title={t("nav.audit")} />
    case "settings":
      return <Placeholder title={t("nav.settings")} />
    default:
      return <DashboardScreen />
  }
}
