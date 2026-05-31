import { useMemo, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { PageHeader } from "@/components/shell/primitives"
import { SAMPLE_LOGS, type LogLine } from "@/lib/sampledata"

type Scope = "server" | "system" | "audit"

const LEVEL_COLOR: Record<string, string> = {
  info: "var(--fg-3)",
  warn: "var(--warn)",
  error: "var(--crit)",
  debug: "var(--fg-dim)",
}

function LogViewer({ lines }: { lines: LogLine[] }) {
  return (
    <div className="card" style={{ flex: 1, overflow: "auto", background: "var(--bg-2)", padding: "10px 12px", fontFamily: "var(--font-mono)", fontSize: 12, lineHeight: 1.6 }}>
      {lines.map((l, i) => (
        <div key={i} className="row gap-2" style={{ alignItems: "flex-start", whiteSpace: "pre-wrap", color: l.crit ? "var(--crit)" : "var(--fg-2)" }}>
          <span className="dim" style={{ flexShrink: 0 }}>{l.ts}</span>
          <span style={{ flexShrink: 0, width: 48, color: LEVEL_COLOR[l.level], textTransform: "uppercase", fontSize: 10.5, fontWeight: 600 }}>{l.level}</span>
          <span className="dim" style={{ flexShrink: 0, width: 96 }}>{l.src}</span>
          <span style={{ minWidth: 0 }}>{l.msg}</span>
        </div>
      ))}
    </div>
  )
}

export function LogsScreen() {
  const { t } = useTranslation()
  const [scope, setScope] = useState<Scope>("server")
  const [live, setLive] = useState(true)
  const [level, setLevel] = useState("all")
  const [source, setSource] = useState("all")
  const [q, setQ] = useState("")

  const sources = useMemo(() => Array.from(new Set(SAMPLE_LOGS.map((l) => l.src))), [])
  const filtered = SAMPLE_LOGS.filter((l) => {
    if (level !== "all" && l.level !== level) return false
    if (source !== "all" && l.src !== source) return false
    if (q && !l.msg.toLowerCase().includes(q.toLowerCase())) return false
    return true
  })

  const scopes: { k: Scope; label: string }[] = [
    { k: "server", label: t("dev.serverLogs") },
    { k: "system", label: t("dev.systemLogs") },
    { k: "audit", label: t("dev.auditLogs") },
  ]

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader
        title={t("nav.logs")}
        subtitle={t("dev.logsSubtitle")}
        actions={<button className="btn btn-sm">{I.external({ size: 13 })}<span>{t("dev.export")}</span></button>}
      />
      <div style={{ padding: "0 24px", borderBottom: "1px solid var(--border)" }}>
        <div className="tabs" style={{ borderBottom: "none", marginBottom: -1 }}>
          {scopes.map((s) => (
            <button key={s.k} className={`tab ${scope === s.k ? "active" : ""}`} onClick={() => setScope(s.k)}>{s.label}</button>
          ))}
        </div>
      </div>
      <div className="col" style={{ padding: "16px 24px 24px", flex: 1, overflow: "hidden", gap: 12 }}>
        <div className="row gap-2" style={{ padding: "8px 12px", borderRadius: 6, background: "rgba(96,165,250,.06)", border: "1px solid rgba(96,165,250,.25)", fontSize: 11.5, color: "var(--fg-3)" }}>
          <span style={{ color: "var(--info)" }}>{I.info({ size: 13 })}</span>
          <span>{t("dev.preview")}</span>
        </div>

        <div className="row gap-2" style={{ flexWrap: "wrap" }}>
          <button className="btn btn-sm" onClick={() => setLive(!live)}>
            <span className={`dot ${live ? "pulse ok" : "off"}`} />
            <span>{live ? t("dev.liveTail") : t("dev.paused")}</span>
          </button>
          <select className="select" style={{ width: "auto" }} value={level} onChange={(e) => setLevel(e.target.value)}>
            <option value="all">{t("dev.allLevels")}</option>
            {["info", "warn", "error", "debug"].map((l) => <option key={l} value={l}>{l}</option>)}
          </select>
          <select className="select" style={{ width: "auto" }} value={source} onChange={(e) => setSource(e.target.value)}>
            <option value="all">{t("dev.allSources")}</option>
            {sources.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
          <div className="row gap-2" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: "0 10px", height: 30, flex: 1, minWidth: 200 }}>
            {I.search({ size: 13 })}
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder={t("common.search")} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontFamily: "inherit", fontSize: 12 }} />
          </div>
          <span className="mono dim" style={{ fontSize: 11, alignSelf: "center" }}>{filtered.length} {t("dev.lines2")}</span>
        </div>

        <LogViewer lines={filtered} />
      </div>
    </div>
  )
}
