import { useTranslation } from "react-i18next"
import { Sun, Moon, Monitor, Globe, LogOut, Users, Shield, Wifi, WifiOff } from "lucide-react"
import { Button } from "@/components/ui/button"
import { useTheme } from "@/hooks/use-theme"
import { useAuth } from "@/contexts/AuthContext"
import { useData } from "@/contexts/DataContext"
import { setLanguage, getLanguage } from "@/i18n"

interface HeaderProps {
  onNavigate: (view: "dashboard" | "users" | "groups" | "permissions" | "settings") => void
}

export function Header({ onNavigate }: HeaderProps) {
  const { t } = useTranslation()
  const { user, logout } = useAuth()
  const { agents, wsStatus, connectionMode } = useData()
  const { theme, setTheme } = useTheme()
  const currentLang = getLanguage()

  const cycleTheme = () => {
    const themes: Array<"light" | "dark" | "system"> = ["light", "dark", "system"]
    const currentIndex = themes.indexOf(theme)
    const nextTheme = themes[(currentIndex + 1) % themes.length]
    setTheme(nextTheme)
  }

  const toggleLanguage = () => {
    setLanguage(currentLang === "en" ? "zh" : "en")
  }

  const ThemeIcon = theme === "light" ? Sun : theme === "dark" ? Moon : Monitor

  const getConnectionStatus = () => {
    if (wsStatus === 'connected') {
      return { color: 'bg-green-500', icon: Wifi, text: 'Live' }
    }
    if (wsStatus === 'connecting') {
      return { color: 'bg-yellow-500', icon: Wifi, text: 'Connecting' }
    }
    if (connectionMode === 'polling') {
      return { color: 'bg-blue-500', icon: WifiOff, text: 'Polling' }
    }
    return { color: 'bg-red-500', icon: WifiOff, text: 'Offline' }
  }

  const status = getConnectionStatus()
  const StatusIcon = status.icon

  return (
    <header className="sticky top-0 z-50 border-b border-[var(--color-border)] bg-[var(--color-background)]/95 backdrop-blur supports-[backdrop-filter]:bg-[var(--color-background)]/60">
      <div className="flex h-14 items-center px-6">
        <div className="flex items-center gap-3">
          <svg
            className="h-8 w-8 text-blue-500"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"
            />
          </svg>
          <h1 className="text-xl font-bold">NanoLink</h1>
        </div>

        <nav className="ml-8 flex items-center gap-4">
          <Button variant="ghost" size="sm" onClick={() => onNavigate("dashboard")}>
            {t("header.dashboard")}
          </Button>
          {user?.isSuperAdmin && (
            <>
              <Button variant="ghost" size="sm" onClick={() => onNavigate("users")}>
                <Users className="mr-1 h-4 w-4" />
                {t("admin.users")}
              </Button>
              <Button variant="ghost" size="sm" onClick={() => onNavigate("groups")}>
                <Shield className="mr-1 h-4 w-4" />
                {t("admin.groups")}
              </Button>
            </>
          )}
        </nav>

        <div className="ml-auto flex items-center gap-3">
          <span className="text-sm text-[var(--color-muted-foreground)]">
            {agents.length} {t("dashboard.connectedAgents")}
          </span>

          <div className="flex items-center gap-1.5" title={status.text}>
            <div className={`h-2 w-2 rounded-full ${status.color}`} />
            <StatusIcon className="h-3.5 w-3.5 text-[var(--color-muted-foreground)]" />
          </div>

          <Button variant="ghost" size="icon" onClick={toggleLanguage} title={t("header.language")}>
            <Globe className="h-4 w-4" />
          </Button>

          <Button variant="ghost" size="icon" onClick={cycleTheme} title={t("header.theme")}>
            <ThemeIcon className="h-4 w-4" />
          </Button>

          {user && (
            <div className="flex items-center gap-2 pl-2 border-l border-[var(--color-border)]">
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-blue-500 text-white text-sm font-medium">
                {user.username.charAt(0).toUpperCase()}
              </div>
              <span className="text-sm font-medium">{user.username}</span>
              <Button variant="ghost" size="icon" onClick={logout} title={t("auth.logout")}>
                <LogOut className="h-4 w-4" />
              </Button>
            </div>
          )}
        </div>
      </div>
    </header>
  )
}
