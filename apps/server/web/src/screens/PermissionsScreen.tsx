import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { usersApi, permissionsApi, groupsApi, auditApi, type UserDetail, type UserPermission, type Group, type GroupDetail, type AuditLog } from "@/lib/api"
import { useData } from "@/contexts/DataContext"
import { PageHeader, Perm } from "@/components/shell/primitives"
import { agentStatus } from "@/lib/format"
import { effectiveAgentPermission } from "@/lib/permissions"

type Mode = "matrix" | "byUser" | "byGroup" | "changes"

export function PermissionsScreen() {
  const { t } = useTranslation()
  const { agents } = useData()
  const [mode, setMode] = useState<Mode>("matrix")
  const [users, setUsers] = useState<UserDetail[]>([])
  const [permMap, setPermMap] = useState<Record<number, Record<string, number>>>({})
  const [loading, setLoading] = useState(true)
  const [selectedUser, setSelectedUser] = useState<number | null>(null)
  const [groups, setGroups] = useState<Group[]>([])
  const [selectedGroup, setSelectedGroup] = useState<number | null>(null)
  const [groupDetail, setGroupDetail] = useState<GroupDetail | null>(null)
  const [changes, setChanges] = useState<AuditLog[]>([])

  useEffect(() => {
    if (mode !== "changes") return
    Promise.all([
      auditApi.logs({ commandType: "PERMISSION_GRANT", limit: 50 }).then((r) => r.logs ?? []).catch(() => []),
      auditApi.logs({ commandType: "PERMISSION_REVOKE", limit: 50 }).then((r) => r.logs ?? []).catch(() => []),
    ]).then(([g, r]) => {
      const merged = [...g, ...r].sort((a, b) => {
        const ta = typeof a.timestamp === "string" ? Date.parse(a.timestamp) : Number(a.timestamp)
        const tb = typeof b.timestamp === "string" ? Date.parse(b.timestamp) : Number(b.timestamp)
        return tb - ta
      })
      setChanges(merged)
    })
  }, [mode])

  useEffect(() => { groupsApi.list().then(setGroups).catch(() => {}) }, [])
  useEffect(() => {
    if (selectedGroup == null) { setGroupDetail(null); return }
    let alive = true
    groupsApi.get(selectedGroup).then((d) => { if (alive) setGroupDetail(d) }).catch(() => { if (alive) setGroupDetail(null) })
    return () => { alive = false }
  }, [selectedGroup])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const u = await usersApi.list()
      setUsers(u)
      const entries = await Promise.all(
        u.map(async (usr) => {
          try {
            const perms = await permissionsApi.forUser(usr.id)
            const m: Record<string, number> = {}
            perms.forEach((p: UserPermission) => { m[p.agentId] = p.permissionLevel })
            return [usr.id, m] as const
          } catch {
            return [usr.id, {} as Record<string, number>] as const
          }
        })
      )
      setPermMap(Object.fromEntries(entries))
    } finally { setLoading(false) }
  }, [])
  useEffect(() => { load() }, [load])

  async function setPerm(userId: number, agentId: string, level: number | null) {
    setPermMap((prev) => {
      const next = { ...prev, [userId]: { ...(prev[userId] ?? {}) } }
      if (level == null) delete next[userId][agentId]
      else next[userId][agentId] = level
      return next
    })
    try {
      if (level == null) await permissionsApi.remove(userId, agentId)
      else await permissionsApi.set(userId, agentId, level)
    } catch { /* reload on error */ load() }
  }

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader
        title={t("nav.permissions")}
        subtitle={t("acc.permsSubtitle")}
        actions={
          <div className="row gap-2" style={{ alignItems: "center" }}>
            <div className="row gap-1">
              <button className="btn btn-sm" onClick={() => setMode("matrix")} style={mode === "matrix" ? { background: "var(--accent)", color: "var(--accent-fg)", borderColor: "var(--accent)" } : {}}>{t("acc.matrix")}</button>
              <button className="btn btn-sm" onClick={() => setMode("byUser")} style={mode === "byUser" ? { background: "var(--accent)", color: "var(--accent-fg)", borderColor: "var(--accent)" } : {}}>{t("acc.byUser")}</button>
              <button className="btn btn-sm" onClick={() => setMode("byGroup")} style={mode === "byGroup" ? { background: "var(--accent)", color: "var(--accent-fg)", borderColor: "var(--accent)" } : {}}>{t("acc.byGroup")}</button>
              <button className="btn btn-sm" onClick={() => setMode("changes")} style={mode === "changes" ? { background: "var(--accent)", color: "var(--accent-fg)", borderColor: "var(--accent)" } : {}}>{t("acc.changes")}</button>
            </div>
            <button className="btn btn-sm btn-primary" onClick={() => { setMode("byUser"); if (selectedUser == null && users[0]) setSelectedUser(users[0].id) }}>{I.plus({ size: 13 })}<span>{t("acc.grant")}</span></button>
          </div>
        }
      />
      <div style={{ padding: "0 24px 24px", overflow: "auto", flex: 1 }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("common.loading")}</div>
        ) : mode === "changes" ? (
          <div className="card" style={{ overflow: "auto" }}>
            <table className="tbl" style={{ minWidth: 640 }}>
              <thead><tr><th>{t("plat.time")}</th><th>{t("acc.user")}</th><th>{t("plat.command")}</th><th>{t("dev.agent")}</th><th>{t("admin.permissions")}</th></tr></thead>
              <tbody>
                {changes.length === 0 ? (
                  <tr><td colSpan={5} style={{ textAlign: "center", color: "var(--fg-4)", padding: 24 }}>{t("common.noData")}</td></tr>
                ) : (
                  changes.map((c) => {
                    let lvl: number | null = null
                    try { const p = c.params ? JSON.parse(c.params) : {}; lvl = p.level != null ? Number(p.level) : null } catch { /* ignore */ }
                    const revoke = c.commandType === "PERMISSION_REVOKE"
                    return (
                      <tr key={c.id}>
                        <td className="mono dim" style={{ fontSize: 11 }}>{new Date(typeof c.timestamp === "string" ? c.timestamp : Number(c.timestamp)).toLocaleString()}</td>
                        <td className="mono" style={{ fontSize: 11.5 }}>{c.username || "—"}</td>
                        <td><span className={`badge ${revoke ? "crit" : "ok"}`}>{revoke ? t("acc.revoked") : t("acc.granted")}</span></td>
                        <td className="mono dim" style={{ fontSize: 11 }}>{c.agentHostname || c.agentId || "—"}</td>
                        <td>{revoke || lvl == null ? <span className="dim">—</span> : <Perm level={lvl} />}</td>
                      </tr>
                    )
                  })
                )}
              </tbody>
            </table>
          </div>
        ) : mode === "byGroup" ? (
          <div className="row gap-4" style={{ alignItems: "flex-start" }}>
            <div className="card" style={{ width: 240, flexShrink: 0, overflow: "hidden" }}>
              {groups.length === 0 ? (
                <div className="muted" style={{ padding: 16, fontSize: 12 }}>{t("acc.noGroups")}</div>
              ) : (
                <div className="col">
                  {groups.map((g) => (
                    <button key={g.id} onClick={() => setSelectedGroup(g.id)} className="row gap-2" style={{ padding: "10px 12px", border: "none", background: selectedGroup === g.id ? "var(--panel-2)" : "transparent", cursor: "pointer", textAlign: "left", borderBottom: "1px solid var(--border)", color: "var(--fg-2)", fontFamily: "inherit", justifyContent: "space-between" }}>
                      <span className="row gap-2" style={{ alignItems: "center", minWidth: 0 }}>{I.group({ size: 12 })}<span className="truncate" style={{ fontSize: 12, fontWeight: selectedGroup === g.id ? 500 : 400 }}>{g.name}</span></span>
                      {g.userCount != null && <span className="mono num dim" style={{ fontSize: 11 }}>{g.userCount}</span>}
                    </button>
                  ))}
                </div>
              )}
            </div>
            <div className="flex-1">
              {selectedGroup == null ? (
                <div className="card" style={{ padding: "40px 24px", textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("acc.selectGroup")}</div>
              ) : (
                <div className="card" style={{ padding: 16 }}>
                  <div className="row gap-2" style={{ alignItems: "center", marginBottom: 12, flexWrap: "wrap" }}>
                    <span style={{ fontWeight: 500 }}>{groupDetail?.name ?? "—"}</span>
                    {groupDetail?.perm != null && <Perm level={groupDetail.perm} />}
                    {groupDetail?.description && <span className="muted" style={{ fontSize: 11.5 }}>{groupDetail.description}</span>}
                  </div>
                  <div className="upper" style={{ color: "var(--fg-4)", marginBottom: 8 }}>{t("acc.members")}</div>
                  <div className="col" style={{ gap: 6 }}>
                    {(groupDetail?.users ?? []).length === 0 ? (
                      <div className="muted" style={{ fontSize: 12 }}>{t("common.noData")}</div>
                    ) : (
                      (groupDetail?.users ?? []).map((u) => (
                        <div key={u.id} className="row" style={{ alignItems: "center", justifyContent: "space-between", padding: "8px 10px", background: "var(--panel-2)", borderRadius: 4 }}>
                          <span className="row gap-2" style={{ alignItems: "center" }}><span className="mono" style={{ fontSize: 12, fontWeight: 500 }}>{u.username}</span>{u.isSuperAdmin && <span className="badge" style={{ color: "var(--crit)", borderColor: "rgba(239,68,68,.3)" }}>{I.shield({ size: 10 })}</span>}</span>
                          <button className="btn btn-sm btn-ghost" onClick={() => { setMode("byUser"); setSelectedUser(u.id) }}>{t("acc.byUser")}</button>
                        </div>
                      ))
                    )}
                  </div>
                  <div className="hr" />
                  <div className="upper" style={{ color: "var(--fg-4)", marginBottom: 8 }}>{t("acc.authorizedAgents")}</div>
                  <div className="col" style={{ gap: 6 }}>
                    {(groupDetail?.agents ?? []).length === 0 ? (
                      <div className="muted" style={{ fontSize: 12 }}>{t("acc.noAgentsGranted")}</div>
                    ) : (
                      (groupDetail?.agents ?? []).map((grant) => {
                        const agent = agents.find((item) => item.id === grant.agentId)
                        const effective = Math.min(grant.permissionLevel, agent?.permissionLevel ?? grant.permissionLevel)
                        return (
                          <div key={grant.agentId} className="row" style={{ alignItems: "center", justifyContent: "space-between", padding: "8px 10px", background: "var(--panel-2)", borderRadius: 4 }}>
                            <span className="row gap-2" style={{ alignItems: "center", minWidth: 0 }}>
                              <span className={`dot ${agent ? "ok" : "crit"}`} />
                              <span className="mono truncate" style={{ fontSize: 12 }}>{agent?.hostname ?? grant.agentId}</span>
                            </span>
                            <Perm level={effective} />
                          </div>
                        )
                      })
                    )}
                  </div>
                </div>
              )}
            </div>
          </div>
        ) : mode === "matrix" ? (
          <div className="card" style={{ overflow: "auto" }}>
            <table className="tbl" style={{ minWidth: 200 + agents.length * 70 }}>
              <thead>
                <tr>
                  <th style={{ position: "sticky", left: 0, zIndex: 2 }}>{t("acc.user")}</th>
                  {agents.map((a) => (
                    <th key={a.id} style={{ textAlign: "center", whiteSpace: "nowrap" }}>
                      <span className="row gap-1" style={{ justifyContent: "center", alignItems: "center" }}>
                        <span className={`dot ${agentStatus(a.lastHeartbeat) === "online" ? "ok" : "crit"}`} />
                        <span className="mono" style={{ textTransform: "none", letterSpacing: 0 }}>{a.hostname}</span>
                      </span>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {users.map((u) => (
                  <tr key={u.id}>
                    <td style={{ position: "sticky", left: 0, background: "var(--panel)", zIndex: 1 }}>
                      <span className="row gap-2" style={{ alignItems: "center" }}>
                        <span className="mono" style={{ fontWeight: 500 }}>{u.username}</span>
                        {u.isSuperAdmin && <span className="badge" style={{ color: "var(--crit)", borderColor: "rgba(239,68,68,.3)" }}>{I.shield({ size: 10 })}</span>}
                      </span>
                    </td>
                    {agents.map((a) => {
                      const lvl = effectiveAgentPermission(u, a, permMap[u.id]?.[a.id], groups)
                      return (
                        <td key={a.id} style={{ textAlign: "center" }}>
                          {lvl != null ? <span className={`perm perm-${lvl}`}>L{lvl}</span> : <span className="dim">{t("acc.noOverride")}</span>}
                        </td>
                      )
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="row gap-4" style={{ alignItems: "flex-start" }}>
            <div className="card" style={{ width: 240, flexShrink: 0, overflow: "hidden" }}>
              <div className="col">
                {users.map((u) => (
                  <button key={u.id} onClick={() => setSelectedUser(u.id)} className="row gap-2" style={{ padding: "10px 12px", border: "none", background: selectedUser === u.id ? "var(--panel-2)" : "transparent", cursor: "pointer", textAlign: "left", borderBottom: "1px solid var(--border)", color: "var(--fg-2)", fontFamily: "inherit" }}>
                    <span className="mono" style={{ fontSize: 12, fontWeight: selectedUser === u.id ? 500 : 400 }}>{u.username}</span>
                    {u.isSuperAdmin && <span className="badge" style={{ color: "var(--crit)", borderColor: "rgba(239,68,68,.3)" }}>{I.shield({ size: 10 })}</span>}
                  </button>
                ))}
              </div>
            </div>
            <div className="flex-1">
              {selectedUser == null ? (
                <div className="card" style={{ padding: "40px 24px", textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("acc.selectUser")}</div>
              ) : (
                <div className="card" style={{ padding: 16 }}>
                  <div className="col" style={{ gap: 6 }}>
                    {agents.map((a) => {
                      const lvl = permMap[selectedUser]?.[a.id]
                      const selected = users.find((x) => x.id === selectedUser)
                      const su = selected?.isSuperAdmin
                      const effective = selected ? effectiveAgentPermission(selected, a, lvl, groups) : undefined
                      return (
                        <div key={a.id} className="row" style={{ alignItems: "center", justifyContent: "space-between", padding: "8px 10px", background: "var(--panel-2)", borderRadius: 4 }}>
                          <span className="mono truncate" style={{ fontSize: 12 }}>{a.hostname}</span>
                          <div className="row gap-1">
                            {su ? <span className={`perm perm-${a.permissionLevel}`}>L{a.permissionLevel} · {t("acc.roleSuper")}</span> : <>
                              {effective != null && effective !== lvl && <span className={`perm perm-${effective}`} title={t("acc.inheritedPermission")}>L{effective}</span>}
                              {[0, 1, 2, 3].map((l) => (
                                <button key={l} className="btn btn-sm" disabled={l > a.permissionLevel} title={l > a.permissionLevel ? t("acc.agentPermissionCeiling", { level: a.permissionLevel }) : undefined} onClick={() => setPerm(selectedUser, a.id, lvl === l ? null : l)} style={{ height: 22, padding: "0 8px", fontFamily: "var(--font-mono)", fontSize: 11, background: lvl === l ? "var(--panel)" : "transparent", border: lvl === l ? "1px solid var(--border-strong)" : "1px solid transparent", color: lvl === l ? "var(--fg)" : "var(--fg-4)" }}>L{l}</button>
                              ))}
                            </>}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
