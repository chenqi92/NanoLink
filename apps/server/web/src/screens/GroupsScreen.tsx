import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { groupsApi, usersApi, type Group, type UserDetail } from "@/lib/api"
import { PageHeader, KVRow, FormBlock, EmptyState } from "@/components/shell/primitives"
import { Modal, ConfirmDialog } from "@/components/shell/Dialog"

function Avatar({ name, size = 18 }: { name: string; size?: number }) {
  return (
    <div style={{ width: size, height: size, borderRadius: "50%", background: "linear-gradient(135deg, var(--fg-2), var(--fg-4))", color: "var(--bg)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: size * 0.44, fontWeight: 700 }}>
      {(name || "?").slice(0, 2).toUpperCase()}
    </div>
  )
}

export function GroupsScreen() {
  const { t } = useTranslation()
  const [groups, setGroups] = useState<Group[]>([])
  const [users, setUsers] = useState<UserDetail[]>([])
  const [loading, setLoading] = useState(true)
  const [editing, setEditing] = useState<Group | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<Group | null>(null)
  const [managing, setManaging] = useState<Group | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [g, u] = await Promise.all([groupsApi.list(), usersApi.list().catch(() => [])])
      setGroups(g)
      setUsers(u)
    } finally { setLoading(false) }
  }, [])
  useEffect(() => { load() }, [load])

  const membersOf = (gid: number) => users.filter((u) => (u.groups ?? []).some((g) => g.id === gid))

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader title={t("nav.groups")} subtitle={t("acc.groupsSubtitle")} actions={<button className="btn btn-sm btn-primary" onClick={() => setCreating(true)}>{I.plus({ size: 13 })}<span>{t("acc.newGroup")}</span></button>} />
      <div style={{ padding: "0 24px 24px", overflow: "auto", flex: 1 }}>
        {loading && groups.length === 0 ? (
          <div style={{ padding: 40, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("common.loading")}</div>
        ) : groups.length === 0 ? (
          <EmptyState icon={I.group({ size: 28 })} title={t("nav.groups")} desc={t("acc.groupsSubtitle")} action={<button className="btn btn-sm btn-primary" onClick={() => setCreating(true)}>{I.plus({ size: 13 })}<span>{t("acc.newGroup")}</span></button>} />
        ) : (
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(340px, 1fr))", gap: 12 }}>
            {groups.map((g) => {
              const members = membersOf(g.id)
              const count = g.userCount ?? members.length
              return (
                <div key={g.id} className="card" style={{ padding: 16 }}>
                  <div className="row" style={{ justifyContent: "space-between", alignItems: "flex-start" }}>
                    <div className="col" style={{ gap: 4, minWidth: 0 }}>
                      <div className="row gap-2" style={{ alignItems: "center" }}>
                        {I.group({ size: 14 })}
                        <span className="mono" style={{ fontWeight: 500, fontSize: 14 }}>{g.name}</span>
                      </div>
                      {g.description && <div className="muted" style={{ fontSize: 11.5 }}>{g.description}</div>}
                    </div>
                  </div>
                  <div className="hr" />
                  <KVRow label={t("acc.members")} value={count} />
                  <div className="hr" />
                  <div className="col" style={{ gap: 6 }}>
                    <div className="upper" style={{ color: "var(--fg-4)" }}>{t("acc.memberPreview")}</div>
                    <div className="row gap-1" style={{ flexWrap: "wrap" }}>
                      {members.slice(0, 6).map((u) => (
                        <div key={u.id} title={u.username} className="row gap-1" style={{ padding: "3px 6px 3px 3px", background: "var(--panel-2)", borderRadius: 12, border: "1px solid var(--border)", alignItems: "center", fontSize: 11 }}>
                          <Avatar name={u.username} /><span className="mono">{u.username}</span>
                        </div>
                      ))}
                      {members.length === 0 && <span className="dim" style={{ fontSize: 11 }}>{t("common.noData")}</span>}
                      {count > 6 && <span className="badge mono">+{count - 6}</span>}
                    </div>
                  </div>
                  <div className="hr" />
                  <div className="row gap-2">
                    <button className="btn btn-sm" style={{ flex: 1 }} onClick={() => setManaging(g)}>{I.users({ size: 12 })}<span>{t("acc.manageMembers")}</span></button>
                    <button className="btn btn-sm btn-ghost btn-icon" onClick={() => setEditing(g)}>{I.edit({ size: 12 })}</button>
                    <button className="btn btn-sm btn-ghost btn-icon" onClick={() => setDeleting(g)}><span style={{ color: "var(--crit)" }}>{I.trash({ size: 12 })}</span></button>
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>

      {creating && <GroupEditor onClose={() => setCreating(false)} onDone={() => { setCreating(false); load() }} />}
      {editing && <GroupEditor group={editing} onClose={() => setEditing(null)} onDone={() => { setEditing(null); load() }} />}
      {deleting && <ConfirmDialog title={t("common.delete")} danger message={t("acc.deleteGroupConfirm", { name: deleting.name })} confirmLabel={t("common.delete")} onClose={() => setDeleting(null)} onConfirm={async () => { await groupsApi.delete(deleting.id); setDeleting(null); load() }} />}
      {managing && <MembersModal group={managing} users={users} memberIds={membersOf(managing.id).map((u) => u.id)} onClose={() => setManaging(null)} onChanged={load} />}
    </div>
  )
}

function GroupEditor({ group, onClose, onDone }: { group?: Group; onClose: () => void; onDone: () => void }) {
  const { t } = useTranslation()
  const [name, setName] = useState(group?.name ?? "")
  const [desc, setDesc] = useState(group?.description ?? "")
  const [busy, setBusy] = useState(false)
  async function submit() {
    setBusy(true)
    try {
      if (group) await groupsApi.update(group.id, { name, description: desc })
      else await groupsApi.create({ name, description: desc })
      onDone()
    } finally { setBusy(false) }
  }
  return (
    <Modal title={group ? t("common.edit") : t("acc.newGroup")} onClose={onClose} footer={<><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-sm btn-primary" onClick={submit} disabled={busy || !name.trim()}>{busy && <span className="dot pulse ok" />}{group ? t("common.save") : t("common.create")}</button></>}>
      <div className="col gap-4">
        <FormBlock label={t("acc.groupName")}><input className="input" value={name} onChange={(e) => setName(e.target.value)} autoFocus /></FormBlock>
        <FormBlock label={t("acc.description")}><input className="input" value={desc} onChange={(e) => setDesc(e.target.value)} /></FormBlock>
      </div>
    </Modal>
  )
}

function MembersModal({ group, users, memberIds, onClose, onChanged }: { group: Group; users: UserDetail[]; memberIds: number[]; onClose: () => void; onChanged: () => void }) {
  const { t } = useTranslation()
  const [ids, setIds] = useState<number[]>(memberIds)
  const [busy, setBusy] = useState(false)

  async function toggle(uid: number) {
    const isMember = ids.includes(uid)
    setBusy(true)
    try {
      if (isMember) { await groupsApi.removeUser(group.id, uid); setIds((s) => s.filter((x) => x !== uid)) }
      else { await groupsApi.addUser(group.id, uid); setIds((s) => [...s, uid]) }
      onChanged()
    } finally { setBusy(false) }
  }

  return (
    <Modal title={`${t("acc.manageMembers")} · ${group.name}`} onClose={onClose} footer={<button className="btn btn-sm btn-primary" onClick={onClose}>{t("common.confirm")}</button>}>
      <div className="col" style={{ gap: 4, maxHeight: 360, overflow: "auto" }}>
        {users.map((u) => {
          const member = ids.includes(u.id)
          return (
            <div key={u.id} className="row" style={{ justifyContent: "space-between", padding: "8px 10px", borderRadius: 4, background: member ? "var(--panel-2)" : "transparent" }}>
              <div className="row gap-2" style={{ alignItems: "center" }}><Avatar name={u.username} /><span className="mono" style={{ fontSize: 12 }}>{u.username}</span></div>
              <button className="btn btn-sm" disabled={busy} onClick={() => toggle(u.id)} style={member ? { background: "var(--accent)", color: "var(--accent-fg)", borderColor: "var(--accent)" } : {}}>
                {member ? <>{I.check({ size: 11 })}<span>{t("acc.members")}</span></> : <span>{I.plus({ size: 11 })}</span>}
              </button>
            </div>
          )
        })}
      </div>
    </Modal>
  )
}
