<script setup>
import { computed } from 'vue'

const props = defineProps({
  systemInfo: {
    type: Object,
    default: null
  },
  cpu: {
    type: Object,
    default: null
  },
  memory: {
    type: Object,
    default: null
  }
})

const formatUptime = (seconds) => {
  if (!seconds) return '--'
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)

  const parts = []
  if (days > 0) parts.push(`${days}d`)
  if (hours > 0) parts.push(`${hours}h`)
  if (minutes > 0) parts.push(`${minutes}m`)

  return parts.join(' ') || '< 1m'
}

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

const bootTime = computed(() => {
  if (!props.systemInfo?.bootTime) return '--'
  const date = new Date(props.systemInfo.bootTime * 1000)
  return date.toLocaleString()
})
</script>

<template>
  <div class="bg-slate-800 rounded-xl border border-slate-700">
    <div class="p-4 border-b border-slate-700">
      <h3 class="text-lg font-semibold text-white flex items-center gap-2">
        <svg class="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
        </svg>
        System Information
      </h3>
    </div>

    <div class="p-4 space-y-4">
      <!-- OS Info -->
      <div class="bg-slate-700/50 rounded-lg p-3">
        <h4 class="text-sm font-medium text-slate-300 mb-2">Operating System</h4>
        <div class="grid grid-cols-2 gap-2 text-sm">
          <div>
            <span class="text-slate-400">OS:</span>
            <span class="text-white ml-2">{{ systemInfo?.osName || '--' }}</span>
          </div>
          <div>
            <span class="text-slate-400">Version:</span>
            <span class="text-white ml-2">{{ systemInfo?.osVersion || '--' }}</span>
          </div>
          <div>
            <span class="text-slate-400">Kernel:</span>
            <span class="text-white ml-2">{{ systemInfo?.kernelVersion || '--' }}</span>
          </div>
          <div>
            <span class="text-slate-400">Hostname:</span>
            <span class="text-white ml-2">{{ systemInfo?.hostname || '--' }}</span>
          </div>
        </div>
      </div>

      <!-- CPU Info -->
      <div v-if="cpu" class="bg-slate-700/50 rounded-lg p-3">
        <h4 class="text-sm font-medium text-slate-300 mb-2">Processor</h4>
        <div class="space-y-2 text-sm">
          <div class="flex items-center justify-between">
            <span class="text-slate-400">Model:</span>
            <span class="text-white">{{ cpu.model || '--' }}</span>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div>
              <span class="text-slate-400">Vendor:</span>
              <span class="text-white ml-2">{{ cpu.vendor || '--' }}</span>
            </div>
            <div>
              <span class="text-slate-400">Architecture:</span>
              <span class="text-white ml-2">{{ cpu.architecture || '--' }}</span>
            </div>
            <div>
              <span class="text-slate-400">Physical Cores:</span>
              <span class="text-white ml-2">{{ cpu.physicalCores || '--' }}</span>
            </div>
            <div>
              <span class="text-slate-400">Logical Cores:</span>
              <span class="text-white ml-2">{{ cpu.logicalCores || cpu.coreCount || '--' }}</span>
            </div>
            <div>
              <span class="text-slate-400">Current Freq:</span>
              <span class="text-white ml-2">{{ cpu.frequencyMhz ? cpu.frequencyMhz + ' MHz' : '--' }}</span>
            </div>
            <div>
              <span class="text-slate-400">Max Freq:</span>
              <span class="text-white ml-2">{{ cpu.frequencyMaxMhz ? cpu.frequencyMaxMhz + ' MHz' : '--' }}</span>
            </div>
          </div>
          <div v-if="cpu.temperature > 0" class="flex items-center justify-between mt-2">
            <span class="text-slate-400">Temperature:</span>
            <span :class="[
              'font-medium',
              cpu.temperature > 80 ? 'text-red-400' :
              cpu.temperature > 60 ? 'text-amber-400' : 'text-green-400'
            ]">{{ cpu.temperature.toFixed(0) }}°C</span>
          </div>
        </div>
      </div>

      <!-- Memory Info -->
      <div v-if="memory" class="bg-slate-700/50 rounded-lg p-3">
        <h4 class="text-sm font-medium text-slate-300 mb-2">Memory</h4>
        <div class="grid grid-cols-2 gap-2 text-sm">
          <div>
            <span class="text-slate-400">Total:</span>
            <span class="text-white ml-2">{{ formatBytes(memory.total) }}</span>
          </div>
          <div>
            <span class="text-slate-400">Type:</span>
            <span class="text-white ml-2">{{ memory.memoryType || '--' }}</span>
          </div>
          <div>
            <span class="text-slate-400">Speed:</span>
            <span class="text-white ml-2">{{ memory.memorySpeedMhz ? memory.memorySpeedMhz + ' MHz' : '--' }}</span>
          </div>
          <div>
            <span class="text-slate-400">Swap:</span>
            <span class="text-white ml-2">{{ formatBytes(memory.swapTotal) }}</span>
          </div>
        </div>
      </div>

      <!-- Hardware Info -->
      <div v-if="systemInfo?.systemVendor || systemInfo?.motherboardModel" class="bg-slate-700/50 rounded-lg p-3">
        <h4 class="text-sm font-medium text-slate-300 mb-2">Hardware</h4>
        <div class="space-y-2 text-sm">
          <div v-if="systemInfo?.systemModel || systemInfo?.systemVendor" class="flex items-center justify-between">
            <span class="text-slate-400">System:</span>
            <span class="text-white">{{ [systemInfo?.systemVendor, systemInfo?.systemModel].filter(Boolean).join(' ') || '--' }}</span>
          </div>
          <div v-if="systemInfo?.motherboardModel || systemInfo?.motherboardVendor" class="flex items-center justify-between">
            <span class="text-slate-400">Motherboard:</span>
            <span class="text-white">{{ [systemInfo?.motherboardVendor, systemInfo?.motherboardModel].filter(Boolean).join(' ') || '--' }}</span>
          </div>
          <div v-if="systemInfo?.biosVersion" class="flex items-center justify-between">
            <span class="text-slate-400">BIOS:</span>
            <span class="text-white">{{ systemInfo.biosVersion }}</span>
          </div>
        </div>
      </div>

      <!-- Uptime -->
      <div class="flex items-center justify-between text-sm">
        <div class="flex items-center gap-2">
          <svg class="w-4 h-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span class="text-slate-400">Uptime:</span>
          <span class="text-green-400 font-medium">{{ formatUptime(systemInfo?.uptimeSeconds) }}</span>
        </div>
        <div class="text-slate-500 text-xs">
          Boot: {{ bootTime }}
        </div>
      </div>
    </div>
  </div>
</template>
