import { useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useAssistant } from "@/contexts/AssistantContext"

export function McpPanel({ visible = true }: { visible?: boolean }) {
  const { t } = useTranslation()
  const { mcp, refreshMcp } = useAssistant()
  const [tab, setTab] = useState<"capabilities" | "activity">("capabilities")

  useEffect(() => {
    if (!visible) return
    const refreshWhenVisible = () => { if (document.visibilityState === "visible") refreshMcp() }
    const id = window.setInterval(refreshWhenVisible, 15000)
    document.addEventListener("visibilitychange", refreshWhenVisible)
    return () => {
      window.clearInterval(id)
      document.removeEventListener("visibilitychange", refreshWhenVisible)
    }
  }, [refreshMcp, visible])

  const overview = mcp.data
  const state = overview?.state || (overview?.enabled ? "starting" : "disabled")
  // Treat missing or null collections as empty so an older/malformed Server
  // response cannot crash the whole Assistant screen.
  const tools = Array.isArray(overview?.tools) ? overview.tools : []
  const activity = Array.isArray(overview?.activity) ? overview.activity : []

  return (
    <aside className="mcp-panel" aria-label={t("assistant.mcpPanel")}>
      <div className="mcp-panel-header">
        <div className="col" style={{ gap: 2 }}>
          <div className="row gap-2"><span className={`dot ${state === "running" ? "ok" : state === "disabled" ? "off" : "warn"}`} /><strong>{t("assistant.mcpTitle")}</strong></div>
          <span className="muted">{t(`assistant.mcpState.${state}`, { defaultValue: state })}{overview?.transport ? ` · ${overview.transport}` : ""}</span>
        </div>
        <button className="btn btn-ghost btn-icon btn-sm" onClick={refreshMcp} disabled={mcp.loading} aria-label={t("assistant.refreshMcp")} title={t("assistant.refreshMcp")}>{I.refresh({ size: 13 })}</button>
      </div>

      <div className="tabs mcp-tabs" role="tablist">
        <button className={`tab ${tab === "capabilities" ? "active" : ""}`} role="tab" aria-selected={tab === "capabilities"} onClick={() => setTab("capabilities")}>{t("assistant.capabilities")}{overview && <span className="badge">{tools.length}</span>}</button>
        <button className={`tab ${tab === "activity" ? "active" : ""}`} role="tab" aria-selected={tab === "activity"} onClick={() => setTab("activity")}>{t("assistant.activity")}{overview && <span className="badge">{activity.length}</span>}</button>
      </div>

      {mcp.error && <div className="mcp-error" role="alert"><span>{mcp.error}</span><button className="btn btn-sm btn-ghost" onClick={refreshMcp}>{t("assistant.retry")}</button></div>}
      {mcp.loading && !overview && <div className="mcp-loading"><div className="skeleton" /><div className="skeleton" /><div className="skeleton" /></div>}

      <div className="mcp-panel-body">
        {tab === "capabilities" ? (
          <div className="mcp-tool-list">
            {!overview?.enabled && overview && <div className="mcp-notice">{t("assistant.mcpDisabled")}</div>}
            {tools.map((tool) => {
              const required = Array.isArray(tool.inputSchema?.required) ? tool.inputSchema.required.map(String) : []
              return (
                <details key={tool.name} className="mcp-tool">
                  <summary>
                    <span className="mcp-tool-icon">{I.bolt({ size: 12 })}</span>
                    <span className="col flex-1" style={{ gap: 2 }}><span className="mono mcp-tool-name">{tool.name}</span><span className="dim mcp-tool-desc">{tool.description}</span></span>
                    {I.chev({ size: 11 })}
                  </summary>
                  <div className="mcp-tool-details">
                    <span className="upper">{t("assistant.requiredInputs")}</span>
                    <span className="mono muted">{required.length ? required.join(", ") : t("assistant.none")}</span>
                    <pre>{JSON.stringify(tool.inputSchema, null, 2)}</pre>
                  </div>
                </details>
              )
            })}
            {overview && tools.length === 0 && <div className="muted mcp-empty">{t("assistant.noCapabilities")}</div>}
          </div>
        ) : (
          <div className="mcp-activity-list">
            {activity.map((entry) => (
              <div key={entry.id} className="mcp-activity-row">
                <span className={`dot ${entry.success ? "ok" : "crit"}`} />
                <div className="col flex-1" style={{ gap: 2, minWidth: 0 }}><span className="mono truncate">{entry.toolName}</span><span className="dim">{new Date(entry.startedAt).toLocaleTimeString()}</span></div>
                <span className="mono dim">{entry.durationMs}ms</span>
              </div>
            ))}
            {overview && activity.length === 0 && <div className="muted mcp-empty">{t("assistant.noActivity")}</div>}
          </div>
        )}
      </div>
      <div className="mcp-scope-note">{I.info({ size: 13 })}<span>{t("assistant.mcpScopeNote")}</span></div>
    </aside>
  )
}
