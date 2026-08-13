import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import type { TFunction } from "i18next"
import { I } from "@/lib/icons"
import { useRouter } from "@/store/router"
import { PageHeader, FormBlock } from "@/components/shell/primitives"
import { Modal, ConfirmDialog } from "@/components/shell/Dialog"
import { alertsApi, type AlertInstanceDTO, type AlertRuleModel, type NotifyChannelModel, type SilenceModel } from "@/lib/api"
import { useAuth } from "@/contexts/AuthContext"
import { InlineIssue } from "@/components/shell/RequestState"

type Tab = "active" | "rules" | "channels" | "silences"

const OP_SYMBOL: Record<string, string> = { gt: ">", lt: "<", ge: "≥", le: "≤", eq: "=" }

/** Build a human expression for a rule, e.g. "cpu > 90% for 5m". */
function ruleExpression(r: AlertRuleModel, t: TFunction): string {
  if (r.metric === "offline") return t("status.offline")
  const op = OP_SYMBOL[r.operator] ?? r.operator
  const metricKey = r.metric === "cpu" ? "metrics.cpu" : r.metric === "memory" ? "metrics.memory" : r.metric === "disk" ? "metrics.disk" : r.metric
  const base = `${t(metricKey)} ${op} ${r.threshold}%`
  if (r.durationSec && r.durationSec > 0) {
    const m = Math.round(r.durationSec / 60)
    return m >= 1
      ? t("plat.ruleForMinutes", { expression: base, count: m })
      : t("plat.ruleForSeconds", { expression: base, count: r.durationSec })
  }
  return base
}

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
  const { user } = useAuth()
  const isAdmin = !!user?.isSuperAdmin
  const [tab, setTab] = useState<Tab>("active")
  const [alerts, setAlerts] = useState<AlertInstanceDTO[]>([])
  const [rules, setRules] = useState<AlertRuleModel[]>([])
  const [channels, setChannels] = useState<NotifyChannelModel[]>([])
  const [silences, setSilences] = useState<SilenceModel[]>([])
  const [loading, setLoading] = useState(true)
  const [newRule, setNewRule] = useState(false)
  const [newChannel, setNewChannel] = useState(false)
  const [newSilence, setNewSilence] = useState(false)
  const [delRule, setDelRule] = useState<AlertRuleModel | null>(null)
  const [testing, setTesting] = useState<number | null>(null)
  const [err, setErr] = useState<unknown>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setErr(null)
    try {
      const a = await alertsApi.list()
      setAlerts(a)
      if (isAdmin) {
        const [r, c, s] = await Promise.all([alertsApi.rules(), alertsApi.channels(), alertsApi.silences()])
        setRules(r)
        setChannels(c)
        setSilences(s)
      } else {
        setRules([])
        setChannels([])
        setSilences([])
      }
    } catch (e) {
      setErr(e)
    } finally {
      setLoading(false)
    }
  }, [isAdmin])
  useEffect(() => {
    load()
    const id = setInterval(() => alertsApi.list().then(setAlerts).catch(() => {}), 15000)
    return () => clearInterval(id)
  }, [load])

  useEffect(() => {
    if (!isAdmin && tab !== "active") setTab("active")
  }, [isAdmin, tab])

  const crit = alerts.filter((a) => a.level === "crit").length
  const warn = alerts.filter((a) => a.level === "warn").length
  const info = alerts.filter((a) => a.level === "info").length
  const unack = alerts.filter((a) => !a.ack).length

  async function ack(id: string) {
    try {
      await alertsApi.ack(id)
      setAlerts((arr) => arr.map((a) => (a.id === id ? { ...a, ack: true } : a)))
    } catch (e) {
      setErr(e)
    }
  }
  async function ackAll() {
    try {
      await Promise.all(alerts.filter((a) => !a.ack).map((a) => alertsApi.ack(a.id)))
      await load()
    } catch (e) {
      setErr(e)
    }
  }
  async function toggleRule(r: AlertRuleModel) {
    try {
      await alertsApi.updateRule(r.id, { enabled: !r.enabled })
      setRules((rs) => rs.map((x) => (x.id === r.id ? { ...x, enabled: !x.enabled } : x)))
    } catch (e) {
      setErr(e)
    }
  }

  async function testChannel(id: number) {
    setTesting(id)
    setErr(null)
    try {
      await alertsApi.testChannel(id)
      load()
    } catch (e) {
      setErr(e)
    } finally {
      setTesting(null)
    }
  }

  const tabs: { k: Tab; label: string; n: number }[] = [
    { k: "active", label: t("plat.active"), n: alerts.length },
    ...(isAdmin ? [
      { k: "rules" as Tab, label: t("plat.rules"), n: rules.length },
      { k: "channels" as Tab, label: t("plat.channels"), n: channels.length },
      { k: "silences" as Tab, label: t("plat.silences"), n: silences.length },
    ] : []),
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
            {isAdmin && tab === "rules" && <button className="btn btn-sm btn-primary" onClick={() => setNewRule(true)}>{I.plus({ size: 13 })}<span>{t("plat.newRule")}</span></button>}
            {isAdmin && tab === "channels" && <button className="btn btn-sm btn-primary" onClick={() => setNewChannel(true)}>{I.plus({ size: 13 })}<span>{t("plat.addChannel")}</span></button>}
            {isAdmin && tab === "silences" && <button className="btn btn-sm btn-primary" onClick={() => setNewSilence(true)}>{I.plus({ size: 13 })}<span>{t("plat.newSilence")}</span></button>}
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
        {err != null && <div style={{ marginBottom: 12 }}><InlineIssue error={err} onDismiss={() => setErr(null)} /></div>}
        {loading ? (
          <div style={{ padding: 40, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("common.loading")}</div>
        ) : tab === "active" ? (
          <>
            <div className="kpi-grid" style={{ gap: 12, marginBottom: 16 }}>
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
              <thead><tr><th>{t("plat.rule")}</th><th>{t("plat.expression")}</th><th>{t("plat.severity")}</th><th>{t("dev.scope")}</th><th>{t("plat.lastFired")}</th><th style={{ textAlign: "right" }}>{t("plat.enabled")}</th><th></th></tr></thead>
              <tbody>
                {rules.map((r) => (
                  <tr key={r.id}>
                    <td style={{ fontWeight: 500 }}>{r.name}</td>
                    <td><code className="mono" style={{ fontSize: 11.5, color: "var(--fg-2)" }}>{ruleExpression(r, t)}</code></td>
                    <td><span className={`badge ${r.severity === "crit" ? "crit" : r.severity === "warn" ? "warn" : "info"}`}>{r.severity}</span></td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{r.scope}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{r.lastFiredAt ? new Date(r.lastFiredAt).toLocaleString() : "—"}</td>
                    <td style={{ textAlign: "right" }}>
                      <button className="btn btn-sm" onClick={() => toggleRule(r)} style={r.enabled ? { background: "var(--accent)", color: "var(--accent-fg)", borderColor: "var(--accent)" } : {}}>{r.enabled ? t("plat.enabled") : t("plat.disabled")}</button>
                    </td>
                    <td style={{ textAlign: "right" }}><button className="btn btn-sm btn-ghost btn-icon" onClick={() => setDelRule(r)}><span style={{ color: "var(--crit)" }}>{I.trash({ size: 12 })}</span></button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : tab === "channels" ? (
          <div className="auto-card-grid-320" style={{ gap: 12 }}>
            {channels.map((c) => (
              <div key={c.id} className="card" style={{ padding: 14 }}>
                <div className="row gap-2" style={{ justifyContent: "space-between", alignItems: "center" }}>
                  <div className="row gap-2" style={{ alignItems: "center", minWidth: 0 }}>
                    <div style={{ width: 30, height: 30, borderRadius: 6, background: "var(--panel-2)", border: "1px solid var(--border)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--fg-3)", fontSize: 10, fontWeight: 700, textTransform: "uppercase" }}>{c.kind.slice(0, 2)}</div>
                    <div className="col" style={{ gap: 1, minWidth: 0 }}>
                      <div className="row gap-2" style={{ alignItems: "center" }}>
                        <span style={{ fontSize: 12.5, fontWeight: 500 }}>{c.name}</span>
                        <span className={`badge ${c.status === "ok" ? "ok" : c.status === "warn" ? "warn" : ""}`} style={{ fontSize: 9.5 }}>{c.enabled ? t("plat.channelEnabled") : t("plat.channelDisabled")}</span>
                      </div>
                      <span className="mono dim truncate" style={{ fontSize: 10.5 }}>{c.target}</span>
                      {c.lastUsedAt && <span className="dim" style={{ fontSize: 10 }}>{t("plat.lastUsed")} {new Date(c.lastUsedAt).toLocaleString()}</span>}
                    </div>
                  </div>
                  <div className="row gap-1">
                    <button className="btn btn-sm btn-ghost" disabled={testing === c.id} onClick={() => testChannel(c.id)}>{testing === c.id ? <span className="dot pulse ok" /> : I.bolt({ size: 12 })}<span>{t("plat.test")}</span></button>
                    <button className="btn btn-sm btn-ghost btn-icon" onClick={async () => { try { await alertsApi.deleteChannel(c.id); await load() } catch (e) { setErr(e) } }}><span style={{ color: "var(--crit)" }}>{I.trash({ size: 12 })}</span></button>
                  </div>
                </div>
              </div>
            ))}
            {channels.length === 0 && <div className="muted" style={{ fontSize: 12.5 }}>{t("common.noData")}</div>}
          </div>
        ) : (
          <div className="col gap-2">
            {silences.length === 0 ? (
              <div className="card" style={{ padding: "40px 24px", textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>
                <div style={{ marginBottom: 10 }}>{I.shield({ size: 28 })}</div>
                {t("plat.noSilences")}
              </div>
            ) : (
              silences.map((s) => (
                <div key={s.id} className="card" style={{ padding: 14 }}>
                  <div className="row gap-3" style={{ alignItems: "center", justifyContent: "space-between" }}>
                    <div className="col" style={{ gap: 3, minWidth: 0 }}>
                      <div className="row gap-2" style={{ alignItems: "center", flexWrap: "wrap" }}>
                        <span style={{ color: "var(--fg-3)" }}>{I.shield({ size: 13 })}</span>
                        <span className="mono" style={{ fontWeight: 500 }}>{s.matcher}</span>
                        {s.reason && <span className="muted" style={{ fontSize: 11.5 }}>{s.reason}</span>}
                      </div>
                      <span className="dim" style={{ fontSize: 11 }}>{t("plat.until")} {new Date(s.until).toLocaleString()}{s.createdBy ? ` · ${s.createdBy}` : ""}</span>
                    </div>
                    <button className="btn btn-sm btn-ghost btn-icon" onClick={async () => { try { await alertsApi.deleteSilence(s.id); await load() } catch (e) { setErr(e) } }}><span style={{ color: "var(--crit)" }}>{I.trash({ size: 12 })}</span></button>
                  </div>
                </div>
              ))
            )}
          </div>
        )}
      </div>

      {newRule && <RuleModal onClose={() => setNewRule(false)} onDone={() => { setNewRule(false); load() }} onError={setErr} />}
      {newChannel && <ChannelModal onClose={() => setNewChannel(false)} onDone={() => { setNewChannel(false); load() }} onError={setErr} />}
      {newSilence && <SilenceModal onClose={() => setNewSilence(false)} onDone={() => { setNewSilence(false); load() }} onError={setErr} />}
      {delRule && <ConfirmDialog title={t("common.delete")} danger message={t("plat.deleteRuleConfirm", { name: delRule.name })} confirmLabel={t("common.delete")} onClose={() => setDelRule(null)} onConfirm={async () => { try { await alertsApi.deleteRule(delRule.id); setDelRule(null); await load() } catch (e) { setErr(e) } }} />}
    </div>
  )
}

function RuleModal({ onClose, onDone, onError }: { onClose: () => void; onDone: () => void; onError: (error: unknown) => void }) {
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
    } catch (error) {
      onError(error)
    } finally { setBusy(false) }
  }
  return (
    <Modal title={t("plat.newRule")} onClose={onClose} footer={<><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-sm btn-primary" onClick={submit} disabled={busy || !name.trim()}>{busy && <span className="dot pulse ok" />}{t("common.create")}</button></>}>
      <div className="col gap-4">
        <FormBlock label={t("plat.name")}><input className="input" value={name} onChange={(e) => setName(e.target.value)} autoFocus /></FormBlock>
        <FormBlock label={t("plat.metric")}>
          <select className="select" value={metric} onChange={(e) => setMetric(e.target.value)}>
            <option value="cpu">{t("metrics.cpu")}</option><option value="memory">{t("metrics.memory")}</option><option value="disk">{t("metrics.disk")}</option><option value="offline">{t("status.offline")}</option>
          </select>
        </FormBlock>
        {metric !== "offline" && (
          <div className="row gap-2">
            <FormBlock label={t("plat.operator")}><select className="select" value={operator} onChange={(e) => setOperator(e.target.value)}><option value="gt">{t("plat.gt")}</option><option value="lt">{t("plat.lt")}</option></select></FormBlock>
            <FormBlock label={t("plat.threshold")}><input className="input" type="number" value={threshold} onChange={(e) => setThreshold(Number(e.target.value))} /></FormBlock>
          </div>
        )}
        <FormBlock label={t("plat.severity")}>
          <select className="select" value={severity} onChange={(e) => setSeverity(e.target.value)}><option value="crit">{t("plat.critical")}</option><option value="warn">{t("plat.warning")}</option><option value="info">{t("plat.info")}</option></select>
        </FormBlock>
      </div>
    </Modal>
  )
}

function ChannelModal({ onClose, onDone, onError }: { onClose: () => void; onDone: () => void; onError: (error: unknown) => void }) {
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
    } catch (error) {
      onError(error)
    } finally { setBusy(false) }
  }
  return (
    <Modal title={t("plat.addChannel")} onClose={onClose} footer={<><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-sm btn-primary" onClick={submit} disabled={busy || !name.trim()}>{busy && <span className="dot pulse ok" />}{t("common.create")}</button></>}>
      <div className="col gap-4">
        <FormBlock label={t("plat.kind")}>
          <select className="select" value={kind} onChange={(e) => setKind(e.target.value)}><option value="slack">{t("plat.channelKinds.slack")}</option><option value="email">{t("plat.channelKinds.email")}</option><option value="webhook">{t("plat.channelKinds.webhook")}</option><option value="pagerduty">{t("plat.channelKinds.pagerduty")}</option><option value="sms">{t("plat.channelKinds.sms")}</option></select>
        </FormBlock>
        <FormBlock label={t("plat.name")}><input className="input" value={name} onChange={(e) => setName(e.target.value)} autoFocus /></FormBlock>
        <FormBlock label={t("plat.target")}><input className="input" value={target} onChange={(e) => setTarget(e.target.value)} placeholder={t("plat.channelTargetPlaceholder")} /></FormBlock>
      </div>
    </Modal>
  )
}

function SilenceModal({ onClose, onDone, onError }: { onClose: () => void; onDone: () => void; onError: (error: unknown) => void }) {
  const { t } = useTranslation()
  const [matcher, setMatcher] = useState("all")
  const [reason, setReason] = useState("")
  const [durationMin, setDurationMin] = useState(60)
  const [busy, setBusy] = useState(false)
  async function submit() {
    setBusy(true)
    try {
      await alertsApi.createSilence({ matcher: matcher.trim() || "all", reason, durationMin })
      onDone()
    } catch (error) {
      onError(error)
    } finally { setBusy(false) }
  }
  return (
    <Modal title={t("plat.newSilence")} onClose={onClose} footer={<><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-sm btn-primary" onClick={submit} disabled={busy || durationMin < 1}>{busy && <span className="dot pulse ok" />}{t("common.create")}</button></>}>
      <div className="col gap-4">
        <FormBlock label={t("plat.matcher")}><input className="input" value={matcher} onChange={(e) => setMatcher(e.target.value)} placeholder={t("plat.silenceMatcherPlaceholder")} autoFocus /></FormBlock>
        <FormBlock label={t("plat.reason")}><input className="input" value={reason} onChange={(e) => setReason(e.target.value)} placeholder={t("plat.silenceReasonPlaceholder")} /></FormBlock>
        <FormBlock label={`${t("plat.duration")} (${t("plat.minutesShort")})`}><input className="input" type="number" min={1} value={durationMin} onChange={(e) => setDurationMin(Number(e.target.value))} /></FormBlock>
      </div>
    </Modal>
  )
}
