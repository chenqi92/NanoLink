import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { PageHeader, Perm } from "@/components/shell/primitives"
import { AgentPicker } from "@/components/monitor/AgentPicker"
import { Modal } from "@/components/shell/Dialog"
import { useAgentCommand, runAgentCommand } from "@/hooks/useAgentCommand"
import { formatBytes } from "@/lib/format"
import type { AgentConfigResult } from "@/lib/api"

type Tab = "packages" | "scripts" | "configs" | "health"

function MiniStat({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="card" style={{ padding: "10px 14px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
      <div className="col" style={{ gap: 2 }}><div className="upper" style={{ color: "var(--fg-4)" }}>{label}</div><div className="num display" style={{ fontSize: 22, fontWeight: 500 }}>{value}</div></div>
      <span style={{ width: 4, height: 28, background: color, borderRadius: 2 }} />
    </div>
  )
}

function State({ loading, error, empty, msg }: { loading: boolean; error: string | null; empty: boolean; msg?: string }) {
  const { t } = useTranslation()
  if (loading) return <div style={{ padding: 32, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}><span className="dot pulse ok" /> {t("common.loading")}</div>
  if (error) return <div className="badge crit" style={{ height: "auto", padding: 10, margin: "12px 0" }}>{error}</div>
  if (empty) return <div style={{ padding: 32, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{msg ?? t("common.noData")}</div>
  return null
}

// ─── localStorage list helper ─────────────────────────────
function useStoredList(key: string, defaults: string[]) {
  const [items, setItems] = useState<string[]>(() => {
    try {
      const raw = localStorage.getItem(key)
      if (raw) return JSON.parse(raw)
    } catch { /* ignore */ }
    return defaults
  })
  const save = useCallback((next: string[]) => {
    setItems(next)
    try { localStorage.setItem(key, JSON.stringify(next)) } catch { /* ignore */ }
  }, [key])
  return [items, save] as const
}

function PackagesPanel({ agentId }: { agentId: string }) {
  const { t } = useTranslation()
  const { data, loading, error, reload } = useAgentCommand(agentId, "PACKAGE_LIST", { enabled: !!agentId })
  const pkgs = data?.packages ?? []
  const updates = pkgs.filter((p) => p.updateAvailable)
  return (
    <div className="col gap-4">
      <div className="row" style={{ justifyContent: "flex-end" }}><button className="btn btn-sm btn-ghost" onClick={reload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button></div>
      <State loading={loading && !data} error={error} empty={!!data && pkgs.length === 0} />
      {data && pkgs.length > 0 && (
        <>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(2, 1fr)", gap: 12 }}>
            <MiniStat label={t("dev.updates")} value={updates.length} color="var(--warn)" />
            <MiniStat label={t("dev.installed")} value={pkgs.length} color="var(--fg-3)" />
          </div>
          <div className="card" style={{ overflow: "auto" }}>
            <table className="tbl" style={{ minWidth: 680 }}>
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
      <div className="row" style={{ justifyContent: "flex-end" }}><button className="btn btn-sm btn-ghost" onClick={reload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button></div>
      <State loading={loading && !data} error={error} empty={!!data && scripts.length === 0} />
      {data && scripts.length > 0 && (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(340px, 1fr))", gap: 12 }}>
          {scripts.map((s) => (
            <div key={s.name} className="card" style={{ padding: 14 }}>
              <div className="row gap-2" style={{ alignItems: "center", marginBottom: 8, flexWrap: "wrap" }}>
                {I.term({ size: 14 })}<span className="mono" style={{ fontWeight: 500, fontSize: 12.5 }}>{s.name}</span>
                {s.category && <span className="badge mono" style={{ fontSize: 10 }}>{s.category}</span>}
                {s.requiredPermission != null && <Perm level={s.requiredPermission} />}
              </div>
              {s.description && <div className="muted" style={{ fontSize: 11.5, marginBottom: 10 }}>{s.description}</div>}
              <div className="hr" />
              <div className="row" style={{ justifyContent: "space-between", fontSize: 11 }}>
                {s.signatureVerified ? <span className="badge ok" style={{ fontSize: 9.5 }}>{I.check({ size: 10 })} signed</span> : <span />}
                <button className="btn btn-sm btn-ghost">{I.bolt({ size: 12 })}<span>{t("dev.run")}</span></button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

interface ProbeResult { target: string; passed?: boolean; latency?: number; message?: string; error?: string; running?: boolean }

function HealthPanel({ agentId }: { agentId: string }) {
  const { t } = useTranslation()
  const [targets, setTargets] = useStoredList("nanolink_health_targets", ["1.1.1.1:53", "github.com:443", "localhost:9100"])
  const [results, setResults] = useState<Record<string, ProbeResult>>({})
  const [input, setInput] = useState("")

  const runOne = useCallback(async (target: string) => {
    setResults((r) => ({ ...r, [target]: { target, running: true } }))
    try {
      const res = await runAgentCommand(agentId, "CONNECTIVITY_TEST", { target })
      const item = res.healthResult?.checks?.[0]
      setResults((r) => ({ ...r, [target]: { target, passed: item?.passed, latency: item?.durationMs, message: item?.message } }))
    } catch (e) {
      setResults((r) => ({ ...r, [target]: { target, error: e instanceof Error ? e.message : "failed" } }))
    }
  }, [agentId])

  const runAll = useCallback(() => { targets.forEach((tg) => runOne(tg)) }, [targets, runOne])
  useEffect(() => { if (agentId) runAll() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [agentId])

  return (
    <div className="col gap-3">
      <div className="row gap-2" style={{ flexWrap: "wrap" }}>
        <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 10px", height: 30, flex: 1, minWidth: 220 }}>
          {I.shield({ size: 13 })}
          <input value={input} onChange={(e) => setInput(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && input.trim()) { setTargets([...targets, input.trim()]); setInput("") } }} placeholder="host:port / https://host" style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "var(--font-mono)", fontSize: 12 }} />
        </div>
        <button className="btn btn-sm" onClick={() => { if (input.trim()) { setTargets([...targets, input.trim()]); setInput("") } }}>{I.plus({ size: 13 })}<span>{t("dev.addTarget")}</span></button>
        <button className="btn btn-sm btn-primary" onClick={runAll}>{I.refresh({ size: 13 })}<span>{t("dev.runAll")}</span></button>
      </div>
      {targets.length === 0 ? (
        <State loading={false} error={null} empty msg={t("dev.noTargets")} />
      ) : (
        <div className="card" style={{ overflow: "auto" }}>
          <table className="tbl" style={{ minWidth: 600 }}>
            <thead><tr><th>{t("dev.target")}</th><th>{t("dev.status")}</th><th style={{ textAlign: "right" }}>{t("dev.latency")}</th><th></th></tr></thead>
            <tbody>
              {targets.map((tg) => {
                const r = results[tg]
                return (
                  <tr key={tg}>
                    <td className="mono">{tg}</td>
                    <td>
                      {!r ? <span className="dim">—</span> : r.running ? <span className="dot pulse ok" /> : r.error ? <span className="row gap-2" style={{ alignItems: "center" }}><span className="dot crit" /><span style={{ fontSize: 11.5, color: "var(--crit)" }}>{r.error}</span></span> : <span className="row gap-2" style={{ alignItems: "center" }}><span className={`dot ${r.passed ? "ok" : "crit"}`} /><span style={{ fontSize: 11.5, color: r.passed ? "var(--ok)" : "var(--crit)" }}>{r.passed ? "ok" : "fail"}</span></span>}
                    </td>
                    <td className="mono num dim" style={{ textAlign: "right", fontSize: 11 }}>{r?.latency != null ? `${r.latency} ms` : "—"}</td>
                    <td style={{ textAlign: "right" }}>
                      <div className="row gap-1" style={{ justifyContent: "flex-end" }}>
                        <button className="btn btn-sm btn-ghost" onClick={() => runOne(tg)}>{I.refresh({ size: 11 })}</button>
                        <button className="btn btn-sm btn-ghost btn-icon" onClick={() => setTargets(targets.filter((x) => x !== tg))}><span style={{ color: "var(--crit)" }}>{I.trash({ size: 11 })}</span></button>
                      </div>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

interface CfgRow { path: string; valid?: boolean; error?: string; running?: boolean }

function ConfigsPanel({ agentId }: { agentId: string }) {
  const { t } = useTranslation()
  const [paths, setPaths] = useStoredList("nanolink_managed_configs", ["/etc/nginx/nginx.conf", "/etc/hosts"])
  const [rows, setRows] = useState<Record<string, CfgRow>>({})
  const [input, setInput] = useState("")
  const [viewing, setViewing] = useState<{ path: string; result: AgentConfigResult } | null>(null)

  const validate = useCallback(async (path: string) => {
    setRows((r) => ({ ...r, [path]: { path, running: true } }))
    try {
      const res = await runAgentCommand(agentId, "CONFIG_VALIDATE", { params: { path } })
      setRows((r) => ({ ...r, [path]: { path, valid: res.configResult?.valid, error: res.configResult?.validationError } }))
    } catch (e) {
      setRows((r) => ({ ...r, [path]: { path, error: e instanceof Error ? e.message : "failed" } }))
    }
  }, [agentId])

  const validateAll = useCallback(() => { paths.forEach((p) => validate(p)) }, [paths, validate])
  useEffect(() => { if (agentId) validateAll() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [agentId])

  async function view(path: string) {
    try {
      const res = await runAgentCommand(agentId, "CONFIG_READ", { params: { path } })
      setViewing({ path, result: res.configResult ?? { path, content: res.output } })
    } catch (e) {
      setViewing({ path, result: { path, content: `Error: ${e instanceof Error ? e.message : "failed"}` } })
    }
  }

  return (
    <div className="col gap-3">
      <div className="row gap-2" style={{ flexWrap: "wrap" }}>
        <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 10px", height: 30, flex: 1, minWidth: 220 }}>
          {I.audit({ size: 13 })}
          <input value={input} onChange={(e) => setInput(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && input.trim()) { setPaths([...paths, input.trim()]); setInput("") } }} placeholder="/etc/..." style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "var(--font-mono)", fontSize: 12 }} />
        </div>
        <button className="btn btn-sm" onClick={() => { if (input.trim()) { setPaths([...paths, input.trim()]); setInput("") } }}>{I.plus({ size: 13 })}<span>{t("dev.addPath")}</span></button>
        <button className="btn btn-sm btn-primary" onClick={validateAll}>{I.refresh({ size: 13 })}<span>{t("dev.runAll")}</span></button>
      </div>
      {paths.length === 0 ? (
        <State loading={false} error={null} empty msg={t("dev.noConfigs")} />
      ) : (
        <div className="card" style={{ overflow: "auto" }}>
          <table className="tbl" style={{ minWidth: 600 }}>
            <thead><tr><th>{t("dev.path")}</th><th>{t("dev.status")}</th><th style={{ textAlign: "right" }}>{t("acc.actions")}</th></tr></thead>
            <tbody>
              {paths.map((p) => {
                const r = rows[p]
                return (
                  <tr key={p}>
                    <td className="mono" style={{ fontSize: 11.5 }}>{p}</td>
                    <td>
                      {!r ? <span className="dim">—</span> : r.running ? <span className="dot pulse ok" /> : r.error ? <span className="badge crit" title={r.error}>{t("dev.invalid")}</span> : r.valid ? <span className="badge ok">{t("dev.valid")}</span> : <span className="badge warn" title={r.error}>{t("dev.invalid")}</span>}
                    </td>
                    <td style={{ textAlign: "right" }}>
                      <div className="row gap-1" style={{ justifyContent: "flex-end" }}>
                        <button className="btn btn-sm btn-ghost" onClick={() => view(p)}>{I.search({ size: 11 })}<span>{t("dev.view")}</span></button>
                        <button className="btn btn-sm btn-ghost" onClick={() => validate(p)}>{I.refresh({ size: 11 })}</button>
                        <button className="btn btn-sm btn-ghost btn-icon" onClick={() => setPaths(paths.filter((x) => x !== p))}><span style={{ color: "var(--crit)" }}>{I.trash({ size: 11 })}</span></button>
                      </div>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
      {viewing && (
        <Modal title={viewing.path} onClose={() => setViewing(null)} width={680} footer={<button className="btn btn-sm" onClick={() => setViewing(null)}>{t("common.cancel")}</button>}>
          <div className="code" style={{ maxHeight: "60vh", whiteSpace: "pre-wrap", overflow: "auto" }}>{viewing.result.content || t("common.noData")}</div>
        </Modal>
      )}
    </div>
  )
}

export function OperationsScreen() {
  const { t } = useTranslation()
  const [tab, setTab] = useState<Tab>("packages")
  const [agentId, setAgentId] = useState("")
  const tabs: { k: Tab; label: string; icon: React.ReactNode }[] = [
    { k: "packages", label: t("dev.packages"), icon: I.disk({ size: 13 }) },
    { k: "scripts", label: t("dev.scripts"), icon: I.term({ size: 13 }) },
    { k: "configs", label: t("dev.configs"), icon: I.audit({ size: 13 }) },
    { k: "health", label: t("dev.health"), icon: I.shield({ size: 13 }) },
  ]
  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader title={t("nav.operations")} subtitle={t("dev.opsSubtitle")} actions={<AgentPicker value={agentId} onChange={setAgentId} />} />
      <div style={{ padding: "0 24px", borderBottom: "1px solid var(--border)" }}>
        <div className="tabs" style={{ borderBottom: "none", marginBottom: -1 }}>
          {tabs.map((tb) => (
            <button key={tb.k} className={`tab ${tab === tb.k ? "active" : ""}`} onClick={() => setTab(tb.k)}>{tb.icon} {tb.label}</button>
          ))}
        </div>
      </div>
      <div style={{ padding: "20px 24px", overflow: "auto", flex: 1 }}>
        {!agentId ? (
          <div style={{ padding: 32, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("common.loading")}</div>
        ) : tab === "packages" ? (
          <PackagesPanel agentId={agentId} />
        ) : tab === "scripts" ? (
          <ScriptsPanel agentId={agentId} />
        ) : tab === "configs" ? (
          <ConfigsPanel agentId={agentId} />
        ) : (
          <HealthPanel agentId={agentId} />
        )}
      </div>
    </div>
  )
}
