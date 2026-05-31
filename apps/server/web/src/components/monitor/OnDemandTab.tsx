import { useState, type ReactNode } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { commandsApi } from "@/lib/api"

// Live process/service/docker/file/log inspection streams back from the agent
// asynchronously; the dashboard-side result channel is a backend TODO. This tab
// triggers the (audited) data request and surfaces request status honestly.
const REQUEST_TYPE: Record<string, string> = {
  processes: "PROCESS_LIST",
  services: "SERVICE_STATUS",
  docker: "DOCKER_LIST",
  files: "FILE_TAIL",
  logs: "LOG_STREAM",
}

export function OnDemandTab({ agentId, host, kind, icon, disabled }: { agentId: string; host: string; kind: keyof typeof REQUEST_TYPE; icon: ReactNode; disabled?: boolean }) {
  const { t } = useTranslation()
  const [status, setStatus] = useState<"idle" | "sending" | "sent" | "error">("idle")

  async function request() {
    setStatus("sending")
    try {
      await commandsApi.dataRequest(agentId, REQUEST_TYPE[kind])
      setStatus("sent")
    } catch {
      setStatus("error")
    }
  }

  return (
    <div style={{ padding: 24 }}>
      <div className="card" style={{ padding: "40px 24px", display: "flex", flexDirection: "column", alignItems: "center", gap: 12, textAlign: "center" }}>
        <span style={{ color: "var(--fg-dim)" }}>{icon}</span>
        <div className="muted" style={{ fontSize: 12.5, maxWidth: 420 }}>{t("mon.onDemandDesc", { host })}</div>
        <button className="btn btn-sm btn-primary" onClick={request} disabled={disabled || status === "sending"}>
          {I.refresh({ size: 13 })}
          <span>{t("mon.requestFromAgent")}</span>
        </button>
        {status === "sent" && <span className="badge ok">{t("mon.requestSent")}</span>}
        {status === "error" && <span className="badge crit">{t("mon.requestFailed")}</span>}
      </div>
    </div>
  )
}
