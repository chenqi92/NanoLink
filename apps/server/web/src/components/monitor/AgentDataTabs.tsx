import { useCallback, useMemo, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useAgentCommand, runAgentCommand } from "@/hooks/useAgentCommand"
import { Modal } from "@/components/shell/Dialog"
import { formatBytes, toneFor } from "@/lib/format"
import { ContentState, LoadingState, RequestState } from "@/components/shell/RequestState"
import { userErrorMessage } from "@/lib/errors"
import { isServiceActive } from "@/lib/fleet"

const SERVICE_CONTROL_LEVEL = 2

function uptimeFrom(start?: number): string {
  if (!start) return "—"
  const ms = start < 1e12 ? start * 1000 : start
  let s = Math.max(0, Math.floor((Date.now() - ms) / 1000))
  const d = Math.floor(s / 86400)
  s %= 86400
  const h = Math.floor(s / 3600)
  s %= 3600
  const m = Math.floor(s / 60)
  return d ? `${d}d${h}h` : h ? `${h}h${m}m` : `${m}m${s}s`
}

/** Imperative agent-command runner with transient feedback, shared by the action tabs. */
function useCommandAction(agentId: string, onDone?: () => void) {
  const { t } = useTranslation()
  const [busy, setBusy] = useState<string | null>(null)
  const [flash, setFlash] = useState<{ kind: "ok" | "crit"; text: string } | null>(null)
  const run = useCallback(
    async (key: string, type: string, opts: { target?: string; params?: Record<string, string> } = {}) => {
      setBusy(key)
      setFlash(null)
      try {
        await runAgentCommand(agentId, type, opts)
        setFlash({ kind: "ok", text: t("dev.cmdSent") })
        onDone?.()
      } catch (e) {
        setFlash({ kind: "crit", text: userErrorMessage(e, t) })
      } finally {
        setBusy(null)
      }
    },
    [agentId, onDone, t],
  )
  return { busy, flash, setFlash, run }
}

function Flash({ flash, onClose }: { flash: { kind: "ok" | "crit"; text: string } | null; onClose: () => void }) {
  if (!flash) return null
  return (
    <div className={`badge ${flash.kind}`} style={{ height: "auto", padding: "6px 10px", marginBottom: 10, cursor: "pointer" }} onClick={onClose} role="status">
      {flash.text}
    </div>
  )
}

function Toolbar({ count, loading, onReload, q, setQ, extra }: { count: number; loading: boolean; onReload: () => void; q: string; setQ: (v: string) => void; extra?: React.ReactNode }) {
  const { t } = useTranslation()
  return (
    <div className="row gap-2" style={{ marginBottom: 12, justifyContent: "space-between", flexWrap: "wrap" }}>
      <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 10px", height: 30, minWidth: 220 }}>
        {I.search({ size: 13 })}
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder={t("mon.search")} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "inherit", fontSize: 12 }} />
      </div>
      <div className="row gap-2" style={{ alignItems: "center" }}>
        {extra}
        <span className="mono dim" style={{ fontSize: 11 }}>{count}</span>
        <button className="btn btn-sm btn-ghost" onClick={onReload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button>
      </div>
    </div>
  )
}

function StatePanel({ loading, error, empty, emptyMsg, onRetry }: { loading: boolean; error: unknown; empty: boolean; emptyMsg: string; onRetry?: () => void }) {
  if (loading) return <LoadingState compact />
  if (error != null) return <RequestState error={error} onRetry={onRetry} compact />
  if (empty) return <ContentState kind="empty" title={emptyMsg} compact />
  return null
}

const SORTS = [
  { k: "cpu", l: "metrics.cpu" },
  { k: "mem", l: "metrics.memory" },
  { k: "pid", l: "mon.pid" },
] as const
type ProcSort = (typeof SORTS)[number]["k"]

const KILL_SIGNALS = ["SIGTERM", "SIGINT", "SIGKILL"] as const

