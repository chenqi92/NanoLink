import { useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { PageHeader } from "@/components/shell/primitives"
import { SAMPLE_CONFIGS, SAMPLE_SCRIPTS, SAMPLE_PACKAGES, SAMPLE_HEALTH } from "@/lib/sampledata"

type Tab = "configs" | "scripts" | "packages" | "health"

function PreviewBanner() {
  const { t } = useTranslation()
  return (
    <div className="row gap-2" style={{ padding: "8px 12px", marginBottom: 14, borderRadius: 6, background: "rgba(96,165,250,.06)", border: "1px solid rgba(96,165,250,.25)", fontSize: 11.5, color: "var(--fg-3)" }}>
      <span style={{ color: "var(--info)" }}>{I.info({ size: 13 })}</span>
      <span>{t("dev.preview")}</span>
    </div>
  )
}

function MiniStat({ label, value, color, action }: { label: string; value: number; color: string; action?: React.ReactNode }) {
  return (
    <div className="card" style={{ padding: "10px 14px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
      <div className="col" style={{ gap: 2 }}>
        <div className="upper" style={{ color: "var(--fg-4)" }}>{label}</div>
        <div className="num display" style={{ fontSize: 22, fontWeight: 500 }}>{value}</div>
      </div>
      {action ?? <span style={{ width: 4, height: 28, background: color, borderRadius: 2 }} />}
    </div>
  )
}

function ConfigsPanel() {
  const { t } = useTranslation()
  return (
    <div className="card" style={{ overflow: "auto" }}>
      <table className="tbl" style={{ minWidth: 880 }}>
        <thead><tr><th>{t("dev.path")}</th><th>{t("dev.agent")}</th><th>{t("dev.size")}</th><th>{t("dev.modified")}</th><th>{t("dev.lastBy")}</th><th>{t("dev.versions")}</th><th>{t("dev.status")}</th><th style={{ textAlign: "right" }}>{t("acc.actions")}</th></tr></thead>
        <tbody>
          {SAMPLE_CONFIGS.map((c) => (
            <tr key={c.path}>
              <td className="mono" style={{ fontSize: 11.5 }}>{c.path}</td>
              <td className="mono dim">{c.agent}</td>
              <td className="mono num">{c.size}</td>
              <td className="mono dim" style={{ fontSize: 11 }}>{c.mtime}</td>
              <td className="mono dim">{c.last}</td>
              <td className="mono num">{c.versions}</td>
              <td>{c.validated ? <span className="badge ok">{t("dev.validated")}</span> : <span className="badge warn" title={c.warn}>{t("dev.needsReview")}</span>}</td>
              <td style={{ textAlign: "right" }}>
                <div className="row gap-1" style={{ justifyContent: "flex-end" }}>
                  <button className="btn btn-sm btn-ghost">{I.edit({ size: 12 })}<span>{t("common.edit")}</span></button>
                  <button className="btn btn-sm btn-ghost">{I.history({ size: 12 })}<span>{t("dev.diff")}</span></button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function ScriptsPanel() {
  const { t } = useTranslation()
  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(340px, 1fr))", gap: 12 }}>
      {SAMPLE_SCRIPTS.map((s) => (
        <div key={s.id} className="card" style={{ padding: 14 }}>
          <div className="row gap-2" style={{ alignItems: "center", marginBottom: 8 }}>
            {I.term({ size: 14 })}
            <span className="mono" style={{ fontWeight: 500, fontSize: 12.5 }}>{s.name}</span>
            <span className="badge mono" style={{ fontSize: 10 }}>{s.lang}</span>
            {s.danger && <span className="badge crit" style={{ fontSize: 10 }}>danger</span>}
          </div>
          <div className="muted" style={{ fontSize: 11.5, marginBottom: 10 }}>{s.desc}</div>
          <div className="hr" />
          <div className="col" style={{ gap: 6, fontSize: 11.5 }}>
            <div className="row" style={{ justifyContent: "space-between" }}><span className="muted">{t("dev.scope")}</span><span className="mono">{s.scope}</span></div>
            <div className="row" style={{ justifyContent: "space-between" }}><span className="muted">{t("dev.author")}</span><span className="mono">{s.author}</span></div>
            <div className="row" style={{ justifyContent: "space-between" }}>
              <span className="muted">{t("dev.lastRun")}</span>
              <span className="row gap-1" style={{ alignItems: "center" }}>
                {s.lastResult === "ok" ? <span style={{ color: "var(--ok)" }}>{I.check({ size: 11 })}</span> : s.lastResult === "fail" ? <span style={{ color: "var(--crit)" }}>{I.x({ size: 11 })}</span> : null}
                <span className="mono">{s.lastRun}</span>
              </span>
            </div>
          </div>
          <div className="hr" />
          <div className="row gap-2">
            <button className="btn btn-sm" style={{ flex: 1 }}>{I.bolt({ size: 12 })}<span>{t("dev.run")}</span></button>
            <button className="btn btn-sm btn-ghost btn-icon">{I.edit({ size: 12 })}</button>
            <button className="btn btn-sm btn-ghost btn-icon">{I.history({ size: 12 })}</button>
          </div>
        </div>
      ))}
    </div>
  )
}

function PackagesPanel() {
  const { t } = useTranslation()
  const updates = SAMPLE_PACKAGES.filter((p) => p.latest)
  const security = updates.filter((p) => p.security)
  return (
    <div className="col gap-4">
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 12 }}>
        <MiniStat label={t("dev.updates")} value={updates.length} color="var(--warn)" />
        <MiniStat label={t("dev.securityUpdates")} value={security.length} color="var(--crit)" />
        <MiniStat label={t("dev.installed")} value={SAMPLE_PACKAGES.length} color="var(--fg-3)" action={<button className="btn btn-sm btn-primary">{I.arrowUp({ size: 12 })}<span>{t("dev.updateAll")}</span></button>} />
      </div>
      <div className="card" style={{ overflow: "auto" }}>
        <table className="tbl" style={{ minWidth: 720 }}>
          <thead><tr><th>{t("dev.packages")}</th><th>{t("dev.current")}</th><th>{t("dev.latest")}</th><th>{t("dev.type")}</th><th>{t("dev.size")}</th><th style={{ textAlign: "right" }}>{t("acc.actions")}</th></tr></thead>
          <tbody>
            {SAMPLE_PACKAGES.map((p) => (
              <tr key={p.name}>
                <td className="mono" style={{ fontWeight: 500, fontSize: 11.5 }}>{p.name}</td>
                <td className="mono dim" style={{ fontSize: 11 }}>{p.current}</td>
                <td className="mono" style={{ fontSize: 11, color: p.latest ? "var(--fg)" : "var(--fg-4)" }}>{p.latest ?? "—"}</td>
                <td>{!p.latest ? <span className="badge">{t("dev.upToDate")}</span> : p.security ? <span className="badge crit">{t("dev.security")}</span> : <span className="badge warn">{t("dev.regular")}</span>}</td>
                <td className="mono num dim" style={{ fontSize: 11 }}>{p.size}</td>
                <td style={{ textAlign: "right" }}>{p.latest && <button className="btn btn-sm btn-ghost">{t("dev.update")}</button>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function HealthPanel() {
  const { t } = useTranslation()
  return (
    <div className="card" style={{ overflow: "auto" }}>
      <table className="tbl" style={{ minWidth: 760 }}>
        <thead><tr><th>Name</th><th>{t("dev.target")}</th><th>{t("dev.kind")}</th><th>{t("dev.interval")}</th><th>{t("dev.status")}</th><th>{t("dev.latency")}</th><th>{t("dev.lastFail")}</th><th style={{ textAlign: "right" }}>{t("acc.actions")}</th></tr></thead>
        <tbody>
          {SAMPLE_HEALTH.map((h) => (
            <tr key={h.id}>
              <td style={{ fontWeight: 500 }}>{h.name}</td>
              <td className="mono dim" style={{ fontSize: 11 }}>{h.target}</td>
              <td><span className="badge mono">{h.kind}</span></td>
              <td className="mono num">{h.interval}</td>
              <td><span className="row gap-2" style={{ alignItems: "center" }}><span className={`dot ${h.status === "ok" ? "ok" : h.status === "warn" ? "warn" : "crit"}`} /><span style={{ fontSize: 11.5, color: h.status === "ok" ? "var(--ok)" : h.status === "warn" ? "var(--warn)" : "var(--crit)" }}>{h.status}</span></span></td>
              <td className="mono num dim" style={{ fontSize: 11 }}>{h.latency}</td>
              <td className="mono dim" style={{ fontSize: 11 }}>{h.lastFail}</td>
              <td style={{ textAlign: "right" }}><button className="btn btn-sm btn-ghost">{I.refresh({ size: 12 })}<span>{t("dev.run")}</span></button></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function OperationsScreen() {
  const { t } = useTranslation()
  const [tab, setTab] = useState<Tab>("configs")
  const tabs: { k: Tab; label: string; icon: React.ReactNode }[] = [
    { k: "configs", label: t("dev.configs"), icon: I.audit({ size: 13 }) },
    { k: "scripts", label: t("dev.scripts"), icon: I.term({ size: 13 }) },
    { k: "packages", label: t("dev.packages"), icon: I.disk({ size: 13 }) },
    { k: "health", label: t("dev.health"), icon: I.shield({ size: 13 }) },
  ]
  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader title={t("nav.operations")} subtitle={t("dev.opsSubtitle")} />
      <div style={{ padding: "0 24px", borderBottom: "1px solid var(--border)" }}>
        <div className="tabs" style={{ borderBottom: "none", marginBottom: -1 }}>
          {tabs.map((tb) => (
            <button key={tb.k} className={`tab ${tab === tb.k ? "active" : ""}`} onClick={() => setTab(tb.k)}>{tb.icon} {tb.label}</button>
          ))}
        </div>
      </div>
      <div style={{ padding: "20px 24px", overflow: "auto", flex: 1 }}>
        <PreviewBanner />
        {tab === "configs" && <ConfigsPanel />}
        {tab === "scripts" && <ScriptsPanel />}
        {tab === "packages" && <PackagesPanel />}
        {tab === "health" && <HealthPanel />}
      </div>
    </div>
  )
}
