<script setup>
import { computed } from 'vue'

const props = defineProps({
  agent: {
    type: Object,
    required: true
  },
  selected: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['click'])

const cpuUsage = computed(() => {
  return props.agent.lastMetrics?.cpu?.usagePercent?.toFixed(1) || '--'
})

const memUsage = computed(() => {
  const mem = props.agent.lastMetrics?.memory
  if (!mem) return '--'
  return ((mem.used / mem.total) * 100).toFixed(1)
})

const cpuModel = computed(() => {
  const model = props.agent.lastMetrics?.cpu?.model
  if (!model) return null
  // Shorten CPU model name
  return model
    .replace('Intel(R) Core(TM)', 'Intel')
    .replace('AMD Ryzen', 'Ryzen')
    .replace('Processor', '')
    .replace(/\s+/g, ' ')
    .trim()
    .substring(0, 30)
})

const gpuInfo = computed(() => {
  const gpus = props.agent.lastMetrics?.gpus
  if (!gpus || gpus.length === 0) return null
  const gpu = gpus[0]
  return {
    name: gpu.name?.replace('NVIDIA ', '').replace('GeForce ', '').substring(0, 20),
    usage: gpu.usagePercent?.toFixed(0) || '0'
  }
})

const formatBytes = (bytes) => {
  if (!bytes) return '--'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let i = 0
  while (bytes >= 1024 && i < units.length - 1) {
    bytes /= 1024
    i++
  }
  return bytes.toFixed(1) + ' ' + units[i]
}

const totalMemory = computed(() => {
  const mem = props.agent.lastMetrics?.memory?.total
  return formatBytes(mem)
})

const osIcon = computed(() => {
  const os = props.agent.os?.toLowerCase() || ''
  if (os.includes('linux')) return '🐧'
  if (os.includes('darwin') || os.includes('mac')) return '🍎'
  if (os.includes('windows')) return '🪟'
  return '🖥️'
})

const uptime = computed(() => {
  const seconds = props.agent.lastMetrics?.systemInfo?.uptimeSeconds
  if (!seconds) return null
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  if (days > 0) return `${days}d ${hours}h`
  return `${hours}h`
})
</script>

<template>
  <div
    :class="[
      'bg-slate-800 rounded-xl p-4 border cursor-pointer transition-all',
      selected
        ? 'border-primary-500 ring-2 ring-primary-500/20'
        : 'border-slate-700 hover:border-slate-600'
    ]"
    @click="emit('click')"
  >
    <div class="flex items-start justify-between mb-3">
      <div class="flex items-center gap-3">
        <div class="text-2xl">{{ osIcon }}</div>
        <div>
          <h3 class="font-semibold text-white">{{ agent.hostname || 'Unknown' }}</h3>
          <p class="text-xs text-slate-400">{{ agent.os }}/{{ agent.arch }}</p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <span v-if="uptime" class="text-xs text-slate-500">{{ uptime }}</span>
        <div class="w-2 h-2 rounded-full bg-green-500"></div>
      </div>
    </div>

    <!-- CPU Model -->
    <div v-if="cpuModel" class="text-xs text-slate-500 mb-2 truncate" :title="agent.lastMetrics?.cpu?.model">
      {{ cpuModel }}
    </div>

    <div class="grid grid-cols-2 gap-3">
      <div class="bg-slate-700/50 rounded-lg p-2">
        <div class="text-xs text-slate-400 mb-1">CPU</div>
        <div class="text-lg font-semibold text-white">{{ cpuUsage }}%</div>
        <div class="mt-1 h-1.5 bg-slate-600 rounded-full overflow-hidden">
          <div
            class="h-full bg-primary-500 rounded-full transition-all duration-300"
            :style="{ width: `${cpuUsage}%` }"
          ></div>
        </div>
      </div>
      <div class="bg-slate-700/50 rounded-lg p-2">
        <div class="text-xs text-slate-400 mb-1">Memory</div>
        <div class="text-lg font-semibold text-white">{{ memUsage }}%</div>
        <div class="mt-1 h-1.5 bg-slate-600 rounded-full overflow-hidden">
          <div
            class="h-full bg-green-500 rounded-full transition-all duration-300"
            :style="{ width: `${memUsage}%` }"
          ></div>
        </div>
      </div>
    </div>

    <!-- GPU Info (if available) -->
    <div v-if="gpuInfo" class="mt-2 bg-slate-700/50 rounded-lg p-2">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <span class="text-xs text-slate-400">GPU</span>
          <span class="text-xs text-slate-500 truncate" :title="gpuInfo.name">{{ gpuInfo.name }}</span>
        </div>
        <span class="text-sm font-semibold text-white">{{ gpuInfo.usage }}%</span>
      </div>
    </div>

    <div class="mt-3 pt-3 border-t border-slate-700 flex items-center justify-between">
      <span class="text-xs text-slate-400">v{{ agent.version || '0.1.0' }}</span>
      <span class="text-xs text-slate-500">{{ totalMemory }}</span>
    </div>
  </div>
</template>
