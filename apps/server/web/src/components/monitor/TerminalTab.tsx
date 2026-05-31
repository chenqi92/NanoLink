import { useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { Terminal } from "@/components/shell/Terminal"

export function TerminalTab({ agentId, permission }: { agentId: string; permission: number }) {
  const { t } = useTranslation()
  const [key, setKey] = useState(0)

  if (permission < 1) {
    return (
      <div style={{ padding: 40, textAlign: "center" }}>
        <span style={{ color: "var(--fg-4)" }}>{I.shield({ size: 32 })}</span>
        <div style={{ marginTop: 12, fontSize: 14, fontWeight: 500 }}>{t("mon.noAccess")}</div>
        <div className="muted" style={{ marginTop: 6, fontSize: 12 }}>
          {t("permission.l3")} · {t("agent.terminal")}
        </div>
      </div>
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
