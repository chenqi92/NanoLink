import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { QRCodeSVG } from "qrcode.react"
import { alertsApi, type NotifyChannelModel, type AlertRuleModel } from "@/lib/api"
import { PageHeader, FormBlock } from "@/components/shell/primitives"
import { ContentState, InlineIssue, LoadingState, RequestState } from "@/components/shell/RequestState"
import { I } from "@/lib/icons"
import "./alert-config.css"

function Section({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="card" style={{ padding: 0 }}>
      <div className="row gap-2" style={{ padding: "12px 16px", borderBottom: "1px solid var(--border)", alignItems: "center", color: "var(--fg-2)" }}>
        <span style={{ color: "var(--fg-4)" }}>{icon}</span>
        <span style={{ fontSize: 12.5, fontWeight: 500 }}>{title}</span>
      </div>
      <div className="col" style={{ padding: 16, gap: 18 }}>{children}</div>
    </div>
  )
}

export function AlertConfigScreen() {
  const { t } = useTranslation()
  const [channels, setChannels] = useState<NotifyChannelModel[]>([])
  const [rules, setRules] = useState<AlertRuleModel[]>([])
  const [showAddChannel, setShowAddChannel] = useState(false)
  const [newChannel, setNewChannel] = useState({ kind: "webhook", name: "", target: "" })
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<unknown>(null)
  const [feedback, setFeedback] = useState<unknown>(null)
  const [testing, setTesting] = useState<number | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [channelData, ruleData] = await Promise.all([alertsApi.channels(), alertsApi.rules()])
      setChannels(channelData)
      setRules(ruleData)
    } catch (loadError) {
      setError(loadError)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { load() }, [load])

  async function createChannel() {
    setFeedback(null)
    try {
      await alertsApi.createChannel(newChannel)
      setNewChannel({ kind: "webhook", name: "", target: "" })
      setShowAddChannel(false)
      await load()
    } catch (actionError) {
      setFeedback(actionError)
    }
  }

  async function deleteChannel(id: number) {
    if (!confirm(t("plat.confirmDeleteChannel"))) return
    setFeedback(null)
    try {
      await alertsApi.deleteChannel(id)
      await load()
    } catch (actionError) {
      setFeedback(actionError)
    }
  }

  async function testChannel(id: number) {
    setTesting(id)
    setFeedback(null)
    try {
      await alertsApi.testChannel(id)
      setFeedback(t("plat.testSent"))
    } catch (actionError) {
      setFeedback(actionError)
    } finally {
      setTesting(null)
    }
  }

  const channelKinds = [
    { value: "webhook", label: "Webhook" },
    { value: "synology", label: t("plat.synology") },
    { value: "telegram", label: "Telegram" },
    { value: "wechat", label: t("plat.wechat") },
    { value: "wecom", label: t("plat.wecom") },
    { value: "feishu", label: t("plat.feishu") },
    { value: "dingtalk", label: t("plat.dingtalk") },
  ]

  const needsQRCode = ["wechat", "wecom", "feishu"].includes(newChannel.kind)

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader title={t("nav.alertConfig")} subtitle={t("plat.configSubtitle")} />
      <div style={{ padding: "0 24px 24px", overflow: "auto", flex: 1 }}>
        {feedback != null && (
          <div style={{ marginBottom: 14 }}>
            {typeof feedback === "string" ? (
              <div className="inline-issue" role="status"><span className="inline-issue__icon" style={{ color: "var(--ok)" }}>{I.check({ size: 13 })}</span><div className="inline-issue__copy"><strong>{feedback}</strong></div><button className="btn btn-sm btn-ghost btn-icon" onClick={() => setFeedback(null)} aria-label={t("common.cancel")}>{I.x({ size: 12 })}</button></div>
            ) : <InlineIssue error={feedback} onDismiss={() => setFeedback(null)} />}
          </div>
        )}

        {loading ? <LoadingState /> : error != null ? <RequestState error={error} onRetry={load} /> : (
        <div className="alert-config-grid">

        {/* 左侧：通知渠道 */}
        <Section title={t("plat.notifyChannels")} icon={I.bell({ size: 13 })}>
          <div className="col" style={{ gap: 12 }}>
            {channels.length === 0 && <ContentState kind="empty" title={t("common.noData")} compact />}
            {channels.map((ch) => (
              <div key={ch.id} className="row gap-3" style={{ padding: "10px 12px", background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, alignItems: "center" }}>
                <div className="col flex-1" style={{ gap: 2, minWidth: 0 }}>
                  <div className="row gap-2" style={{ alignItems: "center" }}>
                    <span style={{ fontSize: 13, fontWeight: 500 }}>{ch.name}</span>
                    <span className="badge" style={{ fontSize: 10 }}>{ch.kind}</span>
                    {ch.enabled && <span className="badge ok" style={{ fontSize: 10 }}>{t("plat.enabled")}</span>}
                  </div>
                  <span className="mono truncate" style={{ fontSize: 11, color: "var(--fg-4)" }}>{ch.target}</span>
                </div>
                <button className="btn btn-ghost btn-sm btn-icon" disabled={testing === ch.id} onClick={() => testChannel(ch.id)} title={t("plat.test")}>
                  {testing === ch.id ? <span className="dot pulse ok" /> : I.sparkle({ size: 14 })}
                </button>
                <button className="btn btn-ghost btn-sm btn-icon" onClick={() => deleteChannel(ch.id)} title={t("common.delete")}>
                  {I.trash({ size: 14 })}
                </button>
              </div>
            ))}
          </div>

          {!showAddChannel && (
            <button className="btn btn-sm btn-primary" onClick={() => setShowAddChannel(true)}>
              {I.plus({ size: 14 })} <span>{t("plat.addChannel")}</span>
            </button>
          )}

          {showAddChannel && (
            <div className="col" style={{ gap: 12, padding: 12, background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 8 }}>
              <FormBlock label={t("plat.channelType")}>
                <select className="input" value={newChannel.kind} onChange={(e) => setNewChannel({ ...newChannel, kind: e.target.value })}>
                  {channelKinds.map((k) => (
                    <option key={k.value} value={k.value}>{k.label}</option>
                  ))}
                </select>
              </FormBlock>

              <FormBlock label={t("plat.channelName")}>
                <input className="input" value={newChannel.name} onChange={(e) => setNewChannel({ ...newChannel, name: e.target.value })} placeholder={t("plat.channelNamePlaceholder")} />
              </FormBlock>

              <FormBlock label={t("plat.target")}>
                <input className="input" value={newChannel.target} onChange={(e) => setNewChannel({ ...newChannel, target: e.target.value })} placeholder={t("plat.targetPlaceholder")} />
              </FormBlock>

              {needsQRCode && newChannel.target && (
                <div className="col" style={{ gap: 8, alignItems: "center", padding: 12, background: "var(--panel)", border: "1px solid var(--border)", borderRadius: 6 }}>
                  <div style={{ width: 160, height: 160, background: "var(--bg)", border: "1px solid var(--border)", borderRadius: 6, display: "flex", alignItems: "center", justifyContent: "center" }}>
                    <QRCodeSVG value={newChannel.target} size={142} bgColor="transparent" fgColor="currentColor" title={t("plat.scanToVerify")} />
                  </div>
                  <span style={{ fontSize: 11, color: "var(--fg-3)", textAlign: "center" }}>{t("plat.scanToVerify")}</span>
                </div>
              )}

              <div className="row gap-2">
                <button className="btn btn-sm btn-primary" onClick={createChannel} disabled={!newChannel.name || !newChannel.target}>
                  {t("common.create")}
                </button>
                <button className="btn btn-sm" onClick={() => { setShowAddChannel(false); setNewChannel({ kind: "webhook", name: "", target: "" }); }}>
                  {t("common.cancel")}
                </button>
              </div>
            </div>
          )}
        </Section>

        {/* 右侧：告警规则映射 */}
        <Section title={t("plat.ruleChannelMapping")} icon={I.settings({ size: 13 })}>
          <div className="col" style={{ gap: 10 }}>
            {rules.length === 0 && <ContentState kind="empty" title={t("common.noData")} compact />}
            {rules.map((rule) => (
              <div key={rule.id} className="col" style={{ padding: "10px 12px", background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, gap: 8 }}>
                <div className="row gap-2" style={{ alignItems: "center", justifyContent: "space-between" }}>
                  <span style={{ fontSize: 13, fontWeight: 500 }}>{rule.name}</span>
                  <span className={`badge ${rule.severity === "crit" ? "crit" : "warn"}`} style={{ fontSize: 10 }}>
                    {rule.severity}
                  </span>
                </div>
                <div style={{ fontSize: 11, color: "var(--fg-3)" }}>
                  {rule.metric} {rule.operator} {rule.threshold}
                </div>
                <div className="col" style={{ gap: 6, marginTop: 4 }}>
                  <span style={{ fontSize: 10, color: "var(--fg-4)", textTransform: "uppercase", letterSpacing: "0.05em" }}>
                    {t("plat.sendTo")}
                  </span>
                  <div className="row gap-2" style={{ flexWrap: "wrap" }}>
                    {channels.filter(c => c.enabled).map((ch) => (
                      <span key={ch.id} className="row gap-1" style={{ alignItems: "center", fontSize: 11, padding: "3px 8px", background: "var(--panel)", border: "1px solid var(--border)", borderRadius: 4 }}>
                        <span className="dot ok" />
                        <span>{ch.name}</span>
                      </span>
                    ))}
                    {channels.filter(c => c.enabled).length === 0 && <span className="dim" style={{ fontSize: 11 }}>{t("common.noData")}</span>}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Section>
        </div>
        )}
      </div>
    </div>
  )
}
