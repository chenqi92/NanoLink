import { useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { PageHeader, SectionPanel } from "@/components/shell/primitives"
import { assistantApi, type FindingDTO } from "@/lib/api"

type Finding = FindingDTO

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
  const [findings, setFindings] = useState<Finding[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let alive = true
    const fetchFindings = () =>
      assistantApi
        .findings()
        .then((f) => alive && setFindings(f))
        .catch(() => {})
        .finally(() => alive && setLoading(false))
    fetchFindings()
    const id = setInterval(fetchFindings, 30000)
    return () => {
      alive = false
      clearInterval(id)
    }
  }, [])

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader title={t("nav.assistant")} subtitle={t("plat.assistantSubtitle")} />
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
                      <div style={{ width: 26, height: 26, borderRadius: 6, background: `color-mix(in srgb, ${kindColor[f.kind]} 12%, transparent)`, color: kindColor[f.kind], display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>{I.bolt({ size: 13 })}</div>
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
                <div className="row gap-2" style={{ alignItems: "flex-start" }}>
                  <div style={{ width: 24, height: 24, borderRadius: "50%", background: "var(--panel-3)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 9, fontWeight: 700, flexShrink: 0 }}>AZ</div>
                  <div className="col" style={{ gap: 2 }}><span style={{ fontSize: 12 }}>Which agents are at risk right now?</span></div>
                </div>
                <div className="row gap-2" style={{ alignItems: "flex-start" }}>
                  <div style={{ width: 24, height: 24, borderRadius: "50%", background: "var(--panel-3)", color: "var(--fg-2)", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>{I.sparkle({ size: 12 })}</div>
                  <div className="col" style={{ gap: 6 }}>
                    <span className="muted" style={{ fontSize: 12 }}>3 agents need attention: db-primary-2 (memory 91%), ml-train-04 (GPU sustained 96%), rpi-monitor-7 (offline 3h).</span>
                    <div className="code" style={{ fontSize: 11 }}>get_system_summary() → 7 online · find_high_cpu_agents(85) → 2 hits</div>
                  </div>
                </div>
              </div>
              <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 10px", height: 36 }}>
                <span style={{ color: "var(--fg-4)" }}>{I.sparkle({ size: 14 })}</span>
                <input placeholder={t("plat.askPlaceholder")} disabled style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "inherit", fontSize: 12.5 }} />
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
                    {tool.danger && <span className="badge crit" style={{ fontSize: 9.5 }}>danger</span>}
                  </div>
                ))}
              </div>
            </SectionPanel>
          </div>
        </div>
      </div>
    </div>
  )
}
