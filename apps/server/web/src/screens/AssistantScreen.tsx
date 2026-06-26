import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useRouter } from "@/store/router"
import { PageHeader, SectionPanel } from "@/components/shell/primitives"
import { assistantApi, auditApi, type FindingDTO, type ChatMessage, type AuditLog } from "@/lib/api"

type Finding = FindingDTO

const kindIcon = (kind: Finding["kind"], size = 13) =>
  kind === "ok" ? I.check({ size }) : kind === "info" ? I.info({ size }) : kind === "warn" ? I.warn({ size }) : I.bolt({ size })

const TOOLS = [
  { name: "list_agents", desc: "List all agents and status" },
  { name: "get_agent_metrics", desc: "Current metrics for an agent" },
  { name: "get_system_summary", desc: "Fleet-wide summary" },
  { name: "find_high_cpu_agents", desc: "Agents over a CPU threshold" },
  { name: "find_low_disk_agents", desc: "Agents low on disk" },
  { name: "get_agent_processes", desc: "Top processes on an agent" },
  { name: "query_audit_log", desc: "Search the audit trail" },
  { name: "request_agent_data", desc: "Request live data from an agent", danger: true },
]

const kindColor: Record<Finding["kind"], string> = { anomaly: "var(--crit)", warn: "var(--warn)", info: "var(--info)", ok: "var(--ok)" }

