import { useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { alertsApi, type NotifyChannelModel, type AlertRuleModel } from "@/lib/api"
import { PageHeader, FormBlock } from "@/components/shell/primitives"
import { I } from "@/lib/icons"

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
  const [qrCode, setQrCode] = useState<string | null>(null)

  useEffect(() => {
    loadChannels()
    loadRules()
  }, [])

  async function loadChannels() {
    try {
      const data = await alertsApi.channels()
      setChannels(data)
    } catch (err) {
      console.error("Failed to load channels:", err)
    }
  }

  async function loadRules() {
    try {
      const data = await alertsApi.rules()
      setRules(data)
    } catch (err) {
      console.error("Failed to load rules:", err)
    }
  }

  async function createChannel() {
    try {
      await alertsApi.createChannel(newChannel)
      setNewChannel({ kind: "webhook", name: "", target: "" })
      setShowAddChannel(false)
      loadChannels()
    } catch (err) {
      console.error("Failed to create channel:", err)
    }
  }

  async function deleteChannel(id: number) {
    if (!confirm(t("alert.confirmDeleteChannel"))) return
    try {
      await alertsApi.deleteChannel(id)
      loadChannels()
    } catch (err) {
      console.error("Failed to delete channel:", err)
    }
  }

  async function testChannel(id: number) {
    try {
      await alertsApi.testChannel(id)
      alert(t("alert.testSent"))
    } catch {
      alert(t("alert.testFailed"))
    }
  }

  const channelKinds = [
    { value: "webhook", label: "Webhook" },
    { value: "synology", label: t("alert.synology") },
    { value: "telegram", label: "Telegram" },
    { value: "wechat", label: t("alert.wechat") },
    { value: "wecom", label: t("alert.wecom") },
    { value: "feishu", label: t("alert.feishu") },
    { value: "dingtalk", label: t("alert.dingtalk") },
  ]

  const needsQRCode = ["wechat", "wecom", "feishu"].includes(newChannel.kind)

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader title={t("nav.alertConfig")} subtitle={t("alert.configSubtitle")} />
      <div style={{ padding: "0 24px 24px", overflow: "auto", flex: 1, display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)", gap: 16, alignItems: "start" }}>

        {/* 左侧：通知渠道 */}
        <Section title={t("alert.notifyChannels")} icon={I.bell({ size: 13 })}>
          <div className="col" style={{ gap: 12 }}>
            {channels.map((ch) => (
              <div key={ch.id} className="row gap-3" style={{ padding: "10px 12px", background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, alignItems: "center" }}>
                <div className="col flex-1" style={{ gap: 2, minWidth: 0 }}>
                  <div className="row gap-2" style={{ alignItems: "center" }}>
                    <span style={{ fontSize: 13, fontWeight: 500 }}>{ch.name}</span>
                    <span className="badge" style={{ fontSize: 10 }}>{ch.kind}</span>
                    {ch.enabled && <span className="badge ok" style={{ fontSize: 10 }}>{t("alert.enabled")}</span>}
                  </div>
                  <span className="mono truncate" style={{ fontSize: 11, color: "var(--fg-4)" }}>{ch.target}</span>
                </div>
                <button className="btn btn-ghost btn-sm btn-icon" onClick={() => testChannel(ch.id)} title={t("alert.test")}>
                  {I.sparkle({ size: 14 })}
                </button>
                <button className="btn btn-ghost btn-sm btn-icon" onClick={() => deleteChannel(ch.id)} title={t("common.delete")}>
                  {I.trash({ size: 14 })}
                </button>
              </div>
            ))}
          </div>

          {!showAddChannel && (
            <button className="btn btn-sm btn-primary" onClick={() => setShowAddChannel(true)}>
              {I.add({ size: 14 })} <span>{t("alert.addChannel")}</span>
            </button>
          )}

          {showAddChannel && (
            <div className="col" style={{ gap: 12, padding: 12, background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 8 }}>
              <FormBlock label={t("alert.channelType")}>
                <select className="input" value={newChannel.kind} onChange={(e) => setNewChannel({ ...newChannel, kind: e.target.value })}>
                  {channelKinds.map((k) => (
                    <option key={k.value} value={k.value}>{k.label}</option>
                  ))}
                </select>
              </FormBlock>

              <FormBlock label={t("alert.channelName")}>
                <input className="input" value={newChannel.name} onChange={(e) => setNewChannel({ ...newChannel, name: e.target.value })} placeholder={t("alert.channelNamePlaceholder")} />
              </FormBlock>

              <FormBlock label={t("alert.target")}>
                <input className="input" value={newChannel.target} onChange={(e) => setNewChannel({ ...newChannel, target: e.target.value })} placeholder={t("alert.targetPlaceholder")} />
              </FormBlock>

              {needsQRCode && newChannel.target && (
                <div className="col" style={{ gap: 8, alignItems: "center", padding: 12, background: "var(--panel)", border: "1px solid var(--border)", borderRadius: 6 }}>
                  <div style={{ width: 160, height: 160, background: "var(--bg)", border: "1px solid var(--border)", borderRadius: 6, display: "flex", alignItems: "center", justifyContent: "center" }}>
                    {qrCode ? <img src={qrCode} alt="QR Code" style={{ width: "100%", height: "100%", objectFit: "contain" }} /> : <span style={{ color: "var(--fg-4)", fontSize: 11 }}>{t("alert.qrPlaceholder")}</span>}
                  </div>
                  <span style={{ fontSize: 11, color: "var(--fg-3)", textAlign: "center" }}>{t("alert.scanToVerify")}</span>
                </div>
              )}

              <div className="row gap-2">
                <button className="btn btn-sm btn-primary" onClick={createChannel} disabled={!newChannel.name || !newChannel.target}>
                  {t("common.create")}
                </button>
                <button className="btn btn-sm" onClick={() => { setShowAddChannel(false); setNewChannel({ kind: "webhook", name: "", target: "" }); setQrCode(null); }}>
                  {t("common.cancel")}
                </button>
              </div>
            </div>
          )}
        </Section>

        {/* 右侧：告警规则映射 */}
        <Section title={t("alert.ruleChannelMapping")} icon={I.settings({ size: 13 })}>
          <div className="col" style={{ gap: 10 }}>
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
                    {t("alert.sendTo")}
                  </span>
                  <div className="row gap-2" style={{ flexWrap: "wrap" }}>
                    {channels.filter(c => c.enabled).map((ch) => (
                      <label key={ch.id} className="row gap-1" style={{ alignItems: "center", fontSize: 11, padding: "3px 8px", background: "var(--panel)", border: "1px solid var(--border)", borderRadius: 4, cursor: "pointer" }}>
                        <input type="checkbox" defaultChecked style={{ width: 12, height: 12 }} />
                        <span>{ch.name}</span>
                      </label>
                    ))}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Section>
      </div>
    </div>
  )
}
