import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useRouter } from "@/store/router"
import { PageHeader, FormBlock } from "@/components/shell/primitives"
import { Modal, ConfirmDialog } from "@/components/shell/Dialog"
import { alertsApi, type AlertInstanceDTO, type AlertRuleModel, type NotifyChannelModel } from "@/lib/api"

type Tab = "active" | "rules" | "channels"

function MiniStat({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="card" style={{ padding: "10px 14px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
      <div className="col" style={{ gap: 2 }}><div className="upper" style={{ color: "var(--fg-4)" }}>{label}</div><div className="num display" style={{ fontSize: 22, fontWeight: 500 }}>{value}</div></div>
      <span style={{ width: 4, height: 28, background: color, borderRadius: 2 }} />
    </div>
  )
}

function AlertCard({ a, onAck, onAgent }: { a: AlertInstanceDTO; onAck: () => void; onAgent: () => void }) {
  const { t } = useTranslation()
  const color = a.level === "crit" ? "var(--crit)" : a.level === "warn" ? "var(--warn)" : "var(--info)"
  return (
    <div className="card" style={{ padding: 14, borderLeft: `3px solid ${color}`, opacity: a.ack ? 0.7 : 1 }}>
      <div className="row gap-3" style={{ alignItems: "flex-start" }}>
        <div style={{ width: 30, height: 30, borderRadius: 6, background: `color-mix(in srgb, ${color} 12%, transparent)`, color, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>{I.warn({ size: 15 })}</div>
        <div className="col flex-1" style={{ gap: 6, minWidth: 0 }}>
          <div className="row gap-2" style={{ alignItems: "center", flexWrap: "wrap" }}>
            <span style={{ fontSize: 12.5, fontWeight: 500 }}>{a.title}</span>
            <span className="mono dim" style={{ fontSize: 10.5 }}>· {a.since}</span>
            {a.ack && <span className="badge ok" style={{ fontSize: 9.5 }}>{t("plat.acked")}{a.ackBy ? ` · ${a.ackBy}` : ""}</span>}
          </div>
          {a.desc && <div className="muted" style={{ fontSize: 11.5 }}>{a.desc}</div>}
          <div className="row gap-1" style={{ flexWrap: "wrap" }}>
            {a.agent && <button className="badge mono" style={{ cursor: "pointer" }} onClick={onAgent}>{a.agent}</button>}
            {a.rule && <span className="badge mono" style={{ fontSize: 10 }}>{a.rule}</span>}
          </div>
        </div>
        {!a.ack && <button className="btn btn-sm" onClick={onAck}>{I.check({ size: 12 })}<span>{t("plat.ack")}</span></button>}
      </div>
    </div>
  )
}

export function AlertsScreen() {
  const { t } = useTranslation()
  const { navigate } = useRouter()
  const [tab, setTab] = useState<Tab>("active")
  const [alerts, setAlerts] = useState<AlertInstanceDTO[]>([])
  const [rules, setRules] = useState<AlertRuleModel[]>([])
  const [channels, setChannels] = useState<NotifyChannelModel[]>([])
  const [loading, setLoading] = useState(true)
  const [newRule, setNewRule] = useState(false)
  const [newChannel, setNewChannel] = useState(false)
  const [delRule, setDelRule] = useState<AlertRuleModel | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [a, r, c] = await Promise.all([alertsApi.list(), alertsApi.rules().catch(() => []), alertsApi.channels().catch(() => [])])
      setAlerts(a)
      setRules(r)
      setChannels(c)
    } finally {
      setLoading(false)
    }
  }, [])
  useEffect(() => {
    load()
    const id = setInterval(() => alertsApi.list().then(setAlerts).catch(() => {}), 15000)
    return () => clearInterval(id)
  }, [load])

  const crit = alerts.filter((a) => a.level === "crit").length
  const warn = alerts.filter((a) => a.level === "warn").length
  const info = alerts.filter((a) => a.level === "info").length
  const unack = alerts.filter((a) => !a.ack).length

  async function ack(id: string) {
    await alertsApi.ack(id).catch(() => {})
    setAlerts((arr) => arr.map((a) => (a.id === id ? { ...a, ack: true } : a)))
  }
  async function ackAll() {
    await Promise.all(alerts.filter((a) => !a.ack).map((a) => alertsApi.ack(a.id).catch(() => {})))
    load()
  }
  async function toggleRule(r: AlertRuleModel) {
    await alertsApi.updateRule(r.id, { enabled: !r.enabled }).catch(() => {})
    setRules((rs) => rs.map((x) => (x.id === r.id ? { ...x, enabled: !x.enabled } : x)))
  }

  const tabs: { k: Tab; label: string; n: number }[] = [
    { k: "active", label: t("plat.active"), n: alerts.length },
    { k: "rules", label: t("plat.rules"), n: rules.length },
    { k: "channels", label: t("plat.channels"), n: channels.length },
  ]

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader
        title={t("nav.alerts")}
        subtitle={t("plat.alertsSubtitle")}
        actions={
          <>
            <button className="btn btn-sm" onClick={load}>{I.refresh({ size: 13 })}<span>{t("acc.refresh")}</span></button>
            {tab === "active" && <button className="btn btn-sm" onClick={ackAll} disabled={unack === 0}>{I.check({ size: 13 })}<span>{t("plat.ackAll")}</span></button>}
            {tab === "rules" && <button className="btn btn-sm btn-primary" onClick={() => setNewRule(true)}>{I.plus({ size: 13 })}<span>{t("plat.newRule")}</span></button>}
            {tab === "channels" && <button className="btn btn-sm btn-primary" onClick={() => setNewChannel(true)}>{I.plus({ size: 13 })}<span>{t("plat.addChannel")}</span></button>}
          </>
        }
      />
      <div style={{ padding: "0 24px", borderBottom: "1px solid var(--border)" }}>
        <div className="tabs" style={{ borderBottom: "none", marginBottom: -1 }}>
          {tabs.map((tb) => (
            <button key={tb.k} className={`tab ${tab === tb.k ? "active" : ""}`} onClick={() => setTab(tb.k)}>{tb.label} <span className="mono num dim">{tb.n}</span></button>
          ))}
        </div>
      </div>
      <div style={{ padding: "20px 24px", overflow: "auto", flex: 1 }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("common.loading")}</div>
        ) : tab === "active" ? (
          <>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12, marginBottom: 16 }}>
              <MiniStat label={t("plat.critical")} value={crit} color="var(--crit)" />
              <MiniStat label={t("plat.warning")} value={warn} color="var(--warn)" />
              <MiniStat label={t("plat.info")} value={info} color="var(--info)" />
              <MiniStat label={t("plat.unacknowledged")} value={unack} color="var(--fg-3)" />
            </div>
            {alerts.length === 0 ? (
              <div className="card" style={{ padding: "40px 24px", textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("plat.noAlerts")}</div>
            ) : (
              <div className="col gap-2">
                {alerts.map((a) => <AlertCard key={a.id} a={a} onAck={() => ack(a.id)} onAgent={() => navigate("agents")} />)}
              </div>
            )}
          </>
        ) : tab === "rules" ? (
          <div className="card" style={{ overflow: "auto" }}>
            <table className="tbl" style={{ minWidth: 760 }}>
              <thead><tr><th>{t("plat.rule")}</th><th>{t("plat.metric")}</th><th>{t("plat.threshold")}</th><th>{t("plat.severity")}</th><th>{t("dev.scope")}</th><th style={{ textAlign: "right" }}>{t("plat.enabled")}</th><th></th></tr></thead>
              <tbody>
                {rules.map((r) => (
                  <tr key={r.id}>
                    <td style={{ fontWeight: 500 }}>{r.name}</td>
                    <td><span className="badge mono">{r.metric}</span></td>
                    <td className="mono num">{r.metric === "offline" ? "—" : `${r.operator} ${r.threshold}%`}</td>
                    <td><span className={`badge ${r.severity === "crit" ? "crit" : r.severity === "warn" ? "warn" : "info"}`}>{r.severity}</span></td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{r.scope}</td>
                    <td style={{ textAlign: "right" }}>
                      <button className="btn btn-sm" onClick={() => toggleRule(r)} style={r.enabled ? { background: "var(--accent)", color: "var(--accent-fg)", borderColor: "var(--accent)" } : {}}>{r.enabled ? t("plat.enabled") : t("plat.disabled")}</button>
                    </td>
                    <td style={{ textAlign: "right" }}><button className="btn btn-sm btn-ghost btn-icon" onClick={() => setDelRule(r)}><span style={{ color: "var(--crit)" }}>{I.trash({ size: 12 })}</span></button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))", gap: 12 }}>
            {channels.map((c) => (
              <div key={c.id} className="card" style={{ padding: 14 }}>
                <div className="row gap-2" style={{ justifyContent: "space-between", alignItems: "center" }}>
                  <div className="row gap-2" style={{ alignItems: "center", minWidth: 0 }}>
                    <div style={{ width: 30, height: 30, borderRadius: 6, background: "var(--panel-2)", border: "1px solid var(--border)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--fg-3)", fontSize: 10, fontWeight: 700, textTransform: "uppercase" }}>{c.kind.slice(0, 2)}</div>
                    <div className="col" style={{ gap: 1, minWidth: 0 }}>
                      <span style={{ fontSize: 12.5, fontWeight: 500 }}>{c.name}</span>
                      <span className="mono dim truncate" style={{ fontSize: 10.5 }}>{c.target}</span>
                    </div>
                  </div>
                  <button className="btn btn-sm btn-ghost btn-icon" onClick={async () => { await alertsApi.deleteChannel(c.id).catch(() => {}); load() }}><span style={{ color: "var(--crit)" }}>{I.trash({ size: 12 })}</span></button>
                </div>
              </div>
            ))}
            {channels.length === 0 && <div className="muted" style={{ fontSize: 12.5 }}>{t("common.noData")}</div>}
          </div>
        )}
      </div>

      {newRule && <RuleModal onClose={() => setNewRule(false)} onDone={() => { setNewRule(false); load() }} />}
      {newChannel && <ChannelModal onClose={() => setNewChannel(false)} onDone={() => { setNewChannel(false); load() }} />}
      {delRule && <ConfirmDialog title={t("common.delete")} danger message={t("plat.deleteRuleConfirm", { name: delRule.name })} confirmLabel={t("common.delete")} onClose={() => setDelRule(null)} onConfirm={async () => { await alertsApi.deleteRule(delRule.id).catch(() => {}); setDelRule(null); load() }} />}
    </div>
  )
}

function RuleModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const { t } = useTranslation()
  const [name, setName] = useState("")
  const [metric, setMetric] = useState("cpu")
  const [operator, setOperator] = useState("gt")
  const [threshold, setThreshold] = useState(90)
  const [severity, setSeverity] = useState("warn")
  const [busy, setBusy] = useState(false)
  async function submit() {
    setBusy(true)
    try {
      await alertsApi.createRule({ name, metric, operator, threshold, severity })
      onDone()
    } finally { setBusy(false) }
  }
  return (
    <Modal title={t("plat.newRule")} onClose={onClose} footer={<><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-sm btn-primary" onClick={submit} disabled={busy || !name.trim()}>{busy && <span className="dot pulse ok" />}{t("common.create")}</button></>}>
      <div className="col gap-4">
        <FormBlock label={t("plat.name")}><input className="input" value={name} onChange={(e) => setName(e.target.value)} autoFocus /></FormBlock>
        <FormBlock label={t("plat.metric")}>
          <select className="select" value={metric} onChange={(e) => setMetric(e.target.value)}>
            <option value="cpu">CPU</option><option value="memory">Memory</option><option value="disk">Disk</option><option value="offline">Offline</option>
          </select>
        </FormBlock>
        {metric !== "offline" && (
          <div className="row gap-2">
            <FormBlock label={t("plat.operator")}><select className="select" value={operator} onChange={(e) => setOperator(e.target.value)}><option value="gt">{t("plat.gt")}</option><option value="lt">{t("plat.lt")}</option></select></FormBlock>
            <FormBlock label={t("plat.threshold")}><input className="input" type="number" value={threshold} onChange={(e) => setThreshold(Number(e.target.value))} /></FormBlock>
          </div>
        )}
        <FormBlock label={t("plat.severity")}>
          <select className="select" value={severity} onChange={(e) => setSeverity(e.target.value)}><option value="crit">crit</option><option value="warn">warn</option><option value="info">info</option></select>
        </FormBlock>
      </div>
    </Modal>
  )
}

function ChannelModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const { t } = useTranslation()
  const [kind, setKind] = useState("slack")
  const [name, setName] = useState("")
  const [target, setTarget] = useState("")
  const [busy, setBusy] = useState(false)
  async function submit() {
    setBusy(true)
    try {
      await alertsApi.createChannel({ kind, name, target })
      onDone()
    } finally { setBusy(false) }
  }
  return (
    <Modal title={t("plat.addChannel")} onClose={onClose} footer={<><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-sm btn-primary" onClick={submit} disabled={busy || !name.trim()}>{busy && <span className="dot pulse ok" />}{t("common.create")}</button></>}>
      <div className="col gap-4">
        <FormBlock label={t("plat.kind")}>
          <select className="select" value={kind} onChange={(e) => setKind(e.target.value)}><option value="slack">Slack</option><option value="email">Email</option><option value="webhook">Webhook</option><option value="pagerduty">PagerDuty</option><option value="sms">SMS</option></select>
        </FormBlock>
        <FormBlock label={t("plat.name")}><input className="input" value={name} onChange={(e) => setName(e.target.value)} autoFocus /></FormBlock>
        <FormBlock label={t("plat.target")}><input className="input" value={target} onChange={(e) => setTarget(e.target.value)} placeholder="webhook url / email / ..." /></FormBlock>
      </div>
    </Modal>
  )
}
