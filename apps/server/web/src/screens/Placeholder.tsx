import type { ReactNode } from "react"
import { PageHeader } from "@/components/shell/primitives"
import { I } from "@/lib/icons"

export function Placeholder({ title, subtitle, note }: { title: ReactNode; subtitle?: ReactNode; note?: ReactNode }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", overflow: "auto" }}>
      <PageHeader title={title} subtitle={subtitle} />
      <div style={{ padding: "0 24px 24px" }}>
        <div className="card" style={{ padding: "48px 24px", display: "flex", flexDirection: "column", alignItems: "center", gap: 12, textAlign: "center", color: "var(--fg-4)" }}>
          <span style={{ color: "var(--fg-dim)" }}>{I.bolt({ size: 28 })}</span>
          <div style={{ fontSize: 13, color: "var(--fg-3)" }}>{note ?? "Under construction"}</div>
        </div>
      </div>
    </div>
  )
}
