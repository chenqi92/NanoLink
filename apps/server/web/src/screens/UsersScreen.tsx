import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { usersApi, groupsApi, permissionsApi, type UserDetail, type Group, type UserPermission } from "@/lib/api"
import { useData } from "@/contexts/DataContext"
import { PageHeader, FormBlock } from "@/components/shell/primitives"
import { Modal, ConfirmDialog } from "@/components/shell/Dialog"

function Avatar({ name, size = 26 }: { name: string; size?: number }) {
  return (
    <div style={{ width: size, height: size, borderRadius: "50%", background: "linear-gradient(135deg, var(--fg-2), var(--fg-4))", color: "var(--bg)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: size * 0.38, fontWeight: 700, flexShrink: 0 }}>
      {(name || "?").slice(0, 2).toUpperCase()}
    </div>
  )
}

export function UsersScreen() {
  const { t } = useTranslation()
  const [users, setUsers] = useState<UserDetail[]>([])
  const [groups, setGroups] = useState<Group[]>([])
  const [loading, setLoading] = useState(true)
  const [drawer, setDrawer] = useState<UserDetail | null>(null)
  const [adding, setAdding] = useState(false)
  const [deleting, setDeleting] = useState<UserDetail | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [u, g] = await Promise.all([usersApi.list(), groupsApi.list().catch(() => [])])
      setUsers(u)
      setGroups(g)
    } finally { setLoading(false) }
  }, [])
  useEffect(() => { load() }, [load])

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader
        title={t("nav.users")}
        subtitle={t("acc.usersSubtitle")}
        actions={<button className="btn btn-sm btn-primary" onClick={() => setAdding(true)}>{I.plus({ size: 13 })}<span>{t("acc.addUser")}</span></button>}
      />
      <div style={{ padding: "0 24px 24px", overflow: "auto", flex: 1 }}>
        <div className="card" style={{ overflow: "hidden" }}>
          <table className="tbl">
            <thead>
              <tr>
                <th>{t("acc.user")}</th>
                <th>{t("acc.email")}</th>
                <th>{t("acc.role")}</th>
                <th>{t("acc.groups")}</th>
                <th>{t("acc.created")}</th>
                <th style={{ textAlign: "right" }}>{t("acc.actions")}</th>
              </tr>
            </thead>
            <tbody>
              {loading && users.length === 0 ? (
                <tr><td colSpan={6} style={{ textAlign: "center", color: "var(--fg-4)", padding: 24 }}>{t("common.loading")}</td></tr>
              ) : (
                users.map((u) => (
                  <tr key={u.id} onClick={() => setDrawer(u)} style={{ cursor: "pointer" }}>
                    <td><div className="row gap-2" style={{ alignItems: "center" }}><Avatar name={u.username} /><span className="mono" style={{ fontWeight: 500 }}>{u.username}</span></div></td>
                    <td className="mono dim" style={{ fontSize: 11.5 }}>{u.email || "—"}</td>
                    <td>
                      {u.isSuperAdmin ? (
                        <span className="badge" style={{ color: "var(--crit)", borderColor: "rgba(239,68,68,.3)", background: "rgba(239,68,68,.06)" }}>{I.shield({ size: 11 })} {t("acc.roleSuper")}</span>
                      ) : (
                        <span className="badge">{t("acc.roleUser")}</span>
                      )}
                    </td>
                    <td><div className="row gap-1" style={{ flexWrap: "wrap" }}>{(u.groups ?? []).map((g) => <span key={g.id} className="badge mono" style={{ fontSize: 10 }}>{g.name}</span>)}</div></td>
                    <td className="mono dim" style={{ fontSize: 11 }}>{u.createdAt ? new Date(u.createdAt).toLocaleDateString() : "—"}</td>
                    <td style={{ textAlign: "right" }} onClick={(e) => e.stopPropagation()}>
                      <div className="row gap-1" style={{ justifyContent: "flex-end" }}>
                        <button className="btn btn-sm btn-ghost" onClick={() => setDrawer(u)}>{I.edit({ size: 12 })}<span>{t("common.edit")}</span></button>
                        <button className="btn btn-sm btn-ghost btn-icon" disabled={u.isSuperAdmin} onClick={() => setDeleting(u)}><span style={{ color: u.isSuperAdmin ? "var(--fg-dim)" : "var(--crit)" }}>{I.trash({ size: 12 })}</span></button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {drawer && <UserDrawer user={drawer} groups={groups} onClose={() => setDrawer(null)} onSaved={() => { setDrawer(null); load() }} />}
      {adding && <AddUserModal groups={groups} onClose={() => setAdding(false)} onDone={() => { setAdding(false); load() }} />}
      {deleting && (
        <ConfirmDialog title={t("common.delete")} danger message={t("acc.deleteUserConfirm", { name: deleting.username })} confirmLabel={t("common.delete")} onClose={() => setDeleting(null)} onConfirm={async () => { await usersApi.delete(deleting.id); setDeleting(null); load() }} />
      )}
    </div>
  )
}

function UserDrawer({ user, groups, onClose, onSaved }: { user: UserDetail; groups: Group[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation()
  const { agents } = useData()
  const [memberIds, setMemberIds] = useState<number[]>((user.groups ?? []).map((g) => g.id))
  const [email, setEmail] = useState(user.email ?? "")
  const [pwd, setPwd] = useState("")
  const [perms, setPerms] = useState<UserPermission[]>([])
  const [busy, setBusy] = useState(false)

  useEffect(() => { permissionsApi.forUser(user.id).then(setPerms).catch(() => setPerms([])) }, [user.id])

  function permFor(agentId: string): number | null {
    const p = perms.find((x) => x.agentId === agentId)
    return p ? p.permissionLevel : null
  }
  async function setPerm(agentId: string, level: number | null) {
    if (level == null) { await permissionsApi.remove(user.id, agentId).catch(() => {}); setPerms((p) => p.filter((x) => x.agentId !== agentId)) }
    else { await permissionsApi.set(user.id, agentId, level).catch(() => {}); setPerms((p) => [...p.filter((x) => x.agentId !== agentId), { agentId, permissionLevel: level }]) }
  }

  async function save() {
    setBusy(true)
    try {
      await usersApi.update(user.id, { email, groupIds: memberIds })
      if (pwd) await usersApi.setPassword(user.id, { newPassword: pwd })
      onSaved()
    } finally { setBusy(false) }
  }

  return (
    <div className="scrim" onClick={onClose} style={{ justifyContent: "flex-end", padding: 0, alignItems: "stretch" }}>
      <div className="dialog" style={{ width: 480, maxWidth: "100%", height: "100%", maxHeight: "100%", borderRadius: 0 }} onClick={(e) => e.stopPropagation()}>
        <div className="dialog-hd">
          <div className="row gap-3" style={{ alignItems: "center" }}>
            <Avatar name={user.username} size={36} />
            <div className="col" style={{ gap: 2 }}>
              <div className="mono" style={{ fontSize: 15, fontWeight: 500 }}>{user.username}</div>
              <div className="dim mono" style={{ fontSize: 11 }}>{user.email || "—"}</div>
            </div>
          </div>
          <button className="btn btn-ghost btn-icon btn-sm" onClick={onClose}>{I.x({ size: 14 })}</button>
        </div>
        <div className="dialog-bd" style={{ flex: 1 }}>
          <div className="col" style={{ gap: 18 }}>
            <FormBlock label={t("acc.role")}>
              <span className="badge" style={user.isSuperAdmin ? { color: "var(--crit)", borderColor: "rgba(239,68,68,.3)" } : {}}>{user.isSuperAdmin ? t("acc.roleSuper") : t("acc.roleUser")}</span>
            </FormBlock>
            <FormBlock label={t("acc.email")}>
              <input className="input" value={email} onChange={(e) => setEmail(e.target.value)} type="email" />
            </FormBlock>
            <FormBlock label={t("acc.membership")}>
              <div className="row gap-1" style={{ flexWrap: "wrap" }}>
                {groups.map((g) => {
                  const member = memberIds.includes(g.id)
                  return (
                    <button key={g.id} className="btn btn-sm" onClick={() => setMemberIds((ids) => (member ? ids.filter((x) => x !== g.id) : [...ids, g.id]))}
                      style={{ background: member ? "var(--accent)" : "var(--panel-2)", color: member ? "var(--accent-fg)" : "var(--fg-3)", borderColor: member ? "var(--accent)" : "var(--border-2)" }}>
                      {member && I.check({ size: 11 })}<span className="mono">{g.name}</span>
                    </button>
                  )
                })}
                {groups.length === 0 && <span className="dim" style={{ fontSize: 11.5 }}>{t("common.noData")}</span>}
              </div>
            </FormBlock>
            <FormBlock label={t("acc.perAgent")}>
              <div className="col" style={{ gap: 6 }}>
                {agents.slice(0, 12).map((a) => {
                  const lvl = permFor(a.id)
                  return (
                    <div key={a.id} className="row" style={{ alignItems: "center", justifyContent: "space-between", padding: "6px 10px", background: "var(--panel-2)", borderRadius: 4 }}>
                      <span className="mono truncate" style={{ fontSize: 12 }}>{a.hostname}</span>
                      <div className="row gap-1">
                        {[0, 1, 2, 3].map((l) => (
                          <button key={l} className="btn btn-sm" onClick={() => setPerm(a.id, lvl === l ? null : l)}
                            style={{ height: 22, padding: "0 8px", fontFamily: "var(--font-mono)", fontSize: 11, background: lvl === l ? "var(--panel)" : "transparent", border: lvl === l ? "1px solid var(--border-strong)" : "1px solid transparent", color: lvl === l ? "var(--fg)" : "var(--fg-4)" }}>L{l}</button>
                        ))}
                      </div>
                    </div>
                  )
                })}
                {agents.length === 0 && <span className="dim" style={{ fontSize: 11.5 }}>{t("common.noData")}</span>}
              </div>
            </FormBlock>
            <FormBlock label={t("acc.password")}>
              <input className="input" value={pwd} onChange={(e) => setPwd(e.target.value)} placeholder={t("acc.newPassword")} type="password" autoComplete="new-password" />
            </FormBlock>
          </div>
        </div>
        <div className="dialog-ft">
          <button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button>
          <button className="btn btn-sm btn-primary" onClick={save} disabled={busy}>{busy && <span className="dot pulse ok" />}{t("acc.save")}</button>
        </div>
      </div>
    </div>
  )
}

function AddUserModal({ groups, onClose, onDone }: { groups: Group[]; onClose: () => void; onDone: () => void }) {
  const { t } = useTranslation()
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [email, setEmail] = useState("")
  const [memberIds, setMemberIds] = useState<number[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit() {
    setBusy(true)
    setError(null)
    try {
      await usersApi.create({ username, password, email: email || undefined, groupIds: memberIds })
      onDone()
    } catch (e) {
      setError(typeof e === "object" && e && "error" in e ? String((e as { error: unknown }).error) : t("common.error"))
    } finally { setBusy(false) }
  }

  return (
    <Modal title={t("acc.addUser")} onClose={onClose} footer={<><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-sm btn-primary" onClick={submit} disabled={busy || !username || !password}>{busy && <span className="dot pulse ok" />}{t("common.create")}</button></>}>
      <div className="col gap-4">
        <FormBlock label={t("acc.username")}><input className="input" value={username} onChange={(e) => setUsername(e.target.value)} autoFocus /></FormBlock>
        <FormBlock label={t("acc.password")}><input className="input" value={password} onChange={(e) => setPassword(e.target.value)} type="password" autoComplete="new-password" /></FormBlock>
        <FormBlock label={t("acc.email")}><input className="input" value={email} onChange={(e) => setEmail(e.target.value)} type="email" /></FormBlock>
        <FormBlock label={t("acc.membership")}>
          <div className="row gap-1" style={{ flexWrap: "wrap" }}>
            {groups.map((g) => {
              const member = memberIds.includes(g.id)
              return (
                <button key={g.id} className="btn btn-sm" onClick={() => setMemberIds((ids) => (member ? ids.filter((x) => x !== g.id) : [...ids, g.id]))}
                  style={{ background: member ? "var(--accent)" : "var(--panel-2)", color: member ? "var(--accent-fg)" : "var(--fg-3)", borderColor: member ? "var(--accent)" : "var(--border-2)" }}>
                  {member && I.check({ size: 11 })}<span className="mono">{g.name}</span>
                </button>
              )
            })}
          </div>
        </FormBlock>
        {error && <div className="badge crit" style={{ height: "auto", padding: "8px 10px" }}>{error}</div>}
      </div>
    </Modal>
  )
}
