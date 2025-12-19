<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import AgentCard from './components/AgentCard.vue'
import SummaryCard from './components/SummaryCard.vue'

const agents = ref([])
const metrics = ref({})
const summary = ref({
  agentCount: 0,
  avgCpuPercent: 0,
  memoryPercent: 0,
})
const loading = ref(true)
const error = ref(null)

let refreshInterval = null

async function fetchData() {
  try {
    const [agentsRes, metricsRes, summaryRes] = await Promise.all([
      fetch('/api/agents'),
      fetch('/api/metrics'),
      fetch('/api/summary'),
    ])

    if (!agentsRes.ok || !metricsRes.ok || !summaryRes.ok) {
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

onMounted(() => {
  fetchData()
  refreshInterval = setInterval(fetchData, 2000)
})

onUnmounted(() => {
  if (refreshInterval) {
    clearInterval(refreshInterval)
  }
})
</script>

<template>
  <div class="min-h-screen bg-gray-900 text-white">
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

      <template v-else>
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
    </main>
  </div>
</template>
