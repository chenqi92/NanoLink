<script setup>
import { ref, onMounted } from 'vue'
import { useAuth } from '../composables/useAuth.js'

const emit = defineEmits(['back'])
const { authFetch } = useAuth()

const users = ref([])
const loading = ref(true)
const error = ref(null)
const showDeleteConfirm = ref(false)
const userToDelete = ref(null)

async function fetchUsers() {
  loading.value = true
  try {
    const res = await authFetch('/users')
    if (!res.ok) throw new Error('Failed to fetch users')
    users.value = await res.json()
    error.value = null
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function deleteUser(user) {
  try {
    const res = await authFetch(`/users/${user.id}`, { method: 'DELETE' })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.error || 'Failed to delete user')
    }
    users.value = users.value.filter(u => u.id !== user.id)
    showDeleteConfirm.value = false
    userToDelete.value = null
  } catch (e) {
    error.value = e.message
  }
}

function confirmDelete(user) {
  userToDelete.value = user
  showDeleteConfirm.value = true
}

onMounted(fetchUsers)
</script>

<template>
  <div>
    <!-- Header -->
    <div class="flex items-center justify-between mb-6">
      <div>
        <h2 class="text-xl font-semibold">User Management</h2>
        <p class="text-sm text-gray-400 mt-1">Manage system users and their access</p>
      </div>
      <button @click="$emit('back')" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg flex items-center">
        <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
        </svg>
        Back
      </button>
    </div>

    <!-- Error Alert -->
    <div v-if="error" class="mb-4 bg-red-900/50 border border-red-700 rounded-lg p-3">
      <p class="text-red-300 text-sm">{{ error }}</p>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="flex items-center justify-center py-12">
      <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
    </div>

    <!-- Users Table -->
    <div v-else class="bg-gray-800 rounded-lg overflow-hidden">
      <table class="w-full">
        <thead class="bg-gray-700">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">User</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Email</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Role</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Created</th>
            <th class="px-6 py-3 text-right text-xs font-medium text-gray-300 uppercase tracking-wider">Actions</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-700">
          <tr v-for="user in users" :key="user.id" class="hover:bg-gray-750">
            <td class="px-6 py-4 whitespace-nowrap">
              <div class="flex items-center">
                <div class="w-8 h-8 bg-blue-600 rounded-full flex items-center justify-center mr-3">
                  <span class="text-sm font-medium text-white">{{ user.username?.charAt(0)?.toUpperCase() }}</span>
                </div>
                <span class="text-sm font-medium text-white">{{ user.username }}</span>
              </div>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-300">
              {{ user.email || '-' }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap">
              <span
                :class="user.isSuperAdmin ? 'bg-purple-600 text-purple-100' : 'bg-gray-600 text-gray-100'"
                class="px-2 py-1 text-xs font-medium rounded"
              >
                {{ user.isSuperAdmin ? 'Super Admin' : 'User' }}
              </span>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
              {{ new Date(user.createdAt).toLocaleDateString() }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-right">
              <button
                v-if="!user.isSuperAdmin"
                @click="confirmDelete(user)"
                class="text-red-400 hover:text-red-300 text-sm"
              >
                Delete
              </button>
              <span v-else class="text-gray-500 text-sm">-</span>
            </td>
          </tr>
          <tr v-if="users.length === 0">
            <td colspan="5" class="px-6 py-8 text-center text-gray-400">
              No users found
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Delete Confirmation Modal -->
    <div v-if="showDeleteConfirm" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div class="bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4 border border-gray-700">
        <h3 class="text-lg font-semibold text-white mb-2">Delete User</h3>
        <p class="text-gray-400 mb-6">
          Are you sure you want to delete <strong class="text-white">{{ userToDelete?.username }}</strong>? 
          This action cannot be undone.
        </p>
        <div class="flex justify-end space-x-3">
          <button
            @click="showDeleteConfirm = false"
            class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg"
          >
            Cancel
          </button>
          <button
            @click="deleteUser(userToDelete)"
            class="px-4 py-2 bg-red-600 hover:bg-red-700 rounded-lg"
          >
            Delete
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
