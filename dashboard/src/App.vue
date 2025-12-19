<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import ServerCard from './components/ServerCard.vue'
import MetricsChart from './components/MetricsChart.vue'
import ProcessList from './components/ProcessList.vue'
import CommandPanel from './components/CommandPanel.vue'
import GpuCard from './components/GpuCard.vue'
import SystemInfoCard from './components/SystemInfoCard.vue'
import DiskCard from './components/DiskCard.vue'
import { useWebSocket } from './composables/useWebSocket'

const { agents, connected, connect, selectedAgent, selectAgent } = useWebSocket()

const activeTab = ref('overview')

const tabs = [
  { id: 'overview', name: 'Overview', icon: 'chart' },
  { id: 'hardware', name: 'Hardware', icon: 'cpu' },
  { id: 'processes', name: 'Processes', icon: 'list' },
  { id: 'commands', name: 'Commands', icon: 'terminal' }
]

const currentAgent = computed(() => {
  if (!selectedAgent.value || !agents.value[selectedAgent.value]) {
    return null
  }
  return agents.value[selectedAgent.value]
})

const agentList = computed(() => Object.values(agents.value))

onMounted(() => {
  connect()
})
</script>

<template>
  <div class="min-h-screen bg-slate-900">
    <!-- Header -->
    <header class="bg-slate-800 border-b border-slate-700 px-6 py-4">
      <div class="max-w-7xl mx-auto flex items-center justify-between">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 bg-primary-500 rounded-lg flex items-center justify-center">
            <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
            </svg>
          </div>
          <div>
            <h1 class="text-xl font-bold text-white">NanoLink</h1>
            <p class="text-sm text-slate-400">Server Monitoring Dashboard</p>
          </div>
        </div>

        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2">
            <div :class="[
              'w-2.5 h-2.5 rounded-full',
              connected ? 'bg-green-500' : 'bg-red-500'
            ]"></div>
            <span class="text-sm text-slate-300">
              {{ connected ? 'Connected' : 'Disconnected' }}
            </span>
          </div>
          <span class="text-sm text-slate-500">
            {{ agentList.length }} agent{{ agentList.length !== 1 ? 's' : '' }}
          </span>
        </div>
      </div>
    </header>

    <main class="max-w-7xl mx-auto px-6 py-8">
      <!-- Agent Selector -->
      <div v-if="agentList.length > 0" class="mb-8">
        <h2 class="text-lg font-semibold text-white mb-4">Connected Agents</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          <ServerCard
            v-for="agent in agentList"
            :key="agent.agentId"
            :agent="agent"
            :selected="selectedAgent === agent.agentId"
            @click="selectAgent(agent.agentId)"
          />
        </div>
      </div>

      <!-- No Agents Message -->
      <div v-else class="text-center py-20">
        <div class="w-20 h-20 mx-auto mb-4 bg-slate-800 rounded-full flex items-center justify-center">
          <svg class="w-10 h-10 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
          </svg>
        </div>
        <h3 class="text-xl font-medium text-white mb-2">No Agents Connected</h3>
        <p class="text-slate-400 max-w-md mx-auto">
          Install the NanoLink agent on your servers to start monitoring.
          Once connected, they will appear here automatically.
        </p>
      </div>

      <!-- Agent Details -->
      <div v-if="currentAgent" class="space-y-6">
        <!-- Tab Navigation -->
        <div class="flex items-center gap-2 border-b border-slate-700 pb-2">
          <button
            v-for="tab in tabs"
            :key="tab.id"
            @click="activeTab = tab.id"
            :class="[
              'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
              activeTab === tab.id
                ? 'bg-primary-500 text-white'
                : 'text-slate-400 hover:text-white hover:bg-slate-800'
            ]"
          >
            {{ tab.name }}
          </button>
        </div>

        <!-- Overview Tab -->
        <div v-if="activeTab === 'overview'">
          <h2 class="text-lg font-semibold text-white mb-4">
            {{ currentAgent.hostname }} - Real-time Metrics
          </h2>
          <MetricsChart :metrics="currentAgent.lastMetrics" />
        </div>

        <!-- Hardware Tab -->
        <div v-if="activeTab === 'hardware'" class="space-y-6">
          <h2 class="text-lg font-semibold text-white mb-4">
            {{ currentAgent.hostname }} - Hardware Information
          </h2>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <!-- System Info Card -->
            <SystemInfoCard
              :system-info="currentAgent.lastMetrics?.systemInfo"
              :cpu="currentAgent.lastMetrics?.cpu"
              :memory="currentAgent.lastMetrics?.memory"
            />

            <!-- GPU Card -->
            <GpuCard :gpus="currentAgent.lastMetrics?.gpus || []" />
          </div>

          <!-- Disk Card -->
          <DiskCard :disks="currentAgent.lastMetrics?.disks || []" />
        </div>

        <!-- Processes Tab -->
        <div v-if="activeTab === 'processes'">
          <h2 class="text-lg font-semibold text-white mb-4">
            {{ currentAgent.hostname }} - Processes
          </h2>
          <ProcessList :agent="currentAgent" />
        </div>

        <!-- Commands Tab -->
        <div v-if="activeTab === 'commands'">
          <h2 class="text-lg font-semibold text-white mb-4">
            {{ currentAgent.hostname }} - Commands
          </h2>
          <CommandPanel :agent="currentAgent" />
        </div>
      </div>
    </main>
  </div>
</template>