export function AssistantScreen() {
  const { t } = useTranslation()
  const { navigate } = useRouter()
  const [findings, setFindings] = useState<Finding[]>([])
  const [loading, setLoading] = useState(true)
  const [recent, setRecent] = useState<AuditLog[]>([])

  const refresh = useCallback(() => {
    assistantApi.findings().then(setFindings).catch(() => {}).finally(() => setLoading(false))
    auditApi.recent(6).then((r) => setRecent(r.logs ?? [])).catch(() => {})
  }, [])

  useEffect(() => {
    refresh()
    const id = setInterval(refresh, 30000)
    return () => clearInterval(id)
  }, [refresh])

  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState("")
  const [sending, setSending] = useState(false)
  const [chatError, setChatError] = useState<string | null>(null)

  const send = async () => {
    const text = input.trim()
    if (!text || sending) return
    const next: ChatMessage[] = [...messages, { role: "user", content: text }]
    setMessages(next)
    setInput("")
    setChatError(null)
    setSending(true)
    try {
      const { reply } = await assistantApi.chat(next)
      setMessages((m) => [...m, { role: "assistant", content: reply }])
    } catch (e) {
      setChatError((e as { error?: string })?.error || "Chat failed")
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader
        title={t("nav.assistant")}
        subtitle={t("plat.assistantSubtitle")}
        actions={
          <>
            <button className="btn btn-sm btn-ghost btn-icon" onClick={refresh} title={t("acc.refresh")}>{I.refresh({ size: 13 })}</button>
            <button className="btn btn-sm btn-primary" onClick={refresh}>{I.sparkle({ size: 13 })}<span>{t("plat.runScan")}</span></button>
          </>
        }
      />
      <div style={{ padding: "0 24px 24px", overflow: "auto", flex: 1 }}>
        <div className="row gap-2" style={{ padding: "8px 12px", marginBottom: 16, borderRadius: 6, background: "rgba(96,165,250,.06)", border: "1px solid rgba(96,165,250,.25)", fontSize: 11.5, color: "var(--fg-3)" }}>
          <span style={{ color: "var(--info)" }}>{I.info({ size: 13 })}</span>
          <span>{t("plat.assistantNote")}</span>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "1.5fr 1fr", gap: 16, alignItems: "start" }}>
          <div className="col gap-4">
            <SectionPanel title={t("plat.findings")} icon={I.sparkle({ size: 13 })} count={findings.length}>
              <div className="col gap-3">
                {loading && findings.length === 0 && <div style={{ padding: 12, color: "var(--fg-4)", fontSize: 12.5 }}><span className="dot pulse ok" /> {t("common.loading")}</div>}
                {findings.map((f, i) => (
                  <div key={i} style={{ border: "1px solid var(--border)", borderRadius: 6, padding: 12, background: "var(--panel-2)" }}>
                    <div className="row gap-2" style={{ alignItems: "flex-start" }}>
                      <div style={{ width: 26, height: 26, borderRadius: 6, background: `color-mix(in srgb, ${kindColor[f.kind]} 12%, transparent)`, color: kindColor[f.kind], display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>{kindIcon(f.kind)}</div>
                      <div className="col flex-1" style={{ gap: 5, minWidth: 0 }}>
                        <span style={{ fontSize: 12, fontWeight: 500 }}>{f.title}</span>
                        <span className="muted" style={{ fontSize: 11.5 }}>{f.detail}</span>
                        {f.actions.length > 0 && (
                          <div className="row gap-1" style={{ flexWrap: "wrap", marginTop: 2 }}>
                            {f.actions.map((a) => <button key={a} className="btn btn-sm btn-ghost">{I.bolt({ size: 11 })}<span>{a}</span></button>)}
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </SectionPanel>

            <div className="card" style={{ padding: 16 }}>
              <div className="row gap-2" style={{ marginBottom: 14 }}>
                <span className="upper" style={{ color: "var(--fg-4)" }}>Chat</span>
                <span className="badge mono" style={{ fontSize: 10 }}>claude-opus · {TOOLS.length} tools</span>
              </div>
              <div className="col gap-3" style={{ marginBottom: 14 }}>
                {messages.length === 0 && (
                  <span className="muted" style={{ fontSize: 12 }}>{t("plat.askPlaceholder")}</span>
                )}
                {messages.map((m, i) => (
                  <div key={i} className="row gap-2" style={{ alignItems: "flex-start" }}>
                    <div style={{ width: 24, height: 24, borderRadius: "50%", background: "var(--panel-3)", color: "var(--fg-2)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 9, fontWeight: 700, flexShrink: 0 }}>
                      {m.role === "user" ? "You" : I.sparkle({ size: 12 })}
                    </div>
                    <div className="col" style={{ gap: 2, minWidth: 0 }}>
                      <span className={m.role === "assistant" ? "muted" : undefined} style={{ fontSize: 12, whiteSpace: "pre-wrap", wordBreak: "break-word" }}>{m.content}</span>
                    </div>
                  </div>
                ))}
                {sending && <div className="muted" style={{ fontSize: 12 }}><span className="dot pulse ok" /> {t("common.loading")}</div>}
                {chatError && <div style={{ fontSize: 12, color: "var(--crit)" }}>{chatError}</div>}
              </div>
              <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 10px", height: 36 }}>
                <span style={{ color: "var(--fg-4)" }}>{I.sparkle({ size: 14 })}</span>
                <input
                  placeholder={t("plat.askPlaceholder")}
                  value={input}
                  onChange={(e) => setInput(e.target.value)}
                  onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send() } }}
                  disabled={sending}
                  style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "inherit", fontSize: 12.5 }}
                />
                <span className="kbd">↵</span>
              </div>
            </div>
          </div>

          <div className="col gap-4">
            <SectionPanel title={t("plat.tools")} icon={I.bolt({ size: 13 })} count={TOOLS.length} bodyStyle={{ padding: 0 }}>
              <div className="col">
                {TOOLS.map((tool) => (
                  <div key={tool.name} className="row gap-2" style={{ padding: "9px 14px", borderBottom: "1px solid var(--border)", alignItems: "center" }}>
                    <span style={{ color: "var(--fg-4)" }}>{I.bolt({ size: 12 })}</span>
                    <div className="col flex-1" style={{ gap: 1, minWidth: 0 }}>
                      <span className="mono" style={{ fontSize: 11.5 }}>{tool.name}</span>
                      <span className="dim" style={{ fontSize: 10.5 }}>{tool.desc}</span>
                    </div>
                    {tool.danger && <span className="badge warn" style={{ fontSize: 9.5 }}>{t("plat.needConfirm")}</span>}
                  </div>
                ))}
              </div>
            </SectionPanel>

            <SectionPanel
              title={t("plat.recentCalls")}
              icon={I.audit({ size: 13 })}
              count={recent.length}
              bodyStyle={{ padding: 0 }}
              actions={<button className="btn btn-sm btn-ghost" onClick={() => navigate("audit")}>{t("plat.allAudit")}</button>}
            >
              <div className="col">
                {recent.length === 0 ? (
                  <div className="muted" style={{ padding: "12px 14px", fontSize: 12 }}>{t("common.noData")}</div>
                ) : (
                  recent.map((r) => (
                    <div key={r.id} className="row gap-2" style={{ padding: "9px 14px", borderBottom: "1px solid var(--border)", alignItems: "center" }}>
                      <span className={`dot ${r.success ? "ok" : "crit"}`} />
                      <div className="col flex-1" style={{ gap: 1, minWidth: 0 }}>
                        <span className="mono truncate" style={{ fontSize: 11.5 }}>{r.commandType}</span>
                        <span className="dim truncate" style={{ fontSize: 10.5 }}>{r.agentHostname || r.agentId}</span>
                      </div>
                      <span className="mono dim" style={{ fontSize: 10.5, flexShrink: 0 }}>{new Date(typeof r.timestamp === "string" ? r.timestamp : Number(r.timestamp)).toLocaleTimeString()}</span>
                    </div>
                  ))
                )}
              </div>
            </SectionPanel>
          </div>
        </div>
      </div>
    </div>
  )
}
