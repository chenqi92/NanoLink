<script setup>
import { ref, onMounted } from 'vue'
import { useAuth } from '../composables/useAuth.js'

const emit = defineEmits(['back'])
const { authFetch } = useAuth()

const groups = ref([])
const loading = ref(true)
const error = ref(null)
const showCreateModal = ref(false)
const showEditModal = ref(false)
const showDeleteConfirm = ref(false)
const showAddUserModal = ref(false)
const selectedGroup = ref(null)
const formData = ref({ name: '', description: '' })
const allUsers = ref([])
const selectedUserId = ref(null)

async function fetchGroups() {
  loading.value = true
  try {
    const res = await authFetch('/groups')
    if (!res.ok) throw new Error('Failed to fetch groups')
    groups.value = await res.json()
    error.value = null
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function fetchUsers() {
  try {
    const res = await authFetch('/users')
    if (res.ok) {
      allUsers.value = await res.json()
    }
  } catch (e) {
    console.error('Failed to fetch users:', e)
  }
}

async function createGroup() {
  try {
    const res = await authFetch('/groups', {
      method: 'POST',
      body: JSON.stringify(formData.value),
    })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.error || 'Failed to create group')
    }
    const newGroup = await res.json()
    groups.value.push(newGroup)
    showCreateModal.value = false
    formData.value = { name: '', description: '' }
  } catch (e) {
    error.value = e.message
  }
}

async function updateGroup() {
  try {
    const res = await authFetch(`/groups/${selectedGroup.value.id}`, {
      method: 'PUT',
      body: JSON.stringify(formData.value),
    })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.error || 'Failed to update group')
    }
    const updated = await res.json()
    const idx = groups.value.findIndex(g => g.id === updated.id)
    if (idx !== -1) groups.value[idx] = { ...groups.value[idx], ...updated }
    showEditModal.value = false
    selectedGroup.value = null
  } catch (e) {
    error.value = e.message
  }
}

async function deleteGroup() {
  try {
    const res = await authFetch(`/groups/${selectedGroup.value.id}`, { method: 'DELETE' })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.error || 'Failed to delete group')
    }
    groups.value = groups.value.filter(g => g.id !== selectedGroup.value.id)
    showDeleteConfirm.value = false
    selectedGroup.value = null
  } catch (e) {
    error.value = e.message
  }
}

async function addUserToGroup() {
  if (!selectedUserId.value) return
  try {
    const res = await authFetch(`/groups/${selectedGroup.value.id}/users`, {
      method: 'POST',
      body: JSON.stringify({ userId: selectedUserId.value }),
    })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.error || 'Failed to add user to group')
    }
    await fetchGroups() // Refresh to get updated user count
    showAddUserModal.value = false
    selectedUserId.value = null
  } catch (e) {
    error.value = e.message
  }
}

async function removeUserFromGroup(groupId, userId) {
  try {
    const res = await authFetch(`/groups/${groupId}/users/${userId}`, { method: 'DELETE' })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.error || 'Failed to remove user')
    }
    await fetchGroups()
  } catch (e) {
    error.value = e.message
  }
}

function openEdit(group) {
  selectedGroup.value = group
  formData.value = { name: group.name, description: group.description }
  showEditModal.value = true
}

function openAddUser(group) {
  selectedGroup.value = group
  fetchUsers()
  showAddUserModal.value = true
}

onMounted(fetchGroups)
</script>