export function ProcessesTab({ agentId, permission = 0 }: { agentId: string; permission?: number }) {
  const { t } = useTranslation()
  const { data, loading, error, reload } = useAgentCommand(agentId, "PROCESS_LIST")
  const { busy, flash, setFlash, run } = useCommandAction(agentId, reload)
  const [q, setQ] = useState("")
  const [sort, setSort] = useState<ProcSort>("cpu")
  const [killTarget, setKillTarget] = useState<{ pid?: number; user?: string; name?: string } | null>(null)
  const [signal, setSignal] = useState<(typeof KILL_SIGNALS)[number]>("SIGTERM")
  const canControl = permission >= SERVICE_CONTROL_LEVEL

  const rows = useMemo(() => {
    const list = [...(data?.processes ?? [])]
    list.sort((a, b) => (sort === "cpu" ? (b.cpuPercent ?? 0) - (a.cpuPercent ?? 0) : sort === "mem" ? (b.memoryBytes ?? 0) - (a.memoryBytes ?? 0) : (a.pid ?? 0) - (b.pid ?? 0)))
    const ql = q.toLowerCase()
    return ql ? list.filter((p) => (p.name ?? "").toLowerCase().includes(ql) || String(p.pid ?? "").includes(ql) || (p.user ?? "").toLowerCase().includes(ql)) : list
  }, [data, q, sort])

  function confirmKill() {
    if (!killTarget?.pid) return
    run(`kill-${killTarget.pid}`, "PROCESS_KILL", { target: String(killTarget.pid), params: { signal } })
    setKillTarget(null)
  }

  const sortToggle = (
    <div className="row gap-1" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: 3 }}>
      {SORTS.map((s) => (
        <button key={s.k} onClick={() => setSort(s.k)} className="btn btn-sm" style={{ background: sort === s.k ? "var(--panel)" : "transparent", border: sort === s.k ? "1px solid var(--border-2)" : "1px solid transparent", color: sort === s.k ? "var(--fg)" : "var(--fg-4)", height: 24, padding: "0 10px", fontFamily: "var(--font-mono)", fontSize: 11 }}>{t(s.l)}</button>
      ))}
    </div>
  )

  return (
    <div className="col" style={{ padding: 20 }}>
      <Toolbar count={rows.length} loading={loading} onReload={reload} q={q} setQ={setQ} extra={sortToggle} />
      <Flash flash={flash} onClose={() => setFlash(null)} />
      <StatePanel loading={loading && !data} error={error} empty={!!data && rows.length === 0} emptyMsg={t("mon.noProcesses")} onRetry={reload} />
      {data && rows.length > 0 && (
        <div className="card" style={{ overflow: "auto" }}>
          <table className="tbl" style={{ minWidth: 760 }}>
            <thead><tr><th>{t("mon.pid")}</th><th>{t("sessions.user")}</th><th style={{ width: 160 }}>{t("metrics.cpu")}</th><th style={{ textAlign: "right" }}>{t("metrics.memory")}</th><th>{t("metrics.time")}</th><th>{t("mon.state")}</th><th>{t("mon.command")}</th><th style={{ textAlign: "right" }} /></tr></thead>
            <tbody>
              {rows.slice(0, 300).map((p) => (
                <tr key={p.pid}>
                  <td className="mono num">{p.pid}</td>
                  <td className="mono dim">{p.user || "—"}</td>
                  <td>
                    <div className="row gap-2" style={{ alignItems: "center" }}>
                      <div className="meter" style={{ flex: 1, height: 4 }}><div className={`meter-fill ${toneFor(p.cpuPercent ?? 0)}`} style={{ width: `${Math.min(100, p.cpuPercent ?? 0)}%` }} /></div>
                      <span className="mono num" style={{ fontSize: 11, minWidth: 38, textAlign: "right", color: toneFor(p.cpuPercent ?? 0) ? `var(--${toneFor(p.cpuPercent ?? 0)})` : "var(--fg-2)" }}>{(p.cpuPercent ?? 0).toFixed(1)}%</span>
                    </div>
                  </td>
                  <td className="mono num dim" style={{ textAlign: "right" }}>{formatBytes(p.memoryBytes)}</td>
                  <td className="mono num dim" style={{ fontSize: 11 }}>{uptimeFrom(p.startTime)}</td>
                  <td className="mono dim">{p.status}</td>
                  <td className="mono truncate" style={{ maxWidth: 300 }}>{p.name}</td>
                  <td style={{ textAlign: "right" }}>
                    <button className="btn btn-sm btn-ghost" disabled={!canControl || busy === `kill-${p.pid}`} title={canControl ? undefined : t("dev.needL2")} onClick={(e) => { e.stopPropagation(); setKillTarget(p); setSignal("SIGTERM") }}>
                      {I.x({ size: 11 })}<span style={{ fontSize: 11 }}>{t("dev.kill")}</span>
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {killTarget && (
        <Modal
          width={460}
          onClose={() => setKillTarget(null)}
          title={<span className="row gap-2" style={{ alignItems: "center" }}>{I.warn({ size: 14 })}<span>{t("dev.killProcess")}</span></span>}
          footer={
            <>
              <button className="btn btn-sm" onClick={() => setKillTarget(null)}>{t("common.cancel")}</button>
              <button className="btn btn-sm btn-danger" onClick={confirmKill}>{I.x({ size: 13 })}<span>{t("dev.kill")}</span></button>
            </>
          }
        >
          <div style={{ fontSize: 12.5, color: "var(--fg-2)", marginBottom: 12, lineHeight: 1.6 }}>{t("dev.killDesc", { signal, pid: killTarget.pid })}</div>
          <pre className="code" style={{ fontSize: 11 }}>{`PID:  ${killTarget.pid}\nUSER: ${killTarget.user ?? "—"}\nCMD:  ${killTarget.name ?? "—"}`}</pre>
          <div className="row gap-2" style={{ marginTop: 12, alignItems: "center" }}>
            <span className="muted" style={{ fontSize: 11.5 }}>{t("dev.signal")}</span>
            <div className="row gap-1">
              {KILL_SIGNALS.map((s) => (
                <button key={s} className="btn btn-sm" onClick={() => setSignal(s)} style={{ height: 24, fontSize: 11, fontFamily: "var(--font-mono)", background: s === signal ? "var(--panel)" : "transparent", border: s === signal ? "1px solid var(--border-strong)" : "1px solid var(--border-2)" }}>{s}</button>
              ))}
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}

const LEVEL_COLOR: Record<string, string> = { info: "var(--fg-3)", warn: "var(--warn)", warning: "var(--warn)", error: "var(--crit)", err: "var(--crit)", debug: "var(--fg-dim)" }

export function ServicesTab({ agentId, permission = 0 }: { agentId: string; permission?: number }) {
  const { t } = useTranslation()
  const { data, loading, error, reload } = useAgentCommand(agentId, "SERVICE_LIST")
  const { busy, flash, setFlash, run } = useCommandAction(agentId, reload)
  const [q, setQ] = useState("")
  const canControl = permission >= SERVICE_CONTROL_LEVEL

  const list = useMemo(() => data?.services ?? [], [data])
  const activeCount = list.filter((s) => /active|running/i.test(s.status)).length
  const failedCount = list.filter((s) => /fail/i.test(s.status) || /fail|dead/i.test(s.subState || "")).length
  const rows = useMemo(() => {
    const ql = q.toLowerCase()
    return ql ? list.filter((s) => s.name.toLowerCase().includes(ql) || (s.description || "").toLowerCase().includes(ql)) : list
  }, [list, q])

  const summary = (
    <span className="row gap-2" style={{ alignItems: "center", fontSize: 11.5 }}>
      <span className="mono" style={{ color: "var(--ok)" }}>{activeCount} {t("dev.active")}</span>
      <span className="mono dim">·</span>
      <span className="mono" style={{ color: failedCount ? "var(--crit)" : "var(--fg-4)" }}>{failedCount} {t("dev.failedState")}</span>
    </span>
  )

  return (
    <div className="col" style={{ padding: 20 }}>
      <Toolbar count={rows.length} loading={loading} onReload={reload} q={q} setQ={setQ} extra={summary} />
      <Flash flash={flash} onClose={() => setFlash(null)} />
      <StatePanel loading={loading && !data} error={error} empty={!!data && rows.length === 0} emptyMsg={t("common.noData")} onRetry={reload} />
      {data && rows.length > 0 && (
        <div className="card" style={{ overflow: "auto" }}>
          <table className="tbl" style={{ minWidth: 760 }}>
            <thead><tr><th>{t("mon.tabServices")}</th><th>{t("acc.status")}</th><th>{t("mon.state")}</th><th>{t("dev.uptime")}</th><th style={{ textAlign: "right" }}>{t("dev.restarts")}</th><th>{t("dev.path")}</th><th style={{ textAlign: "right" }}>{t("dev.actions")}</th></tr></thead>
            <tbody>
              {rows.slice(0, 400).map((s, i) => {
                const active = isServiceActive(s.status, s.subState)
                const failed = /fail/i.test(s.status) || /fail|dead/i.test(s.subState || "")
                const k = (op: string) => `svc-${op}-${s.name}`
                return (
                  <tr key={s.name + i}>
                    <td className="mono" style={{ fontWeight: 500 }}>{s.name}</td>
                    <td><span className="row gap-2" style={{ alignItems: "center" }}><span className={`dot ${active ? "ok" : failed ? "crit" : "off"}`} /><span style={{ fontSize: 11.5, color: active ? "var(--ok)" : failed ? "var(--crit)" : "var(--fg-3)" }}>{s.status}</span></span></td>
                    <td className="mono dim">{s.subState || "—"}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{s.uptime || "—"}</td>
                    <td className="mono num" style={{ textAlign: "right", color: (s.restarts ?? 0) > 3 ? "var(--warn)" : "var(--fg-3)" }}>{s.restarts ?? 0}</td>
                    <td className="muted truncate" style={{ maxWidth: 280, fontSize: 11.5 }}>{s.description || "—"}</td>
                    <td style={{ textAlign: "right" }}>
                      <div className="row gap-1" style={{ justifyContent: "flex-end" }}>
                        <button className="btn btn-sm btn-ghost" disabled={!canControl || !!busy} title={canControl ? undefined : t("dev.needL2")} onClick={() => run(k("restart"), "SERVICE_RESTART", { target: s.name })}>{busy === k("restart") ? <span className="dot pulse ok" /> : I.refresh({ size: 11 })}<span style={{ fontSize: 11 }}>{t("dev.restart")}</span></button>
                        {active ? (
                          <button className="btn btn-sm btn-ghost btn-icon" disabled={!canControl || !!busy} title={canControl ? t("dev.stop") : t("dev.needL2")} onClick={() => run(k("stop"), "SERVICE_STOP", { target: s.name })}>{busy === k("stop") ? <span className="dot pulse ok" /> : I.power({ size: 11 })}</button>
                        ) : (
                          <button className="btn btn-sm btn-ghost btn-icon" disabled={!canControl || !!busy} title={canControl ? t("dev.start") : t("dev.needL2")} onClick={() => run(k("start"), "SERVICE_START", { target: s.name })}>{busy === k("start") ? <span className="dot pulse ok" /> : I.power({ size: 11 })}</button>
                        )}
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

export function DockerTab({ agentId, permission = 0 }: { agentId: string; permission?: number }) {
  const { t } = useTranslation()
  const { data, loading, error, reload } = useAgentCommand(agentId, "DOCKER_LIST")
  const { busy, flash, setFlash, run } = useCommandAction(agentId, reload)
  const [q, setQ] = useState("")
  const [logsFor, setLogsFor] = useState<{ id: string; name: string } | null>(null)
  const canControl = permission >= SERVICE_CONTROL_LEVEL

  const list = useMemo(() => data?.containers ?? [], [data])
  const runningCount = list.filter((c) => /run|up/i.test(c.state || c.status)).length
  const exitedCount = list.length - runningCount
  const rows = useMemo(() => {
    const ql = q.toLowerCase()
    return ql ? list.filter((c) => c.name.toLowerCase().includes(ql) || c.image.toLowerCase().includes(ql)) : list
  }, [list, q])

  const summary = (
    <span className="row gap-2" style={{ alignItems: "center", fontSize: 11.5 }}>
      <span className="mono" style={{ color: "var(--ok)" }}>{runningCount} {t("dev.running")}</span>
      <span className="mono dim">·</span>
      <span className="mono dim">{exitedCount} {t("dev.exited")}</span>
    </span>
  )

  return (
    <div className="col" style={{ padding: 20 }}>
      <Toolbar count={rows.length} loading={loading} onReload={reload} q={q} setQ={setQ} extra={summary} />
      <Flash flash={flash} onClose={() => setFlash(null)} />
      <StatePanel loading={loading && !data} error={error} empty={!!data && rows.length === 0} emptyMsg={t("mon.noContainers")} onRetry={reload} />
      {data && rows.length > 0 && (
        <div className="card" style={{ overflow: "auto" }}>
          <table className="tbl" style={{ minWidth: 760 }}>
            <thead><tr><th>{t("mon.tabDocker")}</th><th>{t("mon.image")}</th><th>{t("mon.state")}</th><th style={{ width: 150 }}>{t("metrics.cpu")} / {t("metrics.memory")}</th><th>{t("dev.ports")}</th><th>{t("dev.network")}</th><th style={{ textAlign: "right" }}>{t("dev.actions")}</th></tr></thead>
            <tbody>
              {rows.map((c) => {
                const running = /run|up/i.test(c.state || c.status)
                const memPct = c.memoryLimit ? ((c.memoryBytes ?? 0) / c.memoryLimit) * 100 : 0
                const k = (op: string) => `dk-${op}-${c.id}`
                return (
                  <tr key={c.id}>
                    <td><span className="row gap-2" style={{ alignItems: "center" }}><span className={`dot ${running ? "ok" : "crit"}`} /><span className="mono" style={{ fontWeight: 500 }}>{c.name}</span></span></td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{c.image}</td>
                    <td className="mono">{c.state || c.status || "—"}</td>
                    <td>
                      {running && (c.cpuPercent != null || c.memoryBytes != null) ? (
                        <div className="col" style={{ gap: 3 }}>
                          <div className="row gap-2" style={{ alignItems: "center" }}>
                            <span className="dim mono" style={{ fontSize: 10, width: 26 }}>{t("metrics.cpu")}</span>
                            <div className="meter" style={{ flex: 1, height: 3 }}><div className={`meter-fill ${toneFor(c.cpuPercent ?? 0)}`} style={{ width: `${Math.min(100, c.cpuPercent ?? 0)}%` }} /></div>
                            <span className="mono num" style={{ fontSize: 10.5, minWidth: 32, textAlign: "right" }}>{(c.cpuPercent ?? 0).toFixed(1)}%</span>
                          </div>
                          <div className="row gap-2" style={{ alignItems: "center" }}>
                            <span className="dim mono" style={{ fontSize: 10, width: 26 }}>{t("metrics.memory")}</span>
                            <div className="meter" style={{ flex: 1, height: 3 }}><div className={`meter-fill ${toneFor(memPct)}`} style={{ width: `${Math.min(100, memPct)}%` }} /></div>
                            <span className="mono num dim" style={{ fontSize: 10.5, minWidth: 52, textAlign: "right" }}>{c.memoryBytes ? formatBytes(c.memoryBytes) : "—"}</span>
                          </div>
                        </div>
                      ) : <span className="dim mono" style={{ fontSize: 11 }}>—</span>}
                    </td>
                    <td className="mono dim" style={{ fontSize: 10.5 }}>{c.ports || "—"}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{c.network || "—"}</td>
                    <td style={{ textAlign: "right" }}>
                      <div className="row gap-1" style={{ justifyContent: "flex-end" }}>
                        <button
                          className="btn btn-sm btn-ghost"
                          disabled={permission < 1}
                          title={permission < 1 ? t("access.permissionLevelDesc", { level: "L1" }) : undefined}
                          onClick={() => setLogsFor({ id: c.id, name: c.name })}
                        >
                          {permission < 1 ? I.lock({ size: 11 }) : I.audit({ size: 11 })}
                          <span style={{ fontSize: 11 }}>{t("dev.logs")}</span>
                        </button>
                        {running ? (
                          <>
                            <button className="btn btn-sm btn-ghost" disabled={!canControl || !!busy} title={canControl ? undefined : t("dev.needL2")} onClick={() => run(k("restart"), "DOCKER_RESTART", { target: c.id })}>{busy === k("restart") ? <span className="dot pulse ok" /> : I.refresh({ size: 11 })}<span style={{ fontSize: 11 }}>{t("dev.restart")}</span></button>
                            <button className="btn btn-sm btn-ghost btn-icon" disabled={!canControl || !!busy} title={canControl ? t("dev.stop") : t("dev.needL2")} onClick={() => run(k("stop"), "DOCKER_STOP", { target: c.id })}>{busy === k("stop") ? <span className="dot pulse ok" /> : I.power({ size: 11 })}</button>
                          </>
                        ) : (
                          <button className="btn btn-sm btn-ghost" disabled={!canControl || !!busy} title={canControl ? undefined : t("dev.needL2")} onClick={() => run(k("start"), "DOCKER_START", { target: c.id })}>{busy === k("start") ? <span className="dot pulse ok" /> : I.power({ size: 11 })}<span style={{ fontSize: 11 }}>{t("dev.start")}</span></button>
                        )}
                      </div>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
      {logsFor && permission >= 1 && <ContainerLogsModal agentId={agentId} container={logsFor} onClose={() => setLogsFor(null)} />}
    </div>
  )
}

function ContainerLogsModal({ agentId, container, onClose }: { agentId: string; container: { id: string; name: string }; onClose: () => void }) {
  const { t } = useTranslation()
  const { data, loading, error } = useAgentCommand(agentId, "DOCKER_LOGS", { target: container.id })
  const text = data?.output ?? (data?.logResult?.lines ?? []).map((l) => `${l.timestamp ?? ""} ${l.message}`).join("\n")
  return (
    <Modal width={720} onClose={onClose} title={`${t("dev.containerLogs")} · ${container.name}`}>
      {loading && !data ? (
        <LoadingState compact />
      ) : error != null ? (
        <RequestState error={error} compact />
      ) : text ? (
        <pre className="code" style={{ fontSize: 11 }}>{text}</pre>
      ) : (
        <div style={{ padding: 24, textAlign: "center", color: "var(--fg-4)" }}>{t("dev.noLines")}</div>
      )}
    </Modal>
  )
}

const parentDir = (p: string) => {
  if (p === "/" || p === "") return "/"
  const trimmed = p.replace(/\/+$/, "")
  const idx = trimmed.lastIndexOf("/")
  return idx <= 0 ? "/" : trimmed.slice(0, idx)
}

export function FilesTab({ agentId, permission = 0 }: { agentId: string; permission?: number }) {
  const { t } = useTranslation()
  const [path, setPath] = useState("/var/log")
  const [input, setInput] = useState("/var/log")
  const [selected, setSelected] = useState<string | null>(null)
  const { data, loading, error, reload } = useAgentCommand(agentId, "FILE_LIST", { target: path })
  const entries = data?.files ?? []

  function go(p: string) {
    setPath(p)
    setInput(p)
    setSelected(null)
  }

  return (
    <div className="row" style={{ padding: 20, gap: 14, height: "100%", overflow: "hidden", alignItems: "stretch" }}>
      <div className="card col" style={{ width: 340, overflow: "hidden", flexShrink: 0 }}>
        <div className="row gap-2" style={{ padding: "8px 10px", borderBottom: "1px solid var(--border)", flexWrap: "wrap" }}>
          <button className="btn btn-sm btn-ghost btn-icon" title={t("dev.goUp")} aria-label={t("dev.goUp")} onClick={() => go(parentDir(path))}>{I.back({ size: 13 })}</button>
          <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 8px", height: 28, flex: 1, minWidth: 140 }}>
            {I.audit({ size: 12 })}
            <input value={input} onChange={(e) => setInput(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") go(input) }} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "var(--font-mono)", fontSize: 11.5 }} />
          </div>
          <button className="btn btn-sm btn-ghost btn-icon" onClick={reload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button>
        </div>
        <div className="col" style={{ flex: 1, overflow: "auto" }}>
          <StatePanel loading={loading && !data} error={error} empty={!!data && entries.length === 0} emptyMsg={t("common.noData")} onRetry={reload} />
          {entries.map((e) => {
            const full = `${path.replace(/\/+$/, "")}/${e.name}`
            const isSel = selected === full
            return (
              <div key={e.name} onClick={() => (e.isDir ? go(full) : setSelected(full))} style={{ padding: "8px 12px", display: "flex", gap: 8, alignItems: "center", cursor: "pointer", background: isSel ? "var(--panel-2)" : "transparent", borderLeft: isSel ? "2px solid var(--fg)" : "2px solid transparent", fontSize: 11.5 }}>
                <span style={{ color: e.isDir ? "var(--info)" : "var(--fg-4)" }}>{e.isDir ? I.disk({ size: 12 }) : I.audit({ size: 12 })}</span>
                <span className="mono truncate" style={{ flex: 1, color: e.isDir ? "var(--fg)" : "var(--fg-2)" }}>{e.name}{e.isDir ? "/" : ""}</span>
                <span className="mono dim" style={{ fontSize: 10 }}>{e.isDir ? "" : formatBytes(e.size ?? 0)}</span>
              </div>
            )
          })}
        </div>
      </div>
      <div className="card col flex-1" style={{ overflow: "hidden" }}>
        {selected ? (
          <FileViewer key={selected} agentId={agentId} path={selected} permission={permission} />
        ) : (
          <div className="col" style={{ flex: 1, alignItems: "center", justifyContent: "center", color: "var(--fg-4)" }}>
            {I.audit({ size: 32 })}
            <div style={{ marginTop: 10, fontSize: 13 }}>{t("dev.selectFile")}</div>
          </div>
        )}
      </div>
    </div>
  )
}

function FileViewer({ agentId, path, permission }: { agentId: string; path: string; permission: number }) {
  const { t } = useTranslation()
  const [tailing, setTailing] = useState(true)
  const { data, loading, error, reload } = useAgentCommand(agentId, "FILE_TAIL", { target: path, params: { lines: "300" } })
  const { busy, flash, setFlash, run } = useCommandAction(agentId)
  const lines = useMemo(() => {
    const fromResult = data?.logResult?.lines
    if (fromResult && fromResult.length) return fromResult.map((l) => ({ level: l.level, text: `${l.timestamp ? l.timestamp + " " : ""}${l.message}` }))
    const out = data?.output ?? ""
    return out ? out.split("\n").map((text) => ({ level: undefined as string | undefined, text })) : []
  }, [data])

  return (
    <>
      <div className="row" style={{ padding: "10px 14px", borderBottom: "1px solid var(--border)", justifyContent: "space-between", alignItems: "center", gap: 10 }}>
        <div className="mono truncate" style={{ fontSize: 12.5, fontWeight: 500, minWidth: 0 }}>{path}</div>
        <div className="row gap-2" style={{ flexShrink: 0 }}>
          <button onClick={() => { setTailing((v) => !v); reload() }} className="btn btn-sm" style={{ background: tailing ? "var(--panel-2)" : "transparent", borderColor: tailing ? "var(--ok)" : "var(--border-2)", color: tailing ? "var(--ok)" : "var(--fg-3)" }}>
            <span className={`dot ${tailing ? "ok pulse" : ""}`} />
            <span>{t("dev.tail")}</span>
          </button>
          <button className="btn btn-sm btn-ghost" disabled={!!busy || permission < 1} title={permission < 1 ? t("access.permissionLevelDesc", { level: "L1" }) : undefined} onClick={() => run("dl", "FILE_DOWNLOAD", { target: path })}>{busy === "dl" ? <span className="dot pulse ok" /> : I.external({ size: 12 })}<span>{t("dev.download")}</span></button>
          <button className="btn btn-sm btn-ghost btn-icon" onClick={reload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 12 })}</button>
        </div>
      </div>
      {flash && <div className={`badge ${flash.kind}`} style={{ height: "auto", padding: "6px 10px", margin: "8px 14px", cursor: "pointer" }} onClick={() => setFlash(null)}>{flash.text}</div>}
      <div style={{ flex: 1, overflow: "auto", padding: 14, fontFamily: "var(--font-mono)", fontSize: 11.5, lineHeight: 1.6, background: "var(--bg-2)" }}>
        {loading && !data ? (
          <div style={{ color: "var(--fg-4)" }}><span className="dot pulse ok" /> {t("common.loading")}</div>
        ) : error != null ? (
          <RequestState error={error} onRetry={reload} compact />
        ) : lines.length === 0 ? (
          <div style={{ color: "var(--fg-4)" }}>{t("dev.noLines")}</div>
        ) : (
          lines.map((l, i) => (
            <div key={i} style={{ display: "flex", gap: 10, color: l.level ? LEVEL_COLOR[l.level.toLowerCase()] ?? "var(--fg-2)" : "var(--fg-2)", wordBreak: "break-all" }}>
              {l.level && <span style={{ flexShrink: 0, width: 44, textTransform: "uppercase", fontSize: 10, fontWeight: 600 }}>{l.level}</span>}
              <span style={{ flex: 1 }}>{l.text}</span>
            </div>
          ))
        )}
        {tailing && !loading && (
          <div style={{ color: "var(--fg-4)", padding: "4px 0", fontStyle: "italic" }}>
            <span className="dot ok pulse" style={{ marginRight: 6 }} />
            {t("dev.tailWaiting")}
          </div>
        )}
      </div>
    </>
  )
}

const LOG_LEVELS = ["all", "info", "warn", "error", "debug"] as const

export function AgentLogsTab({ agentId, permission }: { agentId: string; permission: number }) {
  const { t } = useTranslation()
  const enabled = permission >= 1
  const { data, loading, error, reload } = useAgentCommand(agentId, "SYSTEM_LOGS", { enabled })
  const [level, setLevel] = useState<(typeof LOG_LEVELS)[number]>("all")
  const [q, setQ] = useState("")
  const all = useMemo(() => data?.logResult?.lines ?? [], [data])
  const lines = useMemo(() => {
    const ql = q.toLowerCase()
    return all.filter((l) => (level === "all" || (l.level ?? "").toLowerCase().startsWith(level)) && (!ql || (l.message ?? "").toLowerCase().includes(ql)))
  }, [all, level, q])

  if (!enabled) {
    return (
      <div style={{ padding: 20 }}><ContentState kind="forbidden" eyebrow={t("access.restricted")} title={t("access.noPermissionTitle")} description={t("access.permissionLevelDesc", { level: "L1" })} /></div>
    )
  }

  return (
    <div className="col" style={{ padding: 20, gap: 12, height: "100%" }}>
      <div className="row gap-2" style={{ justifyContent: "space-between", flexWrap: "wrap" }}>
        <div className="row gap-2" style={{ alignItems: "center" }}>
          <div className="row gap-2" style={{ height: 28, padding: "0 4px 0 10px", background: "var(--panel-2)", border: "1px solid var(--border-2)", borderRadius: 6, alignItems: "center", fontSize: 11.5 }}>
            <span className="muted">{t("dev.level")}</span>
            <select value={level} onChange={(e) => setLevel(e.target.value as typeof level)} className="select" style={{ width: "auto", height: 24, border: "none", background: "transparent", padding: "0 4px" }}>
              {LOG_LEVELS.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
          </div>
          <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 10px", height: 28, minWidth: 200 }}>
            {I.search({ size: 13 })}
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder={t("mon.search")} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "var(--font-mono)", fontSize: 11.5 }} />
          </div>
        </div>
        <div className="row gap-2" style={{ alignItems: "center" }}>
          <span className="mono dim" style={{ fontSize: 11 }}>{data?.logResult?.logSource || "system"} · {lines.length} {t("dev.lines2")}</span>
          <button className="btn btn-sm btn-ghost" onClick={reload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button>
        </div>
      </div>
      <StatePanel loading={loading && !data} error={error} empty={!!data && lines.length === 0} emptyMsg={t("common.noData")} onRetry={reload} />
      {data && lines.length > 0 && (
        <div className="card" style={{ flex: 1, overflow: "auto", background: "var(--bg-2)", padding: "10px 12px", fontFamily: "var(--font-mono)", fontSize: 12, lineHeight: 1.6 }}>
          {lines.map((l, i) => (
            <div key={i} className="row gap-2" style={{ alignItems: "flex-start", whiteSpace: "pre-wrap", color: "var(--fg-2)" }}>
              {l.timestamp && <span className="dim" style={{ flexShrink: 0 }}>{l.timestamp}</span>}
              {l.level && <span style={{ flexShrink: 0, width: 48, color: LEVEL_COLOR[l.level.toLowerCase()] || "var(--fg-3)", textTransform: "uppercase", fontSize: 10.5, fontWeight: 600 }}>{l.level}</span>}
              {l.source && <span className="dim" style={{ flexShrink: 0 }}>{l.source}</span>}
              <span style={{ minWidth: 0 }}>{l.message}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
