<script setup>
import { ref, onMounted, computed } from 'vue'
import { useAuth } from '../composables/useAuth.js'

const emit = defineEmits(['back'])
const { authFetch } = useAuth()

const loading = ref(true)
const error = ref(null)
const agents = ref([])
const groups = ref([])
const users = ref([])
const selectedAgent = ref(null)
const agentGroups = ref([])
const showAssignGroupModal = ref(false)
const showAssignUserModal = ref(false)
const assignForm = ref({ groupId: null, permissionLevel: 0 })
const userAssignForm = ref({ userId: null, permissionLevel: 0 })

const permissionLevels = [
  { value: 0, name: 'READ_ONLY', description: 'View monitoring data, logs' },
  { value: 1, name: 'BASIC_WRITE', description: 'Download logs, clean temp files' },
  { value: 2, name: 'SERVICE_CONTROL', description: 'Restart services, Docker' },
  { value: 3, name: 'SYSTEM_ADMIN', description: 'Reboot server, shell commands' },
]

async function fetchData() {
  loading.value = true
  try {
    const [agentsRes, groupsRes, usersRes] = await Promise.all([
      authFetch('/agents'),
      authFetch('/groups'),
      authFetch('/users'),
    ])
    if (agentsRes.ok) agents.value = await agentsRes.json()
    if (groupsRes.ok) groups.value = await groupsRes.json()
    if (usersRes.ok) users.value = await usersRes.json()
    error.value = null
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function selectAgent(agent) {
  selectedAgent.value = agent
  try {
    const res = await authFetch(`/agents/${agent.id}/groups`)
    if (res.ok) {
      agentGroups.value = await res.json()
    }
  } catch (e) {
    error.value = e.message
  }
}

async function assignAgentToGroup() {
  if (!assignForm.value.groupId) return
  try {
    const res = await authFetch('/agents/groups', {
      method: 'POST',
      body: JSON.stringify({
        agentId: selectedAgent.value.id,
        groupId: assignForm.value.groupId,
        permissionLevel: assignForm.value.permissionLevel,
      }),
    })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.error || 'Failed to assign agent')
    }
    await selectAgent(selectedAgent.value)
    showAssignGroupModal.value = false
    assignForm.value = { groupId: null, permissionLevel: 0 }
  } catch (e) {
    error.value = e.message
  }
}

async function removeAgentFromGroup(groupId) {
  try {
    const res = await authFetch(`/agents/${selectedAgent.value.id}/groups/${groupId}`, {
      method: 'DELETE',
    })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.error || 'Failed to remove')
    }
    await selectAgent(selectedAgent.value)
  } catch (e) {
    error.value = e.message
  }
}

async function assignUserPermission() {
  if (!userAssignForm.value.userId) return
  try {
    const res = await authFetch('/permissions', {
      method: 'POST',
      body: JSON.stringify({
        userId: userAssignForm.value.userId,
        agentId: selectedAgent.value.id,
        permissionLevel: userAssignForm.value.permissionLevel,
      }),
    })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.error || 'Failed to assign permission')
    }
    showAssignUserModal.value = false
    userAssignForm.value = { userId: null, permissionLevel: 0 }
  } catch (e) {
    error.value = e.message
  }
}

const availableGroups = computed(() => {
  const assignedIds = new Set(agentGroups.value.map(ag => ag.groupId))
  return groups.value.filter(g => !assignedIds.has(g.id))
})

onMounted(fetchData)
</script>

