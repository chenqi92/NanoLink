import { useState, useEffect } from "react"
import { useTranslation } from "react-i18next"
import { Plus, Pencil, Trash2, Users2, UserPlus, UserMinus, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { useAuth } from "@/hooks/use-auth"

interface Group {
  id: number
  name: string
  description: string
  users?: { id: number; username: string }[]
}

interface User {
  id: number
  username: string
}

export function GroupManagement() {
  const { t } = useTranslation()
  const { token } = useAuth()
  const [groups, setGroups] = useState<Group[]>([])
  const [allUsers, setAllUsers] = useState<User[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  
  // Modal states
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [editingGroup, setEditingGroup] = useState<Group | null>(null)
  const [managingMembers, setManagingMembers] = useState<Group | null>(null)
  
  // Form state
  const [formData, setFormData] = useState({ name: "", description: "" })

  useEffect(() => {
    fetchGroups()
    fetchUsers()
  }, [])

  const fetchGroups = async () => {
    try {
      const res = await fetch("/api/groups", {
        headers: { Authorization: `Bearer ${token}` }
      })
      if (!res.ok) throw new Error("Failed to fetch groups")
      const data = await res.json()
      setGroups(data)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error")
    } finally {
      setLoading(false)
    }
  }

  const fetchUsers = async () => {
    try {
      const res = await fetch("/api/users", {
        headers: { Authorization: `Bearer ${token}` }
      })
      if (res.ok) {
        const data = await res.json()
        setAllUsers(data)
      }
    } catch {
      // Users are optional
    }
  }

  const handleCreate = async () => {
    try {
      const res = await fetch("/api/groups", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`
        },
        body: JSON.stringify(formData)
      })
      if (!res.ok) {
        const err = await res.json()
        throw new Error(err.error || "Failed to create group")
      }
      setShowCreateModal(false)
      setFormData({ name: "", description: "" })
      fetchGroups()
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error")
    }
  }

  const handleUpdate = async () => {
    if (!editingGroup) return
    try {
      const res = await fetch(`/api/groups/${editingGroup.id}`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`
        },
        body: JSON.stringify(formData)
      })
      if (!res.ok) throw new Error("Failed to update group")
      setEditingGroup(null)
      fetchGroups()
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error")
    }
  }

  const handleDelete = async (group: Group) => {
    if (!confirm(`Delete group "${group.name}"?`)) return
    try {
      const res = await fetch(`/api/groups/${group.id}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` }
      })
      if (!res.ok) throw new Error("Failed to delete group")
      fetchGroups()
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error")
    }
  }

  const handleAddUser = async (userId: number) => {
    if (!managingMembers) return
    try {
      const res = await fetch(`/api/groups/${managingMembers.id}/users`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`
        },
        body: JSON.stringify({ userId })
      })
      if (!res.ok) throw new Error("Failed to add user")
      fetchGroups()
      // Refresh the managing group
      const updated = groups.find(g => g.id === managingMembers.id)
      if (updated) setManagingMembers(updated)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error")
    }
  }

  const handleRemoveUser = async (userId: number) => {
    if (!managingMembers) return
    try {
      const res = await fetch(`/api/groups/${managingMembers.id}/users/${userId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` }
      })
      if (!res.ok) throw new Error("Failed to remove user")
      fetchGroups()
      // Refresh the managing group
      const updated = groups.find(g => g.id === managingMembers.id)
      if (updated) setManagingMembers(updated)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error")
    }
  }

  const openEditModal = (group: Group) => {
    setEditingGroup(group)
    setFormData({ name: group.name, description: group.description || "" })
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

  // Get users not in the currently managed group
  const availableUsers = managingMembers
    ? allUsers.filter(u => !managingMembers.users?.some(gu => gu.id === u.id))
    : []

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="flex items-center gap-2">
          <Users2 className="h-5 w-5" />
          {t("admin.groupManagement")}
        </CardTitle>
        <Button onClick={() => setShowCreateModal(true)} size="sm">
          <Plus className="h-4 w-4 mr-1" />
          {t("admin.createGroup")}
        </Button>
      </CardHeader>
      <CardContent>
        {error && (
          <div className="mb-4 p-3 bg-red-500/10 border border-red-500/50 rounded text-red-500">
            {error}
          </div>
        )}
        
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {groups.map(group => (
            <div key={group.id} className="border border-[var(--color-border)] rounded-lg p-4">
              <div className="flex items-start justify-between mb-2">
                <div>
                  <h3 className="font-medium">{group.name}</h3>
                  {group.description && (
                    <p className="text-sm text-[var(--color-muted-foreground)]">{group.description}</p>
                  )}
                </div>
                <div className="flex gap-1">
                  <Button variant="ghost" size="sm" onClick={() => openEditModal(group)}>
                    <Pencil className="h-4 w-4" />
                  </Button>
                  <Button variant="ghost" size="sm" onClick={() => handleDelete(group)}>
                    <Trash2 className="h-4 w-4 text-red-500" />
                  </Button>
                </div>
              </div>
              
              <div className="flex items-center justify-between text-sm">
                <span className="text-[var(--color-muted-foreground)]">
                  {group.users?.length || 0} members
                </span>
                <Button variant="outline" size="sm" onClick={() => setManagingMembers(group)}>
                  <Users2 className="h-4 w-4 mr-1" />
                  Manage
                </Button>
              </div>
            </div>
          ))}
        </div>
        
        {groups.length === 0 && (
          <p className="text-center text-[var(--color-muted-foreground)] py-8">
            No groups yet. Create one to get started.
          </p>
        )}
      </CardContent>

      {/* Create Group Modal */}
      {showCreateModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-[var(--color-card)] rounded-lg p-6 w-full max-w-md mx-4">
            <h3 className="text-lg font-semibold mb-4">{t("admin.createGroup")}</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium mb-1">Name</label>
                <input
                  type="text"
                  value={formData.name}
                  onChange={e => setFormData(p => ({ ...p, name: e.target.value }))}
                  className="w-full px-3 py-2 border border-[var(--color-border)] rounded bg-[var(--color-background)]"
                />
              </div>
              <div>
                <label className="block text-sm font-medium mb-1">Description</label>
                <textarea
                  value={formData.description}
                  onChange={e => setFormData(p => ({ ...p, description: e.target.value }))}
                  className="w-full px-3 py-2 border border-[var(--color-border)] rounded bg-[var(--color-background)]"
                  rows={3}
                />
              </div>
            </div>
            <div className="flex justify-end gap-2 mt-6">
              <Button variant="outline" onClick={() => setShowCreateModal(false)}>Cancel</Button>
              <Button onClick={handleCreate}>Create</Button>
            </div>
          </div>
        </div>
      )}

      {/* Edit Group Modal */}
      {editingGroup && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-[var(--color-card)] rounded-lg p-6 w-full max-w-md mx-4">
            <h3 className="text-lg font-semibold mb-4">Edit Group</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium mb-1">Name</label>
                <input
                  type="text"
                  value={formData.name}
                  onChange={e => setFormData(p => ({ ...p, name: e.target.value }))}
                  className="w-full px-3 py-2 border border-[var(--color-border)] rounded bg-[var(--color-background)]"
                />
              </div>
              <div>
                <label className="block text-sm font-medium mb-1">Description</label>
                <textarea
                  value={formData.description}
                  onChange={e => setFormData(p => ({ ...p, description: e.target.value }))}
                  className="w-full px-3 py-2 border border-[var(--color-border)] rounded bg-[var(--color-background)]"
                  rows={3}
                />
              </div>
            </div>
            <div className="flex justify-end gap-2 mt-6">
              <Button variant="outline" onClick={() => setEditingGroup(null)}>Cancel</Button>
              <Button onClick={handleUpdate}>Save</Button>
            </div>
          </div>
        </div>
      )}

      {/* Manage Members Modal */}
      {managingMembers && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-[var(--color-card)] rounded-lg p-6 w-full max-w-lg mx-4">
            <h3 className="text-lg font-semibold mb-4">
              Members of "{managingMembers.name}"
            </h3>
            
            {/* Current members */}
            <div className="mb-4">
              <h4 className="text-sm font-medium mb-2">Current Members</h4>
              {managingMembers.users?.length ? (
                <div className="space-y-1">
                  {managingMembers.users.map(user => (
                    <div key={user.id} className="flex items-center justify-between p-2 bg-[var(--color-muted)] rounded">
                      <span>{user.username}</span>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => handleRemoveUser(user.id)}
                      >
                        <UserMinus className="h-4 w-4 text-red-500" />
                      </Button>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-[var(--color-muted-foreground)]">No members</p>
              )}
            </div>
            
            {/* Available users */}
            {availableUsers.length > 0 && (
              <div>
                <h4 className="text-sm font-medium mb-2">Add Members</h4>
                <div className="space-y-1 max-h-40 overflow-y-auto">
                  {availableUsers.map(user => (
                    <div key={user.id} className="flex items-center justify-between p-2 hover:bg-[var(--color-muted)] rounded">
                      <span>{user.username}</span>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => handleAddUser(user.id)}
                      >
                        <UserPlus className="h-4 w-4 text-green-500" />
                      </Button>
                    </div>
                  ))}
                </div>
              </div>
            )}
            
            <div className="flex justify-end mt-6">
              <Button onClick={() => setManagingMembers(null)}>Done</Button>
            </div>
          </div>
        </div>
      )}
    </Card>
  )
}
