import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { agentTokensApi, type AgentToken } from "@/lib/api"
import { PageHeader, Perm, Status, FormBlock } from "@/components/shell/primitives"
import { Modal, ConfirmDialog } from "@/components/shell/Dialog"
import { timeAgo } from "@/lib/format"

function MiniStat({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="card" style={{ padding: "10px 14px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
      <div className="col" style={{ gap: 2 }}>
        <div className="upper" style={{ color: "var(--fg-4)" }}>{label}</div>
        <div className="num display" style={{ fontSize: 22, fontWeight: 500 }}>{value}</div>
      </div>
      <span style={{ width: 4, height: 28, background: color, borderRadius: 2 }} />
    </div>
  )
}

function PermSelect({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const { t } = useTranslation()
  return (
    <select className="select" value={value} onChange={(e) => onChange(Number(e.target.value))}>
      {[0, 1, 2, 3].map((l) => (
        <option key={l} value={l}>L{l} · {t(`permission.l${l}`)}</option>
      ))}
    </select>
  )
}

const PAGE_SIZE = 50

export function TokensScreen() {
  const { t } = useTranslation()
  const [items, setItems] = useState<AgentToken[]>([])
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [counts, setCounts] = useState({ online: 0, offline: 0, l3: 0 })
  const [dragId, setDragId] = useState<number | null>(null)
  const [editing, setEditing] = useState<AgentToken | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<AgentToken | null>(null)
  const [resetting, setResetting] = useState<AgentToken | null>(null)
  const [reveal, setReveal] = useState<{ token: string; name: string } | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const r = await agentTokensApi.list(page, PAGE_SIZE)
      setItems(r.items)
      setTotal(r.total)
      setCounts({ online: r.online, offline: r.total - r.online, l3: r.l3 })
    } catch {
      setItems([])
      setTotal(0)
      setCounts({ online: 0, offline: 0, l3: 0 })
    } finally {
      setLoading(false)
    }
  }, [page])

  useEffect(() => { load() }, [load])

  async function persistOrder(next: AgentToken[]) {
    setItems(next)
    try { await agentTokensApi.reorder(next.map((x) => x.id)) } catch { /* ignore */ }
  }

  const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE))

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader
        title={t("nav.tokens")}
        subtitle={t("acc.tokensSubtitle")}
        actions={
          <>
            <button className="btn btn-sm" onClick={load}>{I.refresh({ size: 13 })}<span>{t("acc.refresh")}</span></button>
            <button className="btn btn-sm btn-primary" onClick={() => setCreating(true)}>{I.plus({ size: 13 })}<span>{t("acc.createToken")}</span></button>
          </>
        }
      />
      <div style={{ padding: "0 24px 24px", overflow: "auto", flex: 1 }}>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12, marginBottom: 16 }}>
          <MiniStat label={t("acc.online")} value={counts.online} color="var(--ok)" />
          <MiniStat label={t("acc.offline")} value={counts.offline} color="var(--crit)" />
          <MiniStat label={t("nav.tokens")} value={total} color="var(--fg-3)" />
          <MiniStat label={t("acc.l3admin")} value={counts.l3} color="var(--crit)" />
        </div>

        <div className="card" style={{ overflow: "auto" }}>
          <table className="tbl" style={{ minWidth: 920 }}>
            <thead>
              <tr>
                <th style={{ width: 28 }}></th>
                <th>{t("acc.agentName")}</th>
                <th>{t("acc.status")}</th>
                <th>{t("acc.permission")}</th>
                <th>OS</th>
                <th>{t("acc.lastIp")}</th>
                <th>{t("acc.lastSeen")}</th>
                <th>{t("acc.version")}</th>
                <th style={{ textAlign: "right" }}>{t("acc.actions")}</th>
              </tr>
            </thead>
            <tbody>
              {loading && items.length === 0 ? (
                <tr><td colSpan={9} style={{ textAlign: "center", color: "var(--fg-4)", padding: 24 }}>{t("common.loading")}</td></tr>
              ) : items.length === 0 ? (
                <tr><td colSpan={9} style={{ textAlign: "center", color: "var(--fg-4)", padding: 24 }}>{t("common.noData")}</td></tr>
              ) : (
                items.map((tok) => (
                  <tr
                    key={tok.id}
                    draggable
                    onDragStart={() => setDragId(tok.id)}
                    onDragOver={(e) => e.preventDefault()}
                    onDrop={() => {
                      if (dragId == null || dragId === tok.id) return
                      const idxA = items.findIndex((x) => x.id === dragId)
                      const idxB = items.findIndex((x) => x.id === tok.id)
                      const next = [...items]
                      const [m] = next.splice(idxA, 1)
                      next.splice(idxB, 0, m)
                      persistOrder(next)
                      setDragId(null)
                    }}
                  >
                    <td><span style={{ color: "var(--fg-dim)", cursor: "grab" }}>{I.drag({ size: 14 })}</span></td>
                    <td>
                      <div className="col" style={{ gap: 2 }}>
                        <span className="mono" style={{ fontWeight: 500, whiteSpace: "nowrap" }}>{tok.name || tok.hostname || "—"}</span>
                        <span className="mono dim" style={{ fontSize: 10.5 }}>{tok.tokenHint}</span>
                      </div>
                    </td>
                    <td><Status status={tok.isOnline ? "online" : "offline"} /></td>
                    <td><Perm level={tok.permission} /></td>
                    <td className="muted" style={{ fontSize: 11.5 }}>{tok.os || "—"}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{tok.lastIp || "—"}</td>
                    <td className="mono num" style={{ fontSize: 11 }}>{tok.lastSeenAt ? timeAgo(Number(tok.lastSeenAt)) : "—"}</td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{tok.version ? `v${tok.version}` : "—"}</td>
                    <td style={{ textAlign: "right" }}>
                      <div className="row gap-1" style={{ justifyContent: "flex-end" }}>
                        <button className="btn btn-sm btn-ghost" onClick={() => setResetting(tok)}>
                          {I.refresh({ size: 12 })} <span>{t("acc.reset")}</span>
                        </button>
                        <button className="btn btn-sm btn-ghost btn-icon" onClick={() => setEditing(tok)}>{I.edit({ size: 12 })}</button>
                        <button className="btn btn-sm btn-ghost btn-icon" onClick={() => setDeleting(tok)}><span style={{ color: "var(--crit)" }}>{I.trash({ size: 12 })}</span></button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {pageCount > 1 && (
          <div className="row" style={{ justifyContent: "flex-end", alignItems: "center", gap: 8, marginTop: 12 }}>
            <button className="btn btn-sm btn-icon" disabled={page <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>‹</button>
            <span className="mono muted" style={{ fontSize: 12 }}>{page} / {pageCount}</span>
            <button className="btn btn-sm btn-icon" disabled={page >= pageCount} onClick={() => setPage((p) => Math.min(pageCount, p + 1))}>›</button>
          </div>
        )}
      </div>

      {creating && <TokenEditor onClose={() => setCreating(false)} onDone={(tokenStr, name) => { setCreating(false); if (tokenStr) setReveal({ token: tokenStr, name }); load() }} />}
      {editing && <TokenEditor token={editing} onClose={() => setEditing(null)} onDone={() => { setEditing(null); load() }} />}
      {deleting && (
        <ConfirmDialog
          title={t("common.delete")}
          danger
          message={t("acc.deleteTokenConfirm", { name: deleting.name || deleting.tokenHint })}
          confirmLabel={t("common.delete")}
          onClose={() => setDeleting(null)}
          onConfirm={async () => { await agentTokensApi.delete(deleting.id); setDeleting(null); load() }}
        />
      )}
      {resetting && (
        <ConfirmDialog
          title={<span className="row gap-2" style={{ alignItems: "center" }}>{I.refresh({ size: 14 })}<span>{t("acc.reset")} · {resetting.name || resetting.hostname || resetting.tokenHint}</span></span>}
          danger
          message={
            <div className="col gap-3">
              <span>{t("acc.regenWarn")}</span>
              <div className="code" style={{ fontSize: 11 }}>{`Agent:  ${resetting.name || resetting.hostname || "—"}\nStatus: ${resetting.isOnline ? "online" : "offline"}\nToken:  ${resetting.tokenHint}`}</div>
            </div>
          }
          confirmLabel={t("acc.reset")}
          onClose={() => setResetting(null)}
          onConfirm={async () => {
            const r = await agentTokensApi.regenerate(resetting.id)
            setReveal({ token: r.token, name: resetting.name || resetting.tokenHint })
            setResetting(null)
          }}
        />
      )}
      {reveal && (
        <Modal title={t("acc.newToken")} subtitle={t("acc.tokenOnce")} onClose={() => setReveal(null)} footer={<button className="btn btn-sm btn-primary" onClick={() => setReveal(null)}>{I.check({ size: 13 })}<span>{t("wizard.copied")}</span></button>}>
          <div className="col gap-3">
            <div className="code" style={{ wordBreak: "break-all", whiteSpace: "pre-wrap" }}>{reveal.token}</div>
            <button className="btn btn-sm" onClick={() => navigator.clipboard?.writeText(reveal.token)}>{I.copy({ size: 13 })}<span>{t("acc.copyToken")}</span></button>
            <div className="row gap-2" style={{ alignItems: "flex-start", color: "var(--fg-4)", fontSize: 11 }}>
              <span style={{ color: "var(--info)", flexShrink: 0 }}>{I.info({ size: 12 })}</span>
              <span className="mono">nano-agent token update {reveal.token.slice(0, 8)}…</span>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}

function TokenEditor({ token, onClose, onDone }: { token?: AgentToken; onClose: () => void; onDone: (tokenStr: string | null, name: string) => void }) {
  const { t } = useTranslation()
  const [name, setName] = useState(token?.name ?? "")
  const [perm, setPerm] = useState(token?.permission ?? 0)
  const [busy, setBusy] = useState(false)

  async function submit() {
    setBusy(true)
    try {
      if (token) {
        await agentTokensApi.update(token.id, { name, permission: perm })
        onDone(null, name)
      } else {
        const r = await agentTokensApi.create({ name, permission: perm })
        onDone(r.token, name)
      }
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      title={token ? t("common.edit") : t("acc.createToken")}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button>
          <button className="btn btn-sm btn-primary" onClick={submit} disabled={busy || !name.trim()}>{busy && <span className="dot pulse ok" />}{token ? t("common.save") : t("common.create")}</button>
        </>
      }
    >
      <div className="col gap-4">
        <FormBlock label={t("acc.tokenName")}>
          <input className="input" value={name} onChange={(e) => setName(e.target.value)} placeholder={t("acc.tokenNamePlaceholder")} autoFocus />
        </FormBlock>
        <FormBlock label={t("acc.permission")}>
          <PermSelect value={perm} onChange={setPerm} />
        </FormBlock>
      </div>
    </Modal>
  )
}
