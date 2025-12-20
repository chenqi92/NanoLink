<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useAuth } from './composables/useAuth.js'
import LoginForm from './components/LoginForm.vue'
import AgentCard from './components/AgentCard.vue'
import SummaryCard from './components/SummaryCard.vue'
import UserMenu from './components/UserMenu.vue'

const { state: authState, initAuth, authFetch, logout } = useAuth()

const agents = ref([])
const metrics = ref({})
const summary = ref({
  agentCount: 0,
  avgCpuPercent: 0,
  memoryPercent: 0,
})
const loading = ref(true)
const error = ref(null)
const currentView = ref('dashboard') // 'dashboard', 'users', 'groups', 'permissions'

let refreshInterval = null

async function fetchData() {
  try {
    const [agentsRes, metricsRes, summaryRes] = await Promise.all([
      authFetch('/agents'),
      authFetch('/metrics'),
      authFetch('/summary'),
    ])

    if (!agentsRes.ok || !metricsRes.ok || !summaryRes.ok) {
      if (agentsRes.status === 401) {
        logout()
        return
      }
      throw new Error('Failed to fetch data')
    }

    agents.value = await agentsRes.json()
    metrics.value = await metricsRes.json()
    summary.value = await summaryRes.json()
    error.value = null
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

function startPolling() {
  fetchData()
  refreshInterval = setInterval(fetchData, 2000)
}

function stopPolling() {
  if (refreshInterval) {
    clearInterval(refreshInterval)
    refreshInterval = null
  }
}

function handleLoginSuccess() {
  loading.value = true
  startPolling()
}

function handleShowView(view) {
  currentView.value = view
}

onMounted(async () => {
  await initAuth()
  if (authState.isAuthenticated) {
    startPolling()
  }
})

onUnmounted(() => {
  stopPolling()
})
</script>

<template>
  <!-- Auth Loading -->
  <div v-if="authState.loading" class="min-h-screen bg-gray-900 flex items-center justify-center">
    <div class="text-center">
      <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500 mx-auto"></div>
      <p class="mt-4 text-gray-400">Loading...</p>
    </div>
  </div>

  <!-- Login Form -->
  <LoginForm v-else-if="!authState.isAuthenticated" @login-success="handleLoginSuccess" />

  <!-- Main Dashboard -->
  <div v-else class="min-h-screen bg-gray-900 text-white">
    <!-- Header -->
    <header class="bg-gray-800 border-b border-gray-700 px-6 py-4">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <svg class="w-8 h-8 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
          </svg>
          <h1 class="text-xl font-bold">NanoLink Dashboard</h1>
        </div>
        <div class="flex items-center space-x-4">
          <span class="text-sm text-gray-400">
            {{ agents.length }} Agent{{ agents.length !== 1 ? 's' : '' }} Connected
          </span>
          <div class="w-2 h-2 rounded-full" :class="error ? 'bg-red-500' : 'bg-green-500'"></div>
          <UserMenu
            @show-users="handleShowView('users')"
            @show-groups="handleShowView('groups')"
            @show-permissions="handleShowView('permissions')"
            @show-settings="handleShowView('settings')"
          />
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <main class="p-6">
      <!-- Error Alert -->
      <div v-if="error" class="mb-6 bg-red-900/50 border border-red-700 rounded-lg p-4">
        <p class="text-red-300">{{ error }}</p>
      </div>

      <!-- Loading -->
      <div v-if="loading" class="flex items-center justify-center h-64">
        <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500"></div>
      </div>

      <template v-else-if="currentView === 'dashboard'">
        <!-- Summary Cards -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <SummaryCard
            title="Connected Agents"
            :value="summary.connectedAgents || 0"
            icon="server"
          />
          <SummaryCard
            title="Avg CPU Usage"
            :value="`${(summary.avgCpuPercent || 0).toFixed(1)}%`"
            icon="cpu"
            :color="summary.avgCpuPercent > 80 ? 'red' : summary.avgCpuPercent > 50 ? 'yellow' : 'green'"
          />
          <SummaryCard
            title="Avg Memory Usage"
            :value="`${(summary.memoryPercent || 0).toFixed(1)}%`"
            icon="memory"
            :color="summary.memoryPercent > 80 ? 'red' : summary.memoryPercent > 50 ? 'yellow' : 'green'"
          />
        </div>

        <!-- Agent Cards -->
        <h2 class="text-lg font-semibold mb-4">Agents</h2>
        <div v-if="agents.length === 0" class="card text-center py-12">
          <p class="text-gray-400">No agents connected</p>
          <p class="text-sm text-gray-500 mt-2">Agents will appear here when they connect</p>
        </div>
        <div v-else class="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-6">
          <AgentCard
            v-for="agent in agents"
            :key="agent.id"
            :agent="agent"
            :metrics="metrics[agent.id]"
          />
        </div>
      </template>

      <!-- Admin Views (placeholder for now) -->
      <template v-else-if="currentView === 'users'">
        <div class="flex items-center justify-between mb-6">
          <h2 class="text-xl font-semibold">User Management</h2>
          <button @click="currentView = 'dashboard'" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg">
            Back to Dashboard
          </button>
        </div>
        <div class="bg-gray-800 rounded-lg p-8 text-center">
          <svg class="w-16 h-16 text-gray-600 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197" />
          </svg>
          <p class="text-gray-400">User management interface coming soon</p>
        </div>
      </template>

      <template v-else-if="currentView === 'groups'">
        <div class="flex items-center justify-between mb-6">
          <h2 class="text-xl font-semibold">Group Management</h2>
          <button @click="currentView = 'dashboard'" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg">
            Back to Dashboard
          </button>
        </div>
        <div class="bg-gray-800 rounded-lg p-8 text-center">
          <svg class="w-16 h-16 text-gray-600 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          <p class="text-gray-400">Group management interface coming soon</p>
        </div>
      </template>

      <template v-else-if="currentView === 'permissions'">
        <div class="flex items-center justify-between mb-6">
          <h2 class="text-xl font-semibold">Permission Management</h2>
          <button @click="currentView = 'dashboard'" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg">
            Back to Dashboard
          </button>
        </div>
        <div class="bg-gray-800 rounded-lg p-8 text-center">
          <svg class="w-16 h-16 text-gray-600 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
          </svg>
          <p class="text-gray-400">Permission management interface coming soon</p>
        </div>
      </template>
    </main>
  </div>
</template>
