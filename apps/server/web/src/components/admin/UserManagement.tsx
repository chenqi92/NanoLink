import { useState, useEffect } from "react"
import { useTranslation } from "react-i18next"
import { Plus, Pencil, Trash2, Key, Users, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { useAuth } from "@/hooks/use-auth"

interface User {
  id: number
  username: string
  email: string
  isSuperAdmin: boolean
  createdAt: string
  groups?: { id: number; name: string }[]
}

interface Group {
  id: number
  name: string
  description?: string
}

export function UserManagement() {
  const { t } = useTranslation()
  const { token } = useAuth()
  const [users, setUsers] = useState<User[]>([])
  const [groups, setGroups] = useState<Group[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  
  // Modal states
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [editingUser, setEditingUser] = useState<User | null>(null)
  const [changingPassword, setChangingPassword] = useState<User | null>(null)
  
  // Form states
  const [formData, setFormData] = useState({
    username: "",
    password: "",
    email: "",
    groupIds: [] as number[]
  })
  const [newPassword, setNewPassword] = useState("")

  useEffect(() => {
    fetchUsers()
    fetchGroups()
  }, [])

  const fetchUsers = async () => {
    try {
      const res = await fetch("/api/users", {
        headers: { Authorization: `Bearer ${token}` }
      })
      if (!res.ok) throw new Error("Failed to fetch users")
      const data = await res.json()
      setUsers(data)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error")
    } finally {
      setLoading(false)
    }
  }

  const fetchGroups = async () => {
    try {
      const res = await fetch("/api/groups", {
        headers: { Authorization: `Bearer ${token}` }
      })
      if (res.ok) {
        const data = await res.json()
        setGroups(data)
      }
    } catch {
      // Groups are optional
    }
  }

  const handleCreate = async () => {
    try {
      const res = await fetch("/api/users", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`
        },
        body: JSON.stringify(formData)
      })
      if (!res.ok) {
        const err = await res.json()
        throw new Error(err.error || "Failed to create user")
      }
      setShowCreateModal(false)
      setFormData({ username: "", password: "", email: "", groupIds: [] })
      fetchUsers()
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error")
    }
  }

  const handleUpdate = async () => {
    if (!editingUser) return
    try {
      const res = await fetch(`/api/users/${editingUser.id}`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`
        },
        body: JSON.stringify({
          email: formData.email,
          groupIds: formData.groupIds
        })
      })
      if (!res.ok) throw new Error("Failed to update user")
      setEditingUser(null)
      fetchUsers()
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error")
    }
  }

  const handleDelete = async (user: User) => {
    if (!confirm(`Delete user "${user.username}"?`)) return
    try {
      const res = await fetch(`/api/users/${user.id}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` }
      })
      if (!res.ok) throw new Error("Failed to delete user")
      fetchUsers()
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error")
    }
  }

  const handleChangePassword = async () => {
    if (!changingPassword) return
    try {
      const res = await fetch(`/api/users/${changingPassword.id}/password`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`
        },
        body: JSON.stringify({ newPassword, forceChange: true })
      })
      if (!res.ok) throw new Error("Failed to change password")
      setChangingPassword(null)
      setNewPassword("")
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error")
    }
  }

  const openEditModal = (user: User) => {
    setEditingUser(user)
    setFormData({
      username: user.username,
      password: "",
      email: user.email || "",
      groupIds: user.groups?.map(g => g.id) || []
    })
  }

  if (loading) {
    return (
      <Card>
        <CardContent className="flex items-center justify-center p-12">
          <Loader2 className="h-8 w-8 animate-spin" />
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="flex items-center gap-2">
          <Users className="h-5 w-5" />
          {t("admin.userManagement")}
        </CardTitle>
        <Button onClick={() => setShowCreateModal(true)} size="sm">
          <Plus className="h-4 w-4 mr-1" />
          {t("admin.createUser")}
        </Button>
      </CardHeader>
      <CardContent>
        {error && (
          <div className="mb-4 p-3 bg-red-500/10 border border-red-500/50 rounded text-red-500">
            {error}
          </div>
        )}
        
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[var(--color-border)]">
                <th className="text-left p-2">Username</th>
                <th className="text-left p-2">Email</th>
                <th className="text-left p-2">Role</th>
                <th className="text-left p-2">Groups</th>
                <th className="text-left p-2">Created</th>
                <th className="text-right p-2">Actions</th>
              </tr>
            </thead>
            <tbody>
              {users.map(user => (
                <tr key={user.id} className="border-b border-[var(--color-border)] hover:bg-[var(--color-muted)]">
                  <td className="p-2 font-medium">{user.username}</td>
                  <td className="p-2 text-[var(--color-muted-foreground)]">{user.email || "-"}</td>
                  <td className="p-2">
                    {user.isSuperAdmin ? (
                      <span className="px-2 py-0.5 bg-yellow-500/20 text-yellow-500 rounded text-xs">
                        SuperAdmin
                      </span>
                    ) : (
                      <span className="px-2 py-0.5 bg-blue-500/20 text-blue-500 rounded text-xs">
                        User
                      </span>
                    )}
                  </td>
                  <td className="p-2">
                    {user.groups?.map(g => (
                      <span key={g.id} className="mr-1 px-2 py-0.5 bg-gray-500/20 rounded text-xs">
                        {g.name}
                      </span>
                    )) || "-"}
                  </td>
                  <td className="p-2 text-[var(--color-muted-foreground)]">
                    {new Date(user.createdAt).toLocaleDateString()}
                  </td>
                  <td className="p-2 text-right">
                    <div className="flex justify-end gap-1">
                      <Button variant="ghost" size="sm" onClick={() => openEditModal(user)}>
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <Button variant="ghost" size="sm" onClick={() => setChangingPassword(user)}>
                        <Key className="h-4 w-4" />
                      </Button>
                      {!user.isSuperAdmin && (
                        <Button variant="ghost" size="sm" onClick={() => handleDelete(user)}>
                          <Trash2 className="h-4 w-4 text-red-500" />
                        </Button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </CardContent>

      {/* Create User Modal */}
      {showCreateModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-[var(--color-card)] rounded-lg p-6 w-full max-w-md mx-4">
            <h3 className="text-lg font-semibold mb-4">{t("admin.createUser")}</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium mb-1">Username</label>
                <input
                  type="text"
                  value={formData.username}
                  onChange={e => setFormData(p => ({ ...p, username: e.target.value }))}
                  className="w-full px-3 py-2 border border-[var(--color-border)] rounded bg-[var(--color-background)]"
                />
              </div>
              <div>
                <label className="block text-sm font-medium mb-1">Password</label>
                <input
                  type="password"
                  value={formData.password}
                  onChange={e => setFormData(p => ({ ...p, password: e.target.value }))}
                  className="w-full px-3 py-2 border border-[var(--color-border)] rounded bg-[var(--color-background)]"
                />
              </div>
              <div>
                <label className="block text-sm font-medium mb-1">Email (optional)</label>
                <input
                  type="email"
                  value={formData.email}
                  onChange={e => setFormData(p => ({ ...p, email: e.target.value }))}
                  className="w-full px-3 py-2 border border-[var(--color-border)] rounded bg-[var(--color-background)]"
                />
              </div>
              {groups.length > 0 && (
                <div>
                  <label className="block text-sm font-medium mb-1">Groups</label>
                  <div className="flex flex-wrap gap-2">
                    {groups.map(g => (
                      <label key={g.id} className="flex items-center gap-1 text-sm">
                        <input
                          type="checkbox"
                          checked={formData.groupIds.includes(g.id)}
                          onChange={e => {
                            if (e.target.checked) {
                              setFormData(p => ({ ...p, groupIds: [...p.groupIds, g.id] }))
                            } else {
                              setFormData(p => ({ ...p, groupIds: p.groupIds.filter(id => id !== g.id) }))
                            }
                          }}
                        />
                        {g.name}
                      </label>
                    ))}
                  </div>
                </div>
              )}
            </div>
            <div className="flex justify-end gap-2 mt-6">
              <Button variant="outline" onClick={() => setShowCreateModal(false)}>Cancel</Button>
              <Button onClick={handleCreate}>Create</Button>
            </div>
          </div>
        </div>
      )}

      {/* Edit User Modal */}
      {editingUser && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-[var(--color-card)] rounded-lg p-6 w-full max-w-md mx-4">
            <h3 className="text-lg font-semibold mb-4">Edit User: {editingUser.username}</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium mb-1">Email</label>
                <input
                  type="email"
                  value={formData.email}
                  onChange={e => setFormData(p => ({ ...p, email: e.target.value }))}
                  className="w-full px-3 py-2 border border-[var(--color-border)] rounded bg-[var(--color-background)]"
                />
              </div>
              {groups.length > 0 && (
                <div>
                  <label className="block text-sm font-medium mb-1">Groups</label>
                  <div className="flex flex-wrap gap-2">
                    {groups.map(g => (
                      <label key={g.id} className="flex items-center gap-1 text-sm">
                        <input
                          type="checkbox"
                          checked={formData.groupIds.includes(g.id)}
                          onChange={e => {
                            if (e.target.checked) {
                              setFormData(p => ({ ...p, groupIds: [...p.groupIds, g.id] }))
                            } else {
                              setFormData(p => ({ ...p, groupIds: p.groupIds.filter(id => id !== g.id) }))
                            }
                          }}
                        />
                        {g.name}
                      </label>
                    ))}
                  </div>
                </div>
              )}
            </div>
            <div className="flex justify-end gap-2 mt-6">
              <Button variant="outline" onClick={() => setEditingUser(null)}>Cancel</Button>
              <Button onClick={handleUpdate}>Save</Button>
            </div>
          </div>
        </div>
      )}

      {/* Change Password Modal */}
      {changingPassword && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-[var(--color-card)] rounded-lg p-6 w-full max-w-md mx-4">
            <h3 className="text-lg font-semibold mb-4">Change Password: {changingPassword.username}</h3>
            <div>
              <label className="block text-sm font-medium mb-1">New Password</label>
              <input
                type="password"
                value={newPassword}
                onChange={e => setNewPassword(e.target.value)}
                className="w-full px-3 py-2 border border-[var(--color-border)] rounded bg-[var(--color-background)]"
              />
            </div>
            <div className="flex justify-end gap-2 mt-6">
              <Button variant="outline" onClick={() => setChangingPassword(null)}>Cancel</Button>
              <Button onClick={handleChangePassword}>Change Password</Button>
            </div>
          </div>
        </div>
      )}
    </Card>
  )
}