<template>
  <div>
    <!-- Header -->
    <div class="flex items-center justify-between mb-6">
      <div>
        <h2 class="text-xl font-semibold">Group Management</h2>
        <p class="text-sm text-gray-400 mt-1">Manage user groups and their members</p>
      </div>
      <div class="flex space-x-3">
        <button @click="showCreateModal = true" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg flex items-center">
          <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
          </svg>
          Create Group
        </button>
        <button @click="$emit('back')" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg">
          Back
        </button>
      </div>
    </div>

    <!-- Error Alert -->
    <div v-if="error" class="mb-4 bg-red-900/50 border border-red-700 rounded-lg p-3">
      <p class="text-red-300 text-sm">{{ error }}</p>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="flex items-center justify-center py-12">
      <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
    </div>

    <!-- Groups Grid -->
    <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      <div
        v-for="group in groups"
        :key="group.id"
        class="bg-gray-800 rounded-lg p-6 border border-gray-700"
      >
        <div class="flex items-start justify-between mb-4">
          <div>
            <h3 class="text-lg font-semibold text-white">{{ group.name }}</h3>
            <p class="text-sm text-gray-400 mt-1">{{ group.description || 'No description' }}</p>
          </div>
          <div class="flex space-x-2">
            <button @click="openEdit(group)" class="p-1 text-gray-400 hover:text-white">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
              </svg>
            </button>
            <button @click="selectedGroup = group; showDeleteConfirm = true" class="p-1 text-gray-400 hover:text-red-400">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
            </button>
          </div>
        </div>

        <div class="flex items-center justify-between text-sm">
          <span class="text-gray-400">{{ group.userCount || 0 }} members</span>
          <button @click="openAddUser(group)" class="text-blue-400 hover:text-blue-300">
            Add User
          </button>
        </div>

        <!-- Group Members -->
        <div v-if="group.users?.length" class="mt-4 pt-4 border-t border-gray-700">
          <div v-for="user in group.users" :key="user.id" class="flex items-center justify-between py-2">
            <div class="flex items-center">
              <div class="w-6 h-6 bg-gray-600 rounded-full flex items-center justify-center mr-2">
                <span class="text-xs text-white">{{ user.username?.charAt(0)?.toUpperCase() }}</span>
              </div>
              <span class="text-sm text-gray-300">{{ user.username }}</span>
            </div>
            <button @click="removeUserFromGroup(group.id, user.id)" class="text-gray-400 hover:text-red-400">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>
      </div>

      <!-- Empty State -->
      <div v-if="groups.length === 0" class="col-span-full bg-gray-800 rounded-lg p-12 text-center">
        <svg class="w-16 h-16 text-gray-600 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
        </svg>
        <p class="text-gray-400">No groups yet</p>
        <button @click="showCreateModal = true" class="mt-4 px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg">
          Create First Group
        </button>
      </div>
    </div>

    <!-- Create/Edit Modal -->
    <div v-if="showCreateModal || showEditModal" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div class="bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4 border border-gray-700">
        <h3 class="text-lg font-semibold text-white mb-4">
          {{ showEditModal ? 'Edit Group' : 'Create Group' }}
        </h3>
        <form @submit.prevent="showEditModal ? updateGroup() : createGroup()" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-300 mb-2">Name</label>
            <input
              v-model="formData.name"
              type="text"
              required
              class="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="Group name"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-300 mb-2">Description</label>
            <textarea
              v-model="formData.description"
              rows="3"
              class="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="Optional description"
            ></textarea>
          </div>
          <div class="flex justify-end space-x-3">
            <button
              type="button"
              @click="showCreateModal = false; showEditModal = false"
              class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg"
            >
              Cancel
            </button>
            <button type="submit" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg">
              {{ showEditModal ? 'Save' : 'Create' }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- Add User Modal -->
    <div v-if="showAddUserModal" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div class="bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4 border border-gray-700">
        <h3 class="text-lg font-semibold text-white mb-4">Add User to {{ selectedGroup?.name }}</h3>
        <div class="mb-4">
          <label class="block text-sm font-medium text-gray-300 mb-2">Select User</label>
          <select
            v-model="selectedUserId"
            class="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option :value="null">Select a user...</option>
            <option v-for="user in allUsers" :key="user.id" :value="user.id">
              {{ user.username }} {{ user.email ? `(${user.email})` : '' }}
            </option>
          </select>
        </div>
        <div class="flex justify-end space-x-3">
          <button @click="showAddUserModal = false" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg">
            Cancel
          </button>
          <button @click="addUserToGroup" :disabled="!selectedUserId" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:opacity-50 rounded-lg">
            Add
          </button>
        </div>
      </div>
    </div>

    <!-- Delete Confirmation -->
    <div v-if="showDeleteConfirm" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div class="bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4 border border-gray-700">
        <h3 class="text-lg font-semibold text-white mb-2">Delete Group</h3>
        <p class="text-gray-400 mb-6">
          Are you sure you want to delete <strong class="text-white">{{ selectedGroup?.name }}</strong>?
        </p>
        <div class="flex justify-end space-x-3">
          <button @click="showDeleteConfirm = false" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg">
            Cancel
          </button>
          <button @click="deleteGroup" class="px-4 py-2 bg-red-600 hover:bg-red-700 rounded-lg">
            Delete
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
