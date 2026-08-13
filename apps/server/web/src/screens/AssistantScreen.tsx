import { useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useAssistant } from "@/contexts/AssistantContext"
import { AssistantChat } from "@/components/assistant/AssistantChat"
import { McpPanel } from "@/components/assistant/McpPanel"
import { Drawer } from "@/components/shell/Drawer"
import "./assistant.css"

export function AssistantScreen() {
  const { t } = useTranslation()
  const { findings, refresh } = useAssistant()
  const [mcpOpen, setMcpOpen] = useState(false)

  return (
    <div className="assistant-screen">
      <header className="assistant-page-header">
        <div className="col" style={{ gap: 3, minWidth: 0 }}>
          <div className="row gap-2"><span className="assistant-title-icon">{I.ai({ size: 17 })}</span><h1>{t("nav.assistant")}</h1></div>
          <p>{t("assistant.subtitle")}</p>
        </div>
        <div className="row gap-2 assistant-page-actions">
          <span className={`badge ${findings.error ? "warn" : "info"}`}>{I.sparkle({ size: 11 })}<span>{t("assistant.insightsCount", { count: findings.data.length })}</span></span>
          <button className="btn btn-sm btn-ghost" onClick={refresh} disabled={findings.loading} aria-label={t("assistant.refreshInsights")} title={t("assistant.refreshInsights")}>{I.refresh({ size: 13 })}<span className="assistant-action-label">{t("assistant.refreshInsights")}</span></button>
          <button className="btn btn-sm btn-ghost assistant-mcp-toggle" onClick={() => setMcpOpen(true)} aria-label={t("assistant.openMcp")} title={t("assistant.openMcp")}>{I.bolt({ size: 13 })}<span>{t("assistant.mcpTitle")}</span></button>
        </div>
      </header>

      <div className="assistant-workspace">
        <AssistantChat />
        <div className="assistant-mcp-desktop"><McpPanel visible /></div>
      </div>

      <Drawer open={mcpOpen} title={t("assistant.mcpTitle")} closeLabel={t("assistant.closeMcp")} onClose={() => setMcpOpen(false)} className="assistant-mcp-drawer">
        <McpPanel visible={mcpOpen} />
      </Drawer>
    </div>
  )
}
