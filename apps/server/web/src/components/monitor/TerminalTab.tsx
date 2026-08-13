import { useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { Terminal } from "@/components/shell/Terminal"
import { ContentState } from "@/components/shell/RequestState"

export function TerminalTab({ agentId, permission }: { agentId: string; permission: number }) {
  const { t } = useTranslation()
  const [key, setKey] = useState(0)

  if (permission < 3) {
    return (
      <div style={{ padding: 20 }}><ContentState kind="forbidden" eyebrow={t("access.restricted")} title={t("access.noPermissionTitle")} description={t("access.permissionLevelDesc", { level: "L3" })} /></div>
    )
  }

  const wsUrl = `${window.location.protocol === "https:" ? "wss" : "ws"}://${window.location.host}/ws/shell/${agentId}`

  return (
    <div className="col" style={{ padding: 20, gap: 14, height: "100%" }}>
      <div className="row" style={{ justifyContent: "space-between", alignItems: "center" }}>
        <div className="row gap-2" style={{ alignItems: "center", minWidth: 0 }}>
          <span className="dot pulse ok" />
          <span className="mono truncate" style={{ fontSize: 12, color: "var(--fg-2)" }}>{wsUrl}</span>
        </div>
        <div className="row gap-2">
          <button className="btn btn-sm btn-ghost" onClick={() => setKey((k) => k + 1)}>{I.refresh({ size: 13 })}<span>{t("shell.connect")}</span></button>
        </div>
      </div>
      <div style={{ flex: 1, minHeight: 420 }}>
        <Terminal key={key} agentId={agentId} />
      </div>
    </div>
  )
}
