import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { PageHeader, Perm } from "@/components/shell/primitives"
import { AgentPicker } from "@/components/monitor/AgentPicker"
import { Modal, ConfirmDialog } from "@/components/shell/Dialog"
import { useAgentCommand, runAgentCommand } from "@/hooks/useAgentCommand"
import { formatBytes } from "@/lib/format"
import type { AgentConfigResult } from "@/lib/api"
import { ContentState, LoadingState, RequestState } from "@/components/shell/RequestState"
import { userErrorMessage } from "@/lib/errors"
import { useData } from "@/contexts/DataContext"

type Tab = "packages" | "scripts" | "configs" | "health"

function MiniStat({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="card" style={{ padding: "10px 14px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
      <div className="col" style={{ gap: 2 }}><div className="upper" style={{ color: "var(--fg-4)" }}>{label}</div><div className="num display" style={{ fontSize: 22, fontWeight: 500 }}>{value}</div></div>
      <span style={{ width: 4, height: 28, background: color, borderRadius: 2 }} />
    </div>
  )
}

function State({ loading, error, empty, msg, onRetry }: { loading: boolean; error: unknown; empty: boolean; msg?: string; onRetry?: () => void }) {
  const { t } = useTranslation()
  if (loading) return <LoadingState compact />
  if (error != null) return <RequestState error={error} onRetry={onRetry} compact />
  if (empty) return <ContentState kind="empty" title={msg ?? t("common.noData")} compact />
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

function Flash({ flash, onClose }: { flash: { kind: "ok" | "crit"; text: string } | null; onClose: () => void }) {
  if (!flash) return null
  return <div className={`badge ${flash.kind}`} style={{ height: "auto", padding: "6px 10px", cursor: "pointer" }} onClick={onClose} role="status">{flash.text}</div>
}

function PackagesPanel({ agentId, permission }: { agentId: string; permission: number }) {
  const { t } = useTranslation()
  const { data, loading, error, reload } = useAgentCommand(agentId, "PACKAGE_LIST", { enabled: !!agentId })
  const [busy, setBusy] = useState<string | null>(null)
  const [flash, setFlash] = useState<{ kind: "ok" | "crit"; text: string } | null>(null)
  const pkgs = data?.packages ?? []
  const updates = pkgs.filter((p) => p.updateAvailable)
  const canUpdate = permission >= 3

  const act = useCallback(async (key: string, type: string, target?: string, after?: boolean) => {
    setBusy(key)
    setFlash(null)
    try {
      await runAgentCommand(agentId, type, { target })
      setFlash({ kind: "ok", text: t("dev.cmdSent") })
      if (after) reload()
    } catch (e) {
      setFlash({ kind: "crit", text: userErrorMessage(e, t) })
    } finally {
      setBusy(null)
    }
  }, [agentId, reload, t])

  return (
    <div className="col gap-4">
      <div className="row gap-2" style={{ justifyContent: "flex-end", flexWrap: "wrap" }}>
        <Flash flash={flash} onClose={() => setFlash(null)} />
        <button className="btn btn-sm" disabled={!!busy} onClick={() => act("check", "PACKAGE_CHECK_UPDATES", undefined, true)}>{busy === "check" ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}<span>{t("dev.checkNow")}</span></button>
        <button className="btn btn-sm btn-primary" disabled={!!busy || updates.length === 0 || !canUpdate} title={canUpdate ? undefined : t("access.permissionLevelDesc", { level: "L3" })} onClick={() => act("all", "SYSTEM_UPDATE", undefined, true)}>{busy === "all" ? <span className="dot pulse ok" /> : I.arrowUp({ size: 13 })}<span>{t("dev.updateAll")}</span></button>
        <button className="btn btn-sm btn-ghost" onClick={reload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button>
      </div>
      <State loading={loading && !data} error={error} empty={!!data && pkgs.length === 0} onRetry={reload} />
      {data && pkgs.length > 0 && (
        <>
          <div className="responsive-two-grid" style={{ gap: 12 }}>
            <MiniStat label={t("dev.updates")} value={updates.length} color="var(--warn)" />
            <MiniStat label={t("dev.installed")} value={pkgs.length} color="var(--fg-3)" />
          </div>
          <div className="card" style={{ overflow: "auto" }}>
            <table className="tbl" style={{ minWidth: 720 }}>
              <thead><tr><th>{t("dev.packages")}</th><th>{t("dev.current")}</th><th>{t("dev.latest")}</th><th>{t("dev.type")}</th><th>{t("dev.size")}</th><th style={{ textAlign: "right" }}>{t("dev.actions")}</th></tr></thead>
              <tbody>
                {pkgs.slice(0, 400).map((p) => (
                  <tr key={p.name}>
                    <td className="mono" style={{ fontWeight: 500, fontSize: 11.5 }}>{p.name}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{p.version}</td>
                    <td className="mono" style={{ fontSize: 11, color: p.updateAvailable ? "var(--fg)" : "var(--fg-4)" }}>{p.newVersion || "—"}</td>
                    <td>{p.updateAvailable ? <span className="badge warn">{t("dev.regular")}</span> : <span className="badge">{t("dev.upToDate")}</span>}</td>
                    <td className="mono num dim" style={{ fontSize: 11 }}>{p.installedSize ? formatBytes(p.installedSize) : "—"}</td>
                    <td style={{ textAlign: "right" }}>
                      {p.updateAvailable && (
                        <button className="btn btn-sm btn-ghost" disabled={!!busy || !canUpdate} title={canUpdate ? undefined : t("access.permissionLevelDesc", { level: "L3" })} onClick={() => act(`pkg-${p.name}`, "PACKAGE_UPDATE", p.name)}>{busy === `pkg-${p.name}` ? <span className="dot pulse ok" /> : I.arrowUp({ size: 11 })}<span style={{ fontSize: 11 }}>{t("dev.update")}</span></button>
                      )}
                    </td>
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

function ScriptsPanel({ agentId, permission }: { agentId: string; permission: number }) {
  const { t } = useTranslation()
  const { data, loading, error, reload } = useAgentCommand(agentId, "SCRIPT_LIST", { enabled: !!agentId })
  const [busy, setBusy] = useState<string | null>(null)
  const [flash, setFlash] = useState<{ kind: "ok" | "crit"; text: string } | null>(null)
  const [confirm, setConfirm] = useState<string | null>(null)
  const scripts = data?.scripts ?? []

  async function runScript(name: string) {
    setConfirm(null)
    setBusy(name)
    setFlash(null)
    try {
      const res = await runAgentCommand(agentId, "SCRIPT_EXECUTE", { target: name })
      setFlash({ kind: "ok", text: res.output ? `${name}: ${res.output.slice(0, 200)}` : t("dev.cmdSent") })
    } catch (e) {
      setFlash({ kind: "crit", text: userErrorMessage(e, t) })
    } finally {
      setBusy(null)
    }
  }

  return (
    <div className="col gap-3">
      <div className="row gap-2" style={{ justifyContent: "flex-end", flexWrap: "wrap" }}>
        <Flash flash={flash} onClose={() => setFlash(null)} />
        <button className="btn btn-sm btn-ghost" onClick={reload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button>
      </div>
      <State loading={loading && !data} error={error} empty={!!data && scripts.length === 0} onRetry={reload} />
      {data && scripts.length > 0 && (
        <div className="auto-card-grid-340" style={{ gap: 12 }}>
          {scripts.map((s) => (
            <div key={s.name} className="card" style={{ padding: 14 }}>
              <div className="row gap-2" style={{ alignItems: "center", marginBottom: 8, flexWrap: "wrap" }}>
                {I.term({ size: 14 })}<span className="mono" style={{ fontWeight: 500, fontSize: 12.5 }}>{s.name}</span>
                {s.category && <span className="badge mono" style={{ fontSize: 10 }}>{s.category}</span>}
                {s.requiredPermission != null && <Perm level={s.requiredPermission} />}
              </div>
              {s.description && <div className="muted" style={{ fontSize: 11.5, marginBottom: 10 }}>{s.description}</div>}
              {(s.fileSize != null || s.lastModified) && (
                <div className="row gap-3 dim mono" style={{ fontSize: 10.5, marginBottom: 6 }}>
                  {s.fileSize != null && <span>{t("dev.size")} {formatBytes(s.fileSize)}</span>}
                  {s.lastModified && <span>{t("dev.lastRun")} {new Date(s.lastModified).toLocaleDateString()}</span>}
                </div>
              )}
              <div className="hr" />
              <div className="row" style={{ justifyContent: "space-between", fontSize: 11 }}>
                {s.signatureVerified ? <span className="badge ok" style={{ fontSize: 9.5 }}>{I.check({ size: 10 })} {t("dev.signed")}</span> : <span />}
                <button className="btn btn-sm btn-ghost" disabled={busy === s.name || permission < Math.max(2, s.requiredPermission ?? 0)} title={permission < Math.max(2, s.requiredPermission ?? 0) ? t("access.permissionLevelDesc", { level: `L${Math.max(2, s.requiredPermission ?? 0)}` }) : undefined} onClick={() => setConfirm(s.name)}>{busy === s.name ? <span className="dot pulse ok" /> : I.bolt({ size: 12 })}<span>{t("dev.run")}</span></button>
              </div>
            </div>
          ))}
        </div>
      )}
      {confirm && (
        <ConfirmDialog
          title={t("dev.runScript")}
          message={<span className="mono">{confirm}</span>}
          confirmLabel={t("dev.run")}
          onConfirm={() => runScript(confirm)}
          onClose={() => setConfirm(null)}
        />
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
      setResults((r) => ({ ...r, [target]: { target, error: userErrorMessage(e, t) } }))
    }
  }, [agentId, t])

  const runAll = useCallback(() => { targets.forEach((tg) => runOne(tg)) }, [targets, runOne])
  useEffect(() => { if (agentId) runAll() }, [agentId, runAll])

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
                      {!r ? <span className="dim">—</span> : r.running ? <span className="dot pulse ok" /> : r.error ? <span className="row gap-2" style={{ alignItems: "center" }}><span className="dot crit" /><span style={{ fontSize: 11.5, color: "var(--crit)" }}>{r.error}</span></span> : <span className="row gap-2" style={{ alignItems: "center" }}><span className={`dot ${r.passed ? "ok" : "crit"}`} /><span style={{ fontSize: 11.5, color: r.passed ? "var(--ok)" : "var(--crit)" }}>{t(r.passed ? "plat.ok" : "plat.fail")}</span></span>}
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

function ConfigsPanel({ agentId, permission }: { agentId: string; permission: number }) {
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
      setRows((r) => ({ ...r, [path]: { path, error: userErrorMessage(e, t) } }))
    }
  }, [agentId, t])

  const validateAll = useCallback(() => { paths.forEach((p) => validate(p)) }, [paths, validate])
  useEffect(() => { if (agentId) validateAll() }, [agentId, validateAll])

  const [backupsFor, setBackupsFor] = useState<{ path: string; result: AgentConfigResult } | null>(null)
  const [flash, setFlash] = useState<{ kind: "ok" | "crit"; text: string } | null>(null)

  async function view(path: string) {
    try {
      const res = await runAgentCommand(agentId, "CONFIG_READ", { params: { path } })
      setViewing({ path, result: res.configResult ?? { path, content: res.output } })
    } catch (e) {
      setViewing({ path, result: { path, content: userErrorMessage(e, t) } })
    }
  }

  async function openBackups(path: string) {
    setFlash(null)
    try {
      const res = await runAgentCommand(agentId, "CONFIG_LIST_BACKUPS", { params: { path } })
      setBackupsFor({ path, result: res.configResult ?? { path, backups: [] } })
    } catch (e) {
      setFlash({ kind: "crit", text: userErrorMessage(e, t) })
    }
  }

  async function rollback(path: string, backupPath: string) {
    setBackupsFor(null)
    try {
      await runAgentCommand(agentId, "CONFIG_ROLLBACK", { params: { path, backup: backupPath } })
      setFlash({ kind: "ok", text: t("dev.cmdSent") })
      validate(path)
    } catch (e) {
      setFlash({ kind: "crit", text: userErrorMessage(e, t) })
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
        <Flash flash={flash} onClose={() => setFlash(null)} />
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
                        <button className="btn btn-sm btn-ghost" onClick={() => openBackups(p)}>{I.history({ size: 11 })}<span>{t("dev.backups")}</span></button>
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
          <div className="code" style={{ whiteSpace: "pre-wrap" }}>{viewing.result.content || t("common.noData")}</div>
        </Modal>
      )}
      {backupsFor && (
        <Modal title={`${t("dev.backups")} · ${backupsFor.path}`} onClose={() => setBackupsFor(null)} width={560} footer={<button className="btn btn-sm" onClick={() => setBackupsFor(null)}>{t("common.cancel")}</button>}>
          {(backupsFor.result.backups ?? []).length === 0 ? (
            <div className="muted" style={{ fontSize: 12.5, padding: 8 }}>{t("dev.noBackups")}</div>
          ) : (
            <table className="tbl">
              <thead><tr><th>{t("dev.path")}</th><th>{t("dev.modified")}</th><th style={{ textAlign: "right" }}>{t("dev.size")}</th><th style={{ textAlign: "right" }} /></tr></thead>
              <tbody>
                {(backupsFor.result.backups ?? []).map((b) => (
                  <tr key={b.path}>
                    <td className="mono truncate" style={{ maxWidth: 240, fontSize: 11.5 }}>{b.path}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{b.createdAt ? new Date(b.createdAt).toLocaleString() : "—"}</td>
                    <td className="mono num dim" style={{ textAlign: "right", fontSize: 11 }}>{b.size != null ? formatBytes(b.size) : "—"}</td>
                    <td style={{ textAlign: "right" }}><button className="btn btn-sm btn-ghost" disabled={permission < 2} title={permission < 2 ? t("access.permissionLevelDesc", { level: "L2" }) : undefined} onClick={() => rollback(backupsFor.path, b.path)}>{I.back({ size: 11 })}<span>{t("dev.rollback")}</span></button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Modal>
      )}
    </div>
  )
}

export function OperationsScreen() {
  const { t } = useTranslation()
  const { agents } = useData()
  const [tab, setTab] = useState<Tab>("packages")
  const [agentId, setAgentId] = useState("")
  const selectedAgent = agents.find((agent) => agent.id === agentId)
  const permission = selectedAgent?.permissionLevel ?? 0
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
          agents.length === 0 ? <ContentState kind="empty" title={t("mon.noAgents")} description={t("mon.noAgentsDesc")} /> : <LoadingState />
        ) : tab === "packages" ? (
          <PackagesPanel agentId={agentId} permission={permission} />
        ) : tab === "scripts" ? (
          <ScriptsPanel agentId={agentId} permission={permission} />
        ) : tab === "configs" ? (
          <ConfigsPanel agentId={agentId} permission={permission} />
        ) : (
          <HealthPanel agentId={agentId} />
        )}
      </div>
    </div>
  )
}
