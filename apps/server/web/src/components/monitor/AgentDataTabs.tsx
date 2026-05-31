import { useMemo, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useAgentCommand } from "@/hooks/useAgentCommand"
import { formatBytes, toneFor } from "@/lib/format"

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

function StatePanel({ loading, error, empty, emptyMsg }: { loading: boolean; error: string | null; empty: boolean; emptyMsg: string }) {
  const { t } = useTranslation()
  if (loading) return <div style={{ padding: 32, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}><span className="dot pulse ok" /> {t("common.loading")}</div>
  if (error) return <div className="badge crit" style={{ height: "auto", padding: 10, margin: "12px 0" }}>{error}</div>
  if (empty) return <div style={{ padding: 32, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{emptyMsg}</div>
  return null
}

export function ProcessesTab({ agentId }: { agentId: string }) {
  const { t } = useTranslation()
  const { data, loading, error, reload } = useAgentCommand(agentId, "PROCESS_LIST")
  const [q, setQ] = useState("")
  const rows = useMemo(() => {
    const list = [...(data?.processes ?? [])].sort((a, b) => b.cpuPercent - a.cpuPercent)
    const ql = q.toLowerCase()
    return ql ? list.filter((p) => p.name.toLowerCase().includes(ql) || String(p.pid).includes(ql) || p.user.toLowerCase().includes(ql)) : list
  }, [data, q])

  return (
    <div className="col" style={{ padding: 20 }}>
      <Toolbar count={rows.length} loading={loading} onReload={reload} q={q} setQ={setQ} />
      <StatePanel loading={loading && !data} error={error} empty={!!data && rows.length === 0} emptyMsg={t("mon.noProcesses")} />
      {data && rows.length > 0 && (
        <div className="card" style={{ overflow: "auto" }}>
          <table className="tbl" style={{ minWidth: 720 }}>
            <thead><tr><th>{t("mon.pid")}</th><th>{t("sessions.user")}</th><th style={{ width: 160 }}>CPU</th><th style={{ textAlign: "right" }}>MEM</th><th>{t("mon.state")}</th><th>{t("mon.command")}</th></tr></thead>
            <tbody>
              {rows.slice(0, 300).map((p) => (
                <tr key={p.pid}>
                  <td className="mono num">{p.pid}</td>
                  <td className="mono dim">{p.user || "—"}</td>
                  <td>
                    <div className="row gap-2" style={{ alignItems: "center" }}>
                      <div className="meter" style={{ flex: 1, height: 4 }}><div className={`meter-fill ${toneFor(p.cpuPercent)}`} style={{ width: `${Math.min(100, p.cpuPercent)}%` }} /></div>
                      <span className="mono num" style={{ fontSize: 11, minWidth: 38, textAlign: "right", color: toneFor(p.cpuPercent) ? `var(--${toneFor(p.cpuPercent)})` : "var(--fg-2)" }}>{p.cpuPercent.toFixed(1)}%</span>
                    </div>
                  </td>
                  <td className="mono num dim" style={{ textAlign: "right" }}>{formatBytes(p.memoryBytes)}</td>
                  <td className="mono dim">{p.status}</td>
                  <td className="mono truncate" style={{ maxWidth: 320 }}>{p.name}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

export function DockerTab({ agentId }: { agentId: string }) {
  const { t } = useTranslation()
  const { data, loading, error, reload } = useAgentCommand(agentId, "DOCKER_LIST")
  const [q, setQ] = useState("")
  const rows = useMemo(() => {
    const list = data?.containers ?? []
    const ql = q.toLowerCase()
    return ql ? list.filter((c) => c.name.toLowerCase().includes(ql) || c.image.toLowerCase().includes(ql)) : list
  }, [data, q])

  return (
    <div className="col" style={{ padding: 20 }}>
      <Toolbar count={rows.length} loading={loading} onReload={reload} q={q} setQ={setQ} />
      <StatePanel loading={loading && !data} error={error} empty={!!data && rows.length === 0} emptyMsg={t("mon.noContainers")} />
      {data && rows.length > 0 && (
        <div className="card" style={{ overflow: "auto" }}>
          <table className="tbl" style={{ minWidth: 720 }}>
            <thead><tr><th>{t("mon.tabDocker")}</th><th>{t("mon.image")}</th><th>{t("mon.state")}</th><th>{t("acc.status")}</th><th>{t("mon.created")}</th></tr></thead>
            <tbody>
              {rows.map((c) => {
                const running = /run|up/i.test(c.state || c.status)
                return (
                  <tr key={c.id}>
                    <td><span className="row gap-2" style={{ alignItems: "center" }}><span className={`dot ${running ? "ok" : "crit"}`} /><span className="mono" style={{ fontWeight: 500 }}>{c.name}</span></span></td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{c.image}</td>
                    <td className="mono">{c.state || "—"}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{c.status || "—"}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{c.created || "—"}</td>
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

const LEVEL_COLOR: Record<string, string> = { info: "var(--fg-3)", warn: "var(--warn)", warning: "var(--warn)", error: "var(--crit)", err: "var(--crit)", debug: "var(--fg-dim)" }

export function ServicesTab({ agentId }: { agentId: string }) {
  const { t } = useTranslation()
  const { data, loading, error, reload } = useAgentCommand(agentId, "SERVICE_LIST")
  const [q, setQ] = useState("")
  const rows = useMemo(() => {
    const list = data?.services ?? []
    const ql = q.toLowerCase()
    return ql ? list.filter((s) => s.name.toLowerCase().includes(ql) || (s.description || "").toLowerCase().includes(ql)) : list
  }, [data, q])

  return (
    <div className="col" style={{ padding: 20 }}>
      <Toolbar count={rows.length} loading={loading} onReload={reload} q={q} setQ={setQ} />
      <StatePanel loading={loading && !data} error={error} empty={!!data && rows.length === 0} emptyMsg={t("common.noData")} />
      {data && rows.length > 0 && (
        <div className="card" style={{ overflow: "auto" }}>
          <table className="tbl" style={{ minWidth: 720 }}>
            <thead><tr><th>{t("mon.tabServices")}</th><th>{t("acc.status")}</th><th>{t("mon.state")}</th><th>{t("dev.path")}</th></tr></thead>
            <tbody>
              {rows.slice(0, 400).map((s, i) => {
                const active = /active|running/i.test(s.status) || /running/i.test(s.subState || "")
                const failed = /fail/i.test(s.status) || /fail|dead/i.test(s.subState || "")
                return (
                  <tr key={s.name + i}>
                    <td className="mono" style={{ fontWeight: 500 }}>{s.name}</td>
                    <td><span className="row gap-2" style={{ alignItems: "center" }}><span className={`dot ${active ? "ok" : failed ? "crit" : "off"}`} /><span style={{ fontSize: 11.5, color: active ? "var(--ok)" : failed ? "var(--crit)" : "var(--fg-3)" }}>{s.status}</span></span></td>
                    <td className="mono dim">{s.subState || "—"}</td>
                    <td className="muted truncate" style={{ maxWidth: 360, fontSize: 11.5 }}>{s.description || "—"}</td>
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

const parentDir = (p: string) => {
  if (p === "/" || p === "") return "/"
  const trimmed = p.replace(/\/+$/, "")
  const idx = trimmed.lastIndexOf("/")
  return idx <= 0 ? "/" : trimmed.slice(0, idx)
}

export function FilesTab({ agentId }: { agentId: string }) {
  const { t } = useTranslation()
  const [path, setPath] = useState("/var/log")
  const [input, setInput] = useState("/var/log")
  const { data, loading, error, reload } = useAgentCommand(agentId, "FILE_LIST", { target: path })
  const entries = data?.files ?? []

  function go(p: string) {
    setPath(p)
    setInput(p)
  }

  return (
    <div className="col" style={{ padding: 20, gap: 12 }}>
      <div className="row gap-2" style={{ flexWrap: "wrap" }}>
        <button className="btn btn-sm btn-ghost btn-icon" title="Up" onClick={() => go(parentDir(path))}>{I.back({ size: 13 })}</button>
        <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 10px", height: 30, flex: 1, minWidth: 220 }}>
          {I.audit({ size: 13 })}
          <input value={input} onChange={(e) => setInput(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") go(input) }} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "var(--font-mono)", fontSize: 12 }} />
        </div>
        <button className="btn btn-sm" onClick={() => go(input)}>{t("dev.query")}</button>
        <button className="btn btn-sm btn-ghost" onClick={reload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button>
      </div>
      <StatePanel loading={loading && !data} error={error} empty={!!data && entries.length === 0} emptyMsg={t("common.noData")} />
      {data && entries.length > 0 && (
        <div className="card" style={{ overflow: "auto" }}>
          <table className="tbl" style={{ minWidth: 600 }}>
            <thead><tr><th>{t("dev.path")}</th><th style={{ textAlign: "right" }}>{t("dev.size")}</th><th style={{ textAlign: "right" }}>{t("dev.modified")}</th></tr></thead>
            <tbody>
              {entries.map((e) => (
                <tr key={e.name} style={e.isDir ? { cursor: "pointer" } : {}} onClick={() => e.isDir && go(`${path.replace(/\/+$/, "")}/${e.name}`)}>
                  <td>
                    <span className="row gap-2" style={{ alignItems: "center" }}>
                      <span style={{ color: "var(--fg-4)" }}>{e.isDir ? I.dashboard({ size: 13 }) : I.audit({ size: 13 })}</span>
                      <span className="mono" style={{ color: e.isDir ? "var(--fg)" : "var(--fg-2)" }}>{e.name}{e.isDir ? "/" : ""}</span>
                    </span>
                  </td>
                  <td className="mono num dim" style={{ textAlign: "right", fontSize: 11 }}>{e.isDir ? "—" : formatBytes(e.size ?? 0)}</td>
                  <td className="mono dim" style={{ textAlign: "right", fontSize: 11 }}>{e.modified ? new Date(e.modified).toLocaleString() : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

export function AgentLogsTab({ agentId, permission }: { agentId: string; permission: number }) {
  const { t } = useTranslation()
  const enabled = permission >= 1
  const { data, loading, error, reload } = useAgentCommand(agentId, "SYSTEM_LOGS", { enabled })
  const lines = data?.logResult?.lines ?? []

  if (!enabled) {
    return (
      <div style={{ padding: 40, textAlign: "center" }}>
        <span style={{ color: "var(--fg-4)" }}>{I.shield({ size: 32 })}</span>
        <div style={{ marginTop: 12, fontSize: 13 }}>{t("mon.noAccess")} · L1+</div>
      </div>
    )
  }

  return (
    <div className="col" style={{ padding: 20, gap: 12, height: "100%" }}>
      <div className="row gap-2" style={{ justifyContent: "space-between" }}>
        <span className="mono dim" style={{ fontSize: 11, alignSelf: "center" }}>{data?.logResult?.logSource || "system"} · {lines.length} {t("dev.lines2")}</span>
        <button className="btn btn-sm btn-ghost" onClick={reload} disabled={loading}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 13 })}</button>
      </div>
      <StatePanel loading={loading && !data} error={error} empty={!!data && lines.length === 0} emptyMsg={t("common.noData")} />
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
