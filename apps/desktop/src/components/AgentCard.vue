<script setup>
import { computed } from 'vue'

const props = defineProps({
  agent: Object,
  metrics: Object,
})

const cpuUsage = computed(() => props.metrics?.cpu?.usagePercent || 0)
const memUsage = computed(() => {
  if (!props.metrics?.memory) return 0
  const { used, total } = props.metrics.memory
  return total > 0 ? (used / total) * 100 : 0
})

const formatBytes = (bytes) => {
  if (!bytes) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i]
}

const getStatusColor = (value) => {
  if (value > 80) return 'bg-red-500'
  if (value > 50) return 'bg-yellow-500'
  return 'bg-green-500'
}
</script>

<template>
  <div class="card">
    <!-- Header -->
    <div class="flex items-center justify-between mb-4">
      <div class="flex items-center space-x-3">
        <div class="w-3 h-3 rounded-full bg-green-500"></div>
        <div>
          <h3 class="font-semibold">{{ agent.hostname }}</h3>
          <p class="text-xs text-gray-500">{{ agent.os }}/{{ agent.arch }}</p>
        </div>
      </div>
      <span class="text-xs text-gray-500">v{{ agent.version }}</span>
    </div>

    <!-- CPU Usage -->
    <div class="mb-4">
      <div class="flex justify-between text-sm mb-1">
        <span class="text-gray-400">CPU</span>
        <span :class="cpuUsage > 80 ? 'text-red-400' : 'text-gray-300'">
          {{ cpuUsage.toFixed(1) }}%
        </span>
      </div>
      <div class="w-full bg-gray-700 rounded-full h-2">
        <div
          class="h-2 rounded-full transition-all duration-300"
          :class="getStatusColor(cpuUsage)"
          :style="{ width: `${Math.min(cpuUsage, 100)}%` }"
        ></div>
      </div>
    </div>

    <!-- Memory Usage -->
    <div class="mb-4">
      <div class="flex justify-between text-sm mb-1">
        <span class="text-gray-400">Memory</span>
        <span :class="memUsage > 80 ? 'text-red-400' : 'text-gray-300'">
          {{ memUsage.toFixed(1) }}%
        </span>
      </div>
      <div class="w-full bg-gray-700 rounded-full h-2">
        <div
          class="h-2 rounded-full transition-all duration-300"
          :class="getStatusColor(memUsage)"
          :style="{ width: `${Math.min(memUsage, 100)}%` }"
        ></div>
      </div>
      <div class="text-xs text-gray-500 mt-1">
        {{ formatBytes(metrics?.memory?.used) }} / {{ formatBytes(metrics?.memory?.total) }}
      </div>
    </div>

    <!-- Network -->
    <div v-if="metrics?.networks?.length" class="grid grid-cols-2 gap-2 text-xs">
      <div class="bg-gray-700/50 rounded p-2">
        <div class="text-gray-500">Download</div>
        <div class="text-green-400">{{ formatBytes(metrics.networks[0]?.rxBytesPerSec || 0) }}/s</div>
      </div>
      <div class="bg-gray-700/50 rounded p-2">
        <div class="text-gray-500">Upload</div>
        <div class="text-blue-400">{{ formatBytes(metrics.networks[0]?.txBytesPerSec || 0) }}/s</div>
      </div>
    </div>
  </div>
</template>
