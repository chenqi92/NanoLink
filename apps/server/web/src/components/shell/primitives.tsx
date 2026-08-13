// primitives.tsx — small shared building blocks (Perm, Status, Meter, KPI, PageHeader, …)
import type { ReactNode } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { toneFor, type Tone, type AgentStatus } from "@/lib/format"
import { Sparkline } from "@/components/charts"

// ─── Permission badge ──────────────────────────────────────
export function Perm({ level }: { level?: number }) {
  const { t } = useTranslation()
  const lvl = level ?? 0
  return (
    <span className={`perm perm-${lvl}`}>
      L{lvl} · {t(`permission.l${lvl}`)}
    </span>
  )
}

// ─── Status badge (online / offline / connecting) ──────────
export function Status({ status }: { status: AgentStatus | "polling" }) {
  const { t } = useTranslation()
  const cls = status === "online" ? "ok" : status === "offline" ? "crit" : "warn"
  return (
    <span className="row gap-2" style={{ alignItems: "center" }}>
      <span className={`dot ${cls} ${status === "online" ? "pulse" : ""}`} />
      <span style={{ fontSize: 11.5, color: "var(--fg-3)", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>{t(`status.${status}`)}</span>
    </span>
  )
}

// ─── Usage meter ───────────────────────────────────────────
export function Meter({ value, max = 100, tone, thin, thick }: { value: number; max?: number; tone?: Tone; thin?: boolean; thick?: boolean }) {
  const pct = Math.max(0, Math.min(100, (value / max) * 100))
  const t = tone ?? toneFor(pct)
  return (
    <div className={`meter ${thin ? "thin" : ""} ${thick ? "thick" : ""}`}>
      <div className={`meter-fill ${t}`} style={{ width: `${pct}%` }} />
    </div>
  )
}

// ─── Key/value row ─────────────────────────────────────────
export function KVRow({ label, value, mono = true }: { label: ReactNode; value: ReactNode; mono?: boolean }) {
  return (
    <div className="row" style={{ justifyContent: "space-between", gap: 12 }}>
      <span style={{ color: "var(--fg-4)", fontSize: 11.5 }}>{label}</span>
      <span className={mono ? "mono num" : "num"} style={{ color: "var(--fg-2)", fontSize: 12, textAlign: "right" }}>
        {value}
      </span>
    </div>
  )
}

// ─── KPI tile ──────────────────────────────────────────────
export function KPI({
  label,
  value,
  sub,
  trend,
  spark,
  sparkLabels,
  sparkUnit = "%",
  tone = "",
  icon,
}: {
  label: string
  value: ReactNode
  sub?: ReactNode
  trend?: number
  spark?: number[]
  sparkLabels?: string[]
  sparkUnit?: string
  tone?: Tone
  icon?: ReactNode
}) {
  const valColor = tone === "crit" ? "var(--crit)" : tone === "warn" ? "var(--warn)" : "var(--fg)"
  const sparkColor = tone === "crit" ? "var(--crit)" : tone === "warn" ? "var(--warn)" : "var(--fg-2)"
  return (
    <div className="card" style={{ padding: 14, display: "flex", flexDirection: "column", gap: 8 }}>
      <div className="row gap-2" style={{ alignItems: "center", justifyContent: "space-between" }}>
        <div className="row gap-2" style={{ color: "var(--fg-4)", alignItems: "center", minWidth: 0, flex: 1 }}>
          {icon && <span style={{ display: "inline-flex", flexShrink: 0 }}>{icon}</span>}
          <span className="upper truncate">{label}</span>
        </div>
        {trend !== undefined && (
          <span className="row gap-1 mono num" style={{ fontSize: 10.5, color: trend > 0 ? "var(--warn)" : "var(--ok)" }}>
            {trend > 0 ? I.arrowUp({ size: 10 }) : I.arrowDown({ size: 10 })}
            {Math.abs(trend).toFixed(1)}%
          </span>
        )}
      </div>
      <div className="row gap-2" style={{ alignItems: "baseline" }}>
        <div className="num display" style={{ fontSize: 26, fontWeight: 500, letterSpacing: "-0.02em", color: valColor }}>
          {value}
        </div>
        {sub && <div className="num mono" style={{ fontSize: 11, color: "var(--fg-4)" }}>{sub}</div>}
      </div>
      {spark && (
        <div style={{ marginTop: 2, color: sparkColor }}>
          <Sparkline data={spark} h={28} label={label} unit={sparkUnit} pointLabels={sparkLabels} />
        </div>
      )}
    </div>
  )
}

// ─── Page header ───────────────────────────────────────────
export function PageHeader({ title, subtitle, actions, eyebrow }: { title: ReactNode; subtitle?: ReactNode; actions?: ReactNode; eyebrow?: ReactNode }) {
  return (
    <div className="page-header">
      <div className="page-header__copy">
        {eyebrow && <div className="upper" style={{ color: "var(--fg-4)", marginBottom: 4 }}>{eyebrow}</div>}
        <h1 className="display" style={{ margin: 0, fontSize: 22, fontWeight: 500, letterSpacing: "-0.02em" }}>{title}</h1>
        {subtitle && <div style={{ color: "var(--fg-3)", fontSize: 12.5, marginTop: 3 }}>{subtitle}</div>}
      </div>
      {actions && <div className="page-header__actions">{actions}</div>}
    </div>
  )
}

// ─── Section panel (card with titled header) ───────────────
export function SectionPanel({ icon, title, count, actions, children, bodyStyle }: { icon?: ReactNode; title: ReactNode; count?: ReactNode; actions?: ReactNode; children: ReactNode; bodyStyle?: React.CSSProperties }) {
  return (
    <div className="card" style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
      <div className="row gap-2" style={{ padding: "11px 14px", borderBottom: "1px solid var(--border)", justifyContent: "space-between" }}>
        <div className="row gap-2" style={{ alignItems: "center", color: "var(--fg-2)", minWidth: 0 }}>
          {icon && <span style={{ display: "inline-flex", color: "var(--fg-4)", flexShrink: 0 }}>{icon}</span>}
          <span style={{ fontSize: 12.5, fontWeight: 500 }}>{title}</span>
          {count !== undefined && <span className="mono num" style={{ fontSize: 11, color: "var(--fg-4)" }}>{count}</span>}
        </div>
        {actions && <div className="row gap-2">{actions}</div>}
      </div>
      <div style={{ padding: 14, ...bodyStyle }}>{children}</div>
    </div>
  )
}

// ─── Form block (label + control + hint) ───────────────────
export function FormBlock({ label, hint, children }: { label?: ReactNode; hint?: ReactNode; children: ReactNode }) {
  return (
    <div className="col" style={{ gap: 6 }}>
      {label && <div className="upper" style={{ color: "var(--fg-4)" }}>{label}</div>}
      {children}
      {hint && <div className="hint">{hint}</div>}
    </div>
  )
}

// ─── Empty state ───────────────────────────────────────────
export function EmptyState({ icon, title, desc, action }: { icon?: ReactNode; title: ReactNode; desc?: ReactNode; action?: ReactNode }) {
  return (
    <div className="card" style={{ padding: "48px 24px", display: "flex", flexDirection: "column", alignItems: "center", gap: 10, textAlign: "center" }}>
      {icon && <span style={{ color: "var(--fg-dim)" }}>{icon}</span>}
      <div style={{ fontSize: 14, fontWeight: 500 }}>{title}</div>
      {desc && <div className="muted" style={{ fontSize: 12.5, maxWidth: 380 }}>{desc}</div>}
      {action && <div style={{ marginTop: 6 }}>{action}</div>}
    </div>
  )
}
