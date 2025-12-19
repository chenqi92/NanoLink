<script setup>
import { computed } from 'vue'

const props = defineProps({
  disks: {
    type: Array,
    default: () => []
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

const formatSpeed = (bytesPerSec) => {
  if (!bytesPerSec) return '0 B/s'
  return formatBytes(bytesPerSec) + '/s'
}

const getDiskTypeColor = (type) => {
  if (!type) return 'bg-slate-500'
  const t = type.toLowerCase()
  if (t === 'nvme') return 'bg-purple-500'
  if (t === 'ssd') return 'bg-blue-500'
  if (t === 'hdd') return 'bg-amber-500'
  return 'bg-slate-500'
}

const getDiskTypeIcon = (type) => {
  if (!type) return 'DISK'
  const t = type.toLowerCase()
  if (t === 'nvme') return 'NVMe'
  if (t === 'ssd') return 'SSD'
  if (t === 'hdd') return 'HDD'
  return type.substring(0, 4).toUpperCase()
}

const getHealthColor = (status) => {
  if (!status || status === 'Unknown') return 'text-slate-400'
  if (status === 'PASSED') return 'text-green-400'
  if (status === 'FAILED') return 'text-red-400'
  return 'text-amber-400'
}

const usagePercent = (disk) => {
  if (!disk.total) return 0
  return (disk.used / disk.total) * 100
}

const usageColor = (percent) => {
  if (percent > 90) return 'bg-red-500'
  if (percent > 75) return 'bg-amber-500'
  return 'bg-blue-500'
}
</script>

<template>
  <div class="bg-slate-800 rounded-xl border border-slate-700">
    <div class="p-4 border-b border-slate-700">
      <h3 class="text-lg font-semibold text-white flex items-center gap-2">
        <svg class="w-5 h-5 text-amber-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4" />
        </svg>
        Storage Devices
      </h3>
    </div>

    <div v-if="disks.length === 0" class="p-6 text-center text-slate-400">
      <p>No storage devices detected</p>
    </div>

    <div v-else class="divide-y divide-slate-700">
      <div v-for="(disk, index) in disks" :key="index" class="p-4">
        <!-- Disk Header -->
        <div class="flex items-start justify-between mb-3">
          <div class="flex items-center gap-3">
            <div :class="['w-10 h-10 rounded-lg flex items-center justify-center text-white font-bold text-xs', getDiskTypeColor(disk.diskType)]">
              {{ getDiskTypeIcon(disk.diskType) }}
            </div>
            <div>
              <h4 class="font-medium text-white">{{ disk.model || disk.device || 'Unknown Disk' }}</h4>
              <p class="text-xs text-slate-400">
                {{ disk.mountPoint }} | {{ disk.fsType || 'N/A' }}
              </p>
            </div>
          </div>
          <div class="text-right">
            <span :class="['text-xs font-medium', getHealthColor(disk.healthStatus)]">
              {{ disk.healthStatus || 'Unknown' }}
            </span>
            <div v-if="disk.temperature > 0" class="text-xs mt-1">
              <span :class="[
                disk.temperature > 50 ? 'text-red-400' :
                disk.temperature > 40 ? 'text-amber-400' : 'text-green-400'
              ]">{{ disk.temperature.toFixed(0) }}°C</span>
            </div>
          </div>
        </div>

        <!-- Usage Bar -->
        <div class="mb-3">
          <div class="flex justify-between text-sm mb-1">
            <span class="text-slate-400">Used</span>
            <span class="text-white">
              {{ formatBytes(disk.used) }} / {{ formatBytes(disk.total) }}
              <span class="text-slate-400">({{ usagePercent(disk).toFixed(1) }}%)</span>
            </span>
          </div>
          <div class="h-2 bg-slate-700 rounded-full overflow-hidden">
            <div
              :class="['h-full rounded-full transition-all duration-300', usageColor(usagePercent(disk))]"
              :style="{ width: `${usagePercent(disk)}%` }"
            ></div>
          </div>
        </div>

        <!-- I/O Stats -->
        <div class="grid grid-cols-2 gap-3 text-sm">
          <div class="bg-slate-700/50 rounded-lg p-2">
            <div class="flex items-center gap-1 text-slate-400 text-xs mb-1">
              <span class="text-green-400">R</span> Read
            </div>
            <div class="text-white font-medium">{{ formatSpeed(disk.readBytesSec) }}</div>
            <div v-if="disk.readIops > 0" class="text-slate-500 text-xs">{{ disk.readIops }} IOPS</div>
          </div>
          <div class="bg-slate-700/50 rounded-lg p-2">
            <div class="flex items-center gap-1 text-slate-400 text-xs mb-1">
              <span class="text-blue-400">W</span> Write
            </div>
            <div class="text-white font-medium">{{ formatSpeed(disk.writeBytesSec) }}</div>
            <div v-if="disk.writeIops > 0" class="text-slate-500 text-xs">{{ disk.writeIops }} IOPS</div>
          </div>
        </div>

        <!-- Additional Info -->
        <div v-if="disk.serial" class="mt-2 text-xs text-slate-500">
          Serial: {{ disk.serial }}
        </div>
      </div>
    </div>
  </div>
</template>
