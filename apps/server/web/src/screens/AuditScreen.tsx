import { useCallback, useEffect, useMemo, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { auditApi, type AuditLog, type AuditStats } from "@/lib/api"
import { PageHeader, KPI } from "@/components/shell/primitives"
import { Modal } from "@/components/shell/Dialog"

function fmtTime(ts: string | number): string {
  const d = typeof ts === "number" ? new Date(ts < 1e12 ? ts * 1000 : ts) : new Date(ts)
  if (Number.isNaN(d.getTime())) return String(ts)
  return d.toLocaleString()
}

export function AuditScreen() {
  const { t } = useTranslation()
  const [logs, setLogs] = useState<AuditLog[]>([])
  const [stats, setStats] = useState<AuditStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [typeFilter, setTypeFilter] = useState("all")
  const [resultFilter, setResultFilter] = useState("all")
  const [detail, setDetail] = useState<AuditLog | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [l, s] = await Promise.all([
        auditApi.logs({ limit: 200 }).then((r) => r.data ?? []),
        auditApi.stats().catch(() => null),
      ])
      setLogs(l)
      setStats(s)
    } catch {
      setLogs([])
    } finally {
      setLoading(false)
    }
  }, [])
  useEffect(() => { load() }, [load])

  const types = useMemo(() => Array.from(new Set(logs.map((l) => l.commandType))).sort(), [logs])
  const filtered = logs.filter((l) => {
    if (typeFilter !== "all" && l.commandType !== typeFilter) return false
    if (resultFilter === "ok" && !l.success) return false
    if (resultFilter === "fail" && l.success) return false
    return true
  })

  const failed = logs.filter((l) => !l.success).length
  const successRate = stats?.successRate ?? (logs.length ? ((logs.length - failed) / logs.length) * 100 : 0)

  const exportCSV = () => {
    const esc = (v: unknown) => {
      let s = String(v ?? "")
      if (/^[=+\-@]/.test(s.trimStart()) || /^[\t\r\n]/.test(s)) {
        s = `'${s}`
      }
      return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
    }
    const headers = ["time", "commandType", "username", "agent", "params", "ip", "result", "error"]
    const lines = [headers.join(",")]
    for (const l of filtered) {
      lines.push([
        fmtTime(l.timestamp), l.commandType, l.username,
        l.agentHostname || l.agentId || "", l.target || l.params || "",
        l.ipAddress, l.success ? "ok" : "fail", l.error || "",
      ].map(esc).join(","))
    }
    const blob = new Blob([lines.join("\n")], { type: "text/csv;charset=utf-8" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `audit-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader
        title={t("nav.audit")}
        subtitle={t("plat.auditSubtitle")}
        actions={
          <>
            <button className="btn btn-sm" onClick={load}>{I.refresh({ size: 13 })}<span>{t("acc.refresh")}</span></button>
            <button className="btn btn-sm" onClick={exportCSV} disabled={filtered.length === 0}>{I.external({ size: 13 })}<span>{t("dev.export")}</span></button>
          </>
        }
      />
      <div style={{ padding: "0 24px 24px", overflow: "auto", flex: 1 }}>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1.4fr", gap: 12, marginBottom: 16 }}>
          <KPI icon={I.audit({ size: 13 })} label={t("plat.totalCommands")} value={stats?.totalCommands ?? logs.length} />
          <KPI icon={I.check({ size: 13 })} label={t("plat.successRate")} value={`${successRate.toFixed(0)}%`} sub={`${failed} ${t("plat.failed")}`} tone={successRate < 80 ? "warn" : ""} />
          <div className="card" style={{ padding: 14 }}>
            <div className="upper" style={{ color: "var(--fg-4)", marginBottom: 8 }}>{t("plat.uniqueUsers")}</div>
            <div className="col" style={{ gap: 4 }}>
              {(stats?.topUsers ?? []).slice(0, 4).map((u) => (
                <div key={u.username} className="row" style={{ justifyContent: "space-between" }}>
                  <span className="mono" style={{ fontSize: 12 }}>{u.username}</span>
                  <span className="mono num dim" style={{ fontSize: 11 }}>{u.count}</span>
                </div>
              ))}
              {!stats?.topUsers?.length && <span className="dim" style={{ fontSize: 11.5 }}>{t("common.noData")}</span>}
            </div>
          </div>
        </div>

        {/* filters */}
        <div className="row gap-2" style={{ marginBottom: 12 }}>
          <select className="select" style={{ width: "auto" }} value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)}>
            <option value="all">{t("plat.allTypes")}</option>
            {types.map((ty) => <option key={ty} value={ty}>{ty}</option>)}
          </select>
          <select className="select" style={{ width: "auto" }} value={resultFilter} onChange={(e) => setResultFilter(e.target.value)}>
            <option value="all">{t("plat.allResults")}</option>
            <option value="ok">{t("plat.ok")}</option>
            <option value="fail">{t("plat.fail")}</option>
          </select>
        </div>

        <div className="card" style={{ overflow: "auto" }}>
          <table className="tbl" style={{ minWidth: 920 }}>
            <thead>
              <tr><th>{t("plat.time")}</th><th>{t("plat.command")}</th><th>{t("acc.user")}</th><th>{t("dev.agent")}</th><th>{t("plat.params")}</th><th>IP</th><th style={{ textAlign: "right" }}>{t("plat.result")}</th></tr>
            </thead>
            <tbody>
              {loading && logs.length === 0 ? (
                <tr><td colSpan={7} style={{ textAlign: "center", color: "var(--fg-4)", padding: 24 }}>{t("common.loading")}</td></tr>
              ) : filtered.length === 0 ? (
                <tr><td colSpan={7} style={{ textAlign: "center", color: "var(--fg-4)", padding: 24 }}>{t("common.noData")}</td></tr>
              ) : (
                filtered.map((l) => (
                  <tr key={l.id} onClick={() => setDetail(l)} style={{ cursor: "pointer", borderLeft: l.success ? "2px solid transparent" : "2px solid var(--crit)" }}>
                    <td className="mono dim" style={{ fontSize: 11 }}>{fmtTime(l.timestamp)}</td>
                    <td><span className="badge mono">{l.commandType}</span></td>
                    <td className="mono" style={{ fontSize: 11.5 }}>{l.username}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{l.agentHostname || l.agentId || "—"}</td>
                    <td className="mono dim truncate" style={{ fontSize: 11, maxWidth: 320 }}>{l.target || l.params || "—"}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{l.ipAddress}</td>
                    <td style={{ textAlign: "right" }}><span className={`badge ${l.success ? "ok" : "crit"}`}>{l.success ? t("plat.ok") : t("plat.fail")}</span></td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {detail && (
        <Modal title={detail.commandType} subtitle={fmtTime(detail.timestamp)} onClose={() => setDetail(null)} footer={<button className="btn btn-sm" onClick={() => setDetail(null)}>{t("common.cancel")}</button>}>
          <div className="col gap-4">
            <div className="row gap-2">
              <span className={`badge ${detail.success ? "ok" : "crit"}`}>{detail.success ? t("plat.ok") : t("plat.fail")}</span>
              {detail.durationMs > 0 && <span className="badge mono">{detail.durationMs} ms</span>}
            </div>
            <div className="col gap-2">
              <div className="row" style={{ justifyContent: "space-between" }}><span className="muted" style={{ fontSize: 11.5 }}>{t("acc.user")}</span><span className="mono">{detail.username} <span className="dim">· {detail.ipAddress}</span></span></div>
              <div className="row" style={{ justifyContent: "space-between" }}><span className="muted" style={{ fontSize: 11.5 }}>{t("plat.relatedAgent")}</span><span className="mono">{detail.agentHostname || detail.agentId || "—"}</span></div>
            </div>
            {detail.params && <div className="col gap-1"><span className="upper" style={{ color: "var(--fg-4)" }}>{t("plat.params")}</span><div className="code" style={{ whiteSpace: "pre-wrap", wordBreak: "break-all" }}>{detail.params}</div></div>}
            {detail.error && <div className="col gap-1"><span className="upper" style={{ color: "var(--crit)" }}>Error</span><div className="code" style={{ whiteSpace: "pre-wrap", wordBreak: "break-all", color: "var(--crit)" }}>{detail.error}</div></div>}
          </div>
        </Modal>
      )}
    </div>
  )
}
