import { useTranslation } from "react-i18next"
import { Users, Clock, Globe } from "lucide-react"
import { formatUptime, formatTime } from "@/lib/utils"
import type { UserSession } from "@/lib/api"

interface UserSessionsCardProps {
  sessions: UserSession[]
}

export function UserSessionsCard({ sessions }: UserSessionsCardProps) {
  const { t } = useTranslation()

  return (
    <div>
      <div className="text-sm font-medium mb-2 flex items-center gap-1">
        <Users className="h-4 w-4" /> {t("sessions.title")} ({sessions.length})
      </div>
      <div className="rounded-lg bg-[var(--color-muted)] p-3">
        <div className="space-y-2">
          {sessions.map((session, index) => (
            <div 
              key={`${session.username}-${session.tty}-${index}`} 
              className="flex items-center justify-between text-xs"
            >
              <div className="flex items-center gap-2">
                <div className="h-6 w-6 rounded-full bg-blue-500/20 flex items-center justify-center text-blue-500">
                  {session.username.charAt(0).toUpperCase()}
                </div>
                <div>
                  <div className="font-medium">{session.username}</div>
                  <div className="text-[var(--color-muted-foreground)]">
                    {session.tty} • {session.sessionType}
                  </div>
                </div>
              </div>
              <div className="text-right text-[var(--color-muted-foreground)]">
                {session.remoteHost && (
                  <div className="flex items-center gap-1">
                    <Globe className="h-3 w-3" />
                    <span className="truncate max-w-[100px]">{session.remoteHost}</span>
                  </div>
                )}
                <div className="flex items-center gap-1">
                  <Clock className="h-3 w-3" />
                  <span>{formatTime(session.loginTime)}</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