<template>
  <div>
    <!-- Header -->
    <div class="flex items-center justify-between mb-6">
      <div>
        <h2 class="text-xl font-semibold">Permission Management</h2>
        <p class="text-sm text-gray-400 mt-1">Manage agent permissions for groups and users</p>
      </div>
      <button @click="$emit('back')" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg">
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

    <div v-else class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Agent List -->
      <div class="bg-gray-800 rounded-lg p-4">
        <h3 class="text-sm font-medium text-gray-300 mb-4">Select Agent</h3>
        <div v-if="agents.length === 0" class="text-center py-8 text-gray-400">
          No agents connected
        </div>
        <div v-else class="space-y-2">
          <button
            v-for="agent in agents"
            :key="agent.id"
            @click="selectAgent(agent)"
            :class="[
              'w-full text-left px-4 py-3 rounded-lg transition',
              selectedAgent?.id === agent.id ? 'bg-blue-600' : 'bg-gray-700 hover:bg-gray-600'
            ]"
          >
            <div class="font-medium text-white">{{ agent.hostname }}</div>
            <div class="text-xs text-gray-400">{{ agent.os }} • {{ agent.arch }}</div>
          </button>
        </div>
      </div>

      <!-- Agent Permissions -->
      <div class="lg:col-span-2">
        <div v-if="!selectedAgent" class="bg-gray-800 rounded-lg p-12 text-center">
          <svg class="w-16 h-16 text-gray-600 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
          </svg>
          <p class="text-gray-400">Select an agent to manage permissions</p>
        </div>

        <div v-else class="space-y-6">
          <!-- Agent Info -->
          <div class="bg-gray-800 rounded-lg p-6">
            <div class="flex items-center justify-between mb-4">
              <div>
                <h3 class="text-lg font-semibold text-white">{{ selectedAgent.hostname }}</h3>
                <p class="text-sm text-gray-400">{{ selectedAgent.id }}</p>
              </div>
              <span class="px-3 py-1 bg-green-600/20 text-green-400 rounded-full text-sm">
                Connected
              </span>
            </div>
            <div class="grid grid-cols-3 gap-4 text-sm">
              <div>
                <span class="text-gray-400">OS:</span>
                <span class="text-white ml-2">{{ selectedAgent.os }} {{ selectedAgent.arch }}</span>
              </div>
              <div>
                <span class="text-gray-400">Version:</span>
                <span class="text-white ml-2">{{ selectedAgent.version || '-' }}</span>
              </div>
              <div>
                <span class="text-gray-400">Permission Level:</span>
                <span class="text-white ml-2">{{ selectedAgent.permissionLevel }}</span>
              </div>
            </div>
          </div>

          <!-- Group Assignments -->
          <div class="bg-gray-800 rounded-lg p-6">
            <div class="flex items-center justify-between mb-4">
              <h4 class="font-medium text-white">Group Assignments</h4>
              <button
                @click="showAssignGroupModal = true"
                class="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-sm"
              >
                Assign to Group
              </button>
            </div>
            <div v-if="agentGroups.length === 0" class="text-center py-4 text-gray-400 text-sm">
              Not assigned to any group
            </div>
            <div v-else class="space-y-2">
              <div
                v-for="ag in agentGroups"
                :key="ag.id"
                class="flex items-center justify-between bg-gray-700 rounded-lg px-4 py-3"
              >
                <div>
                  <span class="text-white font-medium">{{ ag.groupName }}</span>
                  <span class="ml-3 px-2 py-0.5 bg-gray-600 rounded text-xs text-gray-300">
                    {{ ag.permissionName }}
                  </span>
                </div>
                <button
                  @click="removeAgentFromGroup(ag.groupId)"
                  class="text-red-400 hover:text-red-300"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>
          </div>

          <!-- Direct User Permissions -->
          <div class="bg-gray-800 rounded-lg p-6">
            <div class="flex items-center justify-between mb-4">
              <h4 class="font-medium text-white">Direct User Permissions</h4>
              <button
                @click="showAssignUserModal = true"
                class="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-sm"
              >
                Assign to User
              </button>
            </div>
            <p class="text-sm text-gray-400">
              Assign specific permission levels directly to users for this agent.
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- Assign Group Modal -->
    <div v-if="showAssignGroupModal" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div class="bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4 border border-gray-700">
        <h3 class="text-lg font-semibold text-white mb-4">Assign Agent to Group</h3>
        <form @submit.prevent="assignAgentToGroup" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-300 mb-2">Group</label>
            <select
              v-model="assignForm.groupId"
              class="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-lg text-white"
            >
              <option :value="null">Select a group...</option>
              <option v-for="group in availableGroups" :key="group.id" :value="group.id">
                {{ group.name }}
              </option>
            </select>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-300 mb-2">Permission Level</label>
            <select
              v-model="assignForm.permissionLevel"
              class="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-lg text-white"
            >
              <option v-for="level in permissionLevels" :key="level.value" :value="level.value">
                {{ level.value }} - {{ level.name }} ({{ level.description }})
              </option>
            </select>
          </div>
          <div class="flex justify-end space-x-3">
            <button type="button" @click="showAssignGroupModal = false" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg">
              Cancel
            </button>
            <button type="submit" :disabled="!assignForm.groupId" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:opacity-50 rounded-lg">
              Assign
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- Assign User Modal -->
    <div v-if="showAssignUserModal" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div class="bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4 border border-gray-700">
        <h3 class="text-lg font-semibold text-white mb-4">Assign User Permission</h3>
        <form @submit.prevent="assignUserPermission" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-300 mb-2">User</label>
            <select
              v-model="userAssignForm.userId"
              class="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-lg text-white"
            >
              <option :value="null">Select a user...</option>
              <option v-for="user in users" :key="user.id" :value="user.id">
                {{ user.username }}
              </option>
            </select>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-300 mb-2">Permission Level</label>
            <select
              v-model="userAssignForm.permissionLevel"
              class="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-lg text-white"
            >
              <option v-for="level in permissionLevels" :key="level.value" :value="level.value">
                {{ level.value }} - {{ level.name }}
              </option>
            </select>
          </div>
          <div class="flex justify-end space-x-3">
            <button type="button" @click="showAssignUserModal = false" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg">
              Cancel
            </button>
            <button type="submit" :disabled="!userAssignForm.userId" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:opacity-50 rounded-lg">
              Assign
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
