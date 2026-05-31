import { useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useRouter } from "@/store/router"
import { PageHeader } from "@/components/shell/primitives"
import { SAMPLE_ALERTS, SAMPLE_ALERT_RULES, SAMPLE_CHANNELS, type AlertItem } from "@/lib/sampledata"

type Tab = "active" | "rules" | "channels"

function PreviewBanner() {
  const { t } = useTranslation()
  return (
    <div className="row gap-2" style={{ padding: "8px 12px", marginBottom: 14, borderRadius: 6, background: "rgba(96,165,250,.06)", border: "1px solid rgba(96,165,250,.25)", fontSize: 11.5, color: "var(--fg-3)" }}>
      <span style={{ color: "var(--info)" }}>{I.info({ size: 13 })}</span>
      <span>{t("dev.preview")}</span>
    </div>
  )
}

function MiniStat({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="card" style={{ padding: "10px 14px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
      <div className="col" style={{ gap: 2 }}><div className="upper" style={{ color: "var(--fg-4)" }}>{label}</div><div className="num display" style={{ fontSize: 22, fontWeight: 500 }}>{value}</div></div>
      <span style={{ width: 4, height: 28, background: color, borderRadius: 2 }} />
    </div>
  )
}

function AlertCard({ a, onAck, onAgent }: { a: AlertItem; onAck: () => void; onAgent: () => void }) {
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
          <div className="muted" style={{ fontSize: 11.5 }}>{a.desc}</div>
          <div className="row gap-1" style={{ flexWrap: "wrap" }}>
            <button className="badge mono" style={{ cursor: "pointer" }} onClick={onAgent}>{a.agent}</button>
            <span className="badge mono" style={{ fontSize: 10 }}>{a.rule}</span>
            {a.runbook && <span className="badge" style={{ fontSize: 10 }}>{I.external({ size: 10 })} {t("plat.runbook")}</span>}
          </div>
        </div>
        <div className="row gap-1">
          {!a.ack && <button className="btn btn-sm" onClick={onAck}>{I.check({ size: 12 })}<span>{t("plat.ack")}</span></button>}
          <button className="btn btn-sm btn-ghost">{t("plat.silence")}</button>
        </div>
      </div>
    </div>
  )
}

export function AlertsScreen() {
  const { t } = useTranslation()
  const { navigate } = useRouter()
  const [tab, setTab] = useState<Tab>("active")
  const [alerts, setAlerts] = useState<AlertItem[]>(SAMPLE_ALERTS)

  const crit = alerts.filter((a) => a.level === "crit").length
  const warn = alerts.filter((a) => a.level === "warn").length
  const info = alerts.filter((a) => a.level === "info").length
  const unack = alerts.filter((a) => !a.ack).length

  const ack = (id: string) => setAlerts((arr) => arr.map((a) => (a.id === id ? { ...a, ack: true } : a)))
  const ackAll = () => setAlerts((arr) => arr.map((a) => ({ ...a, ack: true })))

  const tabs: { k: Tab; label: string; n: number }[] = [
    { k: "active", label: t("plat.active"), n: alerts.length },
    { k: "rules", label: t("plat.rules"), n: SAMPLE_ALERT_RULES.length },
    { k: "channels", label: t("plat.channels"), n: SAMPLE_CHANNELS.length },
  ]

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader
        title={t("nav.alerts")}
        subtitle={t("plat.alertsSubtitle")}
        actions={
          <>
            <button className="btn btn-sm" onClick={ackAll}>{I.check({ size: 13 })}<span>{t("plat.ackAll")}</span></button>
            <button className="btn btn-sm btn-primary">{I.plus({ size: 13 })}<span>{t("plat.newRule")}</span></button>
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
        <PreviewBanner />
        {tab === "active" && (
          <>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12, marginBottom: 16 }}>
              <MiniStat label={t("plat.critical")} value={crit} color="var(--crit)" />
              <MiniStat label={t("plat.warning")} value={warn} color="var(--warn)" />
              <MiniStat label={t("plat.info")} value={info} color="var(--info)" />
              <MiniStat label={t("plat.unacknowledged")} value={unack} color="var(--fg-3)" />
            </div>
            <div className="col gap-2">
              {alerts.map((a) => <AlertCard key={a.id} a={a} onAck={() => ack(a.id)} onAgent={() => navigate("agents")} />)}
            </div>
          </>
        )}
        {tab === "rules" && (
          <div className="card" style={{ overflow: "auto" }}>
            <table className="tbl" style={{ minWidth: 820 }}>
              <thead><tr><th>{t("plat.rule")}</th><th>{t("plat.params")}</th><th>{t("dev.scope")}</th><th>{t("plat.severity")}</th><th>{t("plat.channels")}</th><th>{t("plat.lastFired")}</th><th style={{ textAlign: "right" }}>{t("plat.enabled")}</th></tr></thead>
              <tbody>
                {SAMPLE_ALERT_RULES.map((r) => (
                  <tr key={r.id}>
                    <td style={{ fontWeight: 500 }}>{r.name}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{r.expr}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{r.scope}</td>
                    <td><span className={`badge ${r.severity === "crit" ? "crit" : "warn"}`}>{r.severity}</span></td>
                    <td><div className="row gap-1">{r.channels.map((c) => <span key={c} className="badge mono" style={{ fontSize: 10 }}>{c}</span>)}</div></td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{r.lastFired}</td>
                    <td style={{ textAlign: "right" }}><span className={`badge ${r.enabled ? "ok" : ""}`}>{r.enabled ? t("plat.enabled") : t("plat.disabled")}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {tab === "channels" && (
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))", gap: 12 }}>
            {SAMPLE_CHANNELS.map((c) => (
              <div key={c.id} className="card" style={{ padding: 14 }}>
                <div className="row gap-2" style={{ justifyContent: "space-between", alignItems: "center" }}>
                  <div className="row gap-2" style={{ alignItems: "center", minWidth: 0 }}>
                    <div style={{ width: 30, height: 30, borderRadius: 6, background: "var(--panel-2)", border: "1px solid var(--border)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--fg-3)", fontSize: 10, fontWeight: 700, textTransform: "uppercase" }}>{c.kind.slice(0, 2)}</div>
                    <div className="col" style={{ gap: 1, minWidth: 0 }}>
                      <span style={{ fontSize: 12.5, fontWeight: 500 }}>{c.name}</span>
                      <span className="mono dim truncate" style={{ fontSize: 10.5 }}>{c.target}</span>
                    </div>
                  </div>
                  <span className={`dot ${c.status === "ok" ? "ok" : c.status === "warn" ? "warn" : "crit"}`} />
                </div>
                <div className="hr" />
                <div className="row" style={{ justifyContent: "space-between", fontSize: 11 }}><span className="muted">{t("acc.lastUsed")}</span><span className="mono">{c.lastUsed}</span></div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
