<script setup>
import { computed } from 'vue'
import AgentCard from './AgentCard.vue'

const props = defineProps({
  agents: Array,
  metrics: Object,
})

defineEmits(['disconnect'])

const summary = computed(() => {
  let totalCPU = 0
  let totalMem = 0
  let usedMem = 0

  Object.values(props.metrics || {}).forEach(m => {
    totalCPU += m.cpu?.usagePercent || 0
    totalMem += m.memory?.total || 0
    usedMem += m.memory?.used || 0
  })

  const count = Object.keys(props.metrics || {}).length
  return {
    agentCount: props.agents?.length || 0,
    avgCpu: count > 0 ? totalCPU / count : 0,
    memPercent: totalMem > 0 ? (usedMem / totalMem) * 100 : 0,
  }
})
</script>

<template>
  <div class="p-6">
    <!-- Header -->
    <div class="flex items-center justify-between mb-6">
      <h1 class="text-2xl font-bold">Dashboard</h1>
      <button @click="$emit('disconnect')" class="btn btn-secondary text-sm">
        Disconnect
      </button>
    </div>

    <!-- Summary Cards -->
    <div class="grid grid-cols-3 gap-4 mb-8">
      <div class="card">
        <div class="text-sm text-gray-400">Connected Agents</div>
        <div class="text-3xl font-bold text-blue-400">{{ summary.agentCount }}</div>
      </div>
      <div class="card">
        <div class="text-sm text-gray-400">Avg CPU Usage</div>
        <div class="text-3xl font-bold" :class="summary.avgCpu > 80 ? 'text-red-400' : 'text-green-400'">
          {{ summary.avgCpu.toFixed(1) }}%
        </div>
      </div>
      <div class="card">
        <div class="text-sm text-gray-400">Avg Memory Usage</div>
        <div class="text-3xl font-bold" :class="summary.memPercent > 80 ? 'text-red-400' : 'text-green-400'">
          {{ summary.memPercent.toFixed(1) }}%
        </div>
      </div>
    </div>

    <!-- Agents -->
    <h2 class="text-lg font-semibold mb-4">Agents</h2>
    <div v-if="agents.length === 0" class="card text-center py-12">
      <p class="text-gray-400">No agents connected</p>
    </div>
    <div v-else class="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4">
      <AgentCard
        v-for="agent in agents"
        :key="agent.id"
        :agent="agent"
        :metrics="metrics[agent.id]"
      />
    </div>
  </div>
</template>
