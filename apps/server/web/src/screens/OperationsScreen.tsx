import { useMemo, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { PageHeader, Perm } from "@/components/shell/primitives"
import { AgentPicker } from "@/components/monitor/AgentPicker"
import { useAgentCommand } from "@/hooks/useAgentCommand"
import { formatBytes } from "@/lib/format"
import { SAMPLE_CONFIGS, SAMPLE_HEALTH } from "@/lib/sampledata"

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

function MiniStat({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="card" style={{ padding: "10px 14px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
      <div className="col" style={{ gap: 2 }}><div className="upper" style={{ color: "var(--fg-4)" }}>{label}</div><div className="num display" style={{ fontSize: 22, fontWeight: 500 }}>{value}</div></div>
      <span style={{ width: 4, height: 28, background: color, borderRadius: 2 }} />
    </div>
  )
}

function State({ loading, error, empty }: { loading: boolean; error: string | null; empty: boolean }) {
  const { t } = useTranslation()
  if (loading) return <div style={{ padding: 32, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}><span className="dot pulse ok" /> {t("common.loading")}</div>
  if (error) return <div className="badge crit" style={{ height: "auto", padding: 10, margin: "12px 0" }}>{error}</div>
  if (empty) return <div style={{ padding: 32, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("common.noData")}</div>
  return null
}

function PackagesPanel({ agentId }: { agentId: string }) {
  const { t } = useTranslation()
  const { data, loading, error, reload } = useAgentCommand(agentId, "PACKAGE_LIST", { enabled: !!agentId })
  const pkgs = data?.packages ?? []
  const updates = pkgs.filter((p) => p.updateAvailable)
  const security = updates.filter((p) => /sec/i.test(p.repository || ""))

  return (
    <div className="col gap-4">
      <div className="row" style={{ justifyContent: "flex-end" }}>
        <button className="btn btn-sm btn-ghost" onClick={reload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button>
      </div>
      <State loading={loading && !data} error={error} empty={!!data && pkgs.length === 0} />
      {data && pkgs.length > 0 && (
        <>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 12 }}>
            <MiniStat label={t("dev.updates")} value={updates.length} color="var(--warn)" />
            <MiniStat label={t("dev.securityUpdates")} value={security.length} color="var(--crit)" />
            <MiniStat label={t("dev.installed")} value={pkgs.length} color="var(--fg-3)" />
          </div>
          <div className="card" style={{ overflow: "auto" }}>
            <table className="tbl" style={{ minWidth: 720 }}>
              <thead><tr><th>{t("dev.packages")}</th><th>{t("dev.current")}</th><th>{t("dev.latest")}</th><th>{t("dev.type")}</th><th>{t("dev.size")}</th></tr></thead>
              <tbody>
                {pkgs.slice(0, 400).map((p) => (
                  <tr key={p.name}>
                    <td className="mono" style={{ fontWeight: 500, fontSize: 11.5 }}>{p.name}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{p.version}</td>
                    <td className="mono" style={{ fontSize: 11, color: p.updateAvailable ? "var(--fg)" : "var(--fg-4)" }}>{p.newVersion || "—"}</td>
                    <td>{p.updateAvailable ? <span className="badge warn">{t("dev.regular")}</span> : <span className="badge">{t("dev.upToDate")}</span>}</td>
                    <td className="mono num dim" style={{ fontSize: 11 }}>{p.installedSize ? formatBytes(p.installedSize) : "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  )
}

function ScriptsPanel({ agentId }: { agentId: string }) {
  const { t } = useTranslation()
  const { data, loading, error, reload } = useAgentCommand(agentId, "SCRIPT_LIST", { enabled: !!agentId })
  const scripts = data?.scripts ?? []
  return (
    <div className="col gap-3">
      <div className="row" style={{ justifyContent: "flex-end" }}>
        <button className="btn btn-sm btn-ghost" onClick={reload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button>
      </div>
      <State loading={loading && !data} error={error} empty={!!data && scripts.length === 0} />
      {data && scripts.length > 0 && (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(340px, 1fr))", gap: 12 }}>
          {scripts.map((s) => (
            <div key={s.name} className="card" style={{ padding: 14 }}>
              <div className="row gap-2" style={{ alignItems: "center", marginBottom: 8, flexWrap: "wrap" }}>
                {I.term({ size: 14 })}
                <span className="mono" style={{ fontWeight: 500, fontSize: 12.5 }}>{s.name}</span>
                {s.category && <span className="badge mono" style={{ fontSize: 10 }}>{s.category}</span>}
                {s.requiredPermission != null && <Perm level={s.requiredPermission} />}
              </div>
              {s.description && <div className="muted" style={{ fontSize: 11.5, marginBottom: 10 }}>{s.description}</div>}
              <div className="hr" />
              <div className="row" style={{ justifyContent: "space-between", fontSize: 11 }}>
                <span className="row gap-2" style={{ alignItems: "center" }}>
                  {s.signatureVerified && <span className="badge ok" style={{ fontSize: 9.5 }}>{I.check({ size: 10 })} signed</span>}
                  {s.fileSize ? <span className="mono dim">{formatBytes(s.fileSize)}</span> : null}
                </span>
                <button className="btn btn-sm btn-ghost">{I.bolt({ size: 12 })}<span>{t("dev.run")}</span></button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function ConfigsPanel() {
  const { t } = useTranslation()
  return (
    <>
      <PreviewBanner />
      <div className="card" style={{ overflow: "auto" }}>
        <table className="tbl" style={{ minWidth: 820 }}>
          <thead><tr><th>{t("dev.path")}</th><th>{t("dev.agent")}</th><th>{t("dev.size")}</th><th>{t("dev.modified")}</th><th>{t("dev.lastBy")}</th><th>{t("dev.status")}</th></tr></thead>
          <tbody>
            {SAMPLE_CONFIGS.map((c) => (
              <tr key={c.path}>
                <td className="mono" style={{ fontSize: 11.5 }}>{c.path}</td>
                <td className="mono dim">{c.agent}</td>
                <td className="mono num">{c.size}</td>
                <td className="mono dim" style={{ fontSize: 11 }}>{c.mtime}</td>
                <td className="mono dim">{c.last}</td>
                <td>{c.validated ? <span className="badge ok">{t("dev.validated")}</span> : <span className="badge warn">{t("dev.needsReview")}</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  )
}

function HealthPanel() {
  const { t } = useTranslation()
  return (
    <>
      <PreviewBanner />
      <div className="card" style={{ overflow: "auto" }}>
        <table className="tbl" style={{ minWidth: 720 }}>
          <thead><tr><th>Name</th><th>{t("dev.target")}</th><th>{t("dev.kind")}</th><th>{t("dev.status")}</th><th>{t("dev.latency")}</th></tr></thead>
          <tbody>
            {SAMPLE_HEALTH.map((h) => (
              <tr key={h.id}>
                <td style={{ fontWeight: 500 }}>{h.name}</td>
                <td className="mono dim" style={{ fontSize: 11 }}>{h.target}</td>
                <td><span className="badge mono">{h.kind}</span></td>
                <td><span className="row gap-2" style={{ alignItems: "center" }}><span className={`dot ${h.status === "ok" ? "ok" : h.status === "warn" ? "warn" : "crit"}`} /><span style={{ fontSize: 11.5 }}>{h.status}</span></span></td>
                <td className="mono num dim" style={{ fontSize: 11 }}>{h.latency}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  )
}

export function OperationsScreen() {
  const { t } = useTranslation()
  const [tab, setTab] = useState<Tab>("packages")
  const [agentId, setAgentId] = useState("")
  const tabs: { k: Tab; label: string; icon: React.ReactNode; real?: boolean }[] = [
    { k: "packages", label: t("dev.packages"), icon: I.disk({ size: 13 }), real: true },
    { k: "scripts", label: t("dev.scripts"), icon: I.term({ size: 13 }), real: true },
    { k: "configs", label: t("dev.configs"), icon: I.audit({ size: 13 }) },
    { k: "health", label: t("dev.health"), icon: I.shield({ size: 13 }) },
  ]
  const realTab = tab === "packages" || tab === "scripts"
  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader title={t("nav.operations")} subtitle={t("dev.opsSubtitle")} actions={realTab ? <AgentPicker value={agentId} onChange={setAgentId} /> : undefined} />
      <div style={{ padding: "0 24px", borderBottom: "1px solid var(--border)" }}>
        <div className="tabs" style={{ borderBottom: "none", marginBottom: -1 }}>
          {tabs.map((tb) => (
            <button key={tb.k} className={`tab ${tab === tb.k ? "active" : ""}`} onClick={() => setTab(tb.k)}>{tb.icon} {tb.label}</button>
          ))}
        </div>
      </div>
      <div style={{ padding: "20px 24px", overflow: "auto", flex: 1 }}>
        {tab === "packages" && <PackagesPanel agentId={agentId} />}
        {tab === "scripts" && <ScriptsPanel agentId={agentId} />}
        {tab === "configs" && <ConfigsPanel />}
        {tab === "health" && <HealthPanel />}
      </div>
    </div>
  )
}
