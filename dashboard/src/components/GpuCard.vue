<script setup>
import { computed } from 'vue'

const props = defineProps({
  gpus: {
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

const getVendorColor = (vendor) => {
  if (!vendor) return 'bg-slate-500'
  const v = vendor.toLowerCase()
  if (v.includes('nvidia')) return 'bg-green-500'
  if (v.includes('amd')) return 'bg-red-500'
  if (v.includes('intel')) return 'bg-blue-500'
  return 'bg-slate-500'
}

const getVendorIcon = (vendor) => {
  if (!vendor) return 'GPU'
  const v = vendor.toLowerCase()
  if (v.includes('nvidia')) return 'NV'
  if (v.includes('amd')) return 'AMD'
  if (v.includes('intel')) return 'INT'
  return 'GPU'
}
</script>

<template>
  <div class="bg-slate-800 rounded-xl border border-slate-700">
    <div class="p-4 border-b border-slate-700">
      <h3 class="text-lg font-semibold text-white flex items-center gap-2">
        <svg class="w-5 h-5 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
        </svg>
        GPU Information
      </h3>
    </div>

    <div v-if="gpus.length === 0" class="p-6 text-center text-slate-400">
      <svg class="w-12 h-12 mx-auto mb-3 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      <p>No GPU detected</p>
    </div>

    <div v-else class="divide-y divide-slate-700">
      <div v-for="gpu in gpus" :key="gpu.index" class="p-4">
        <!-- GPU Header -->
        <div class="flex items-start justify-between mb-4">
          <div class="flex items-center gap-3">
            <div :class="['w-10 h-10 rounded-lg flex items-center justify-center text-white font-bold text-xs', getVendorColor(gpu.vendor)]">
              {{ getVendorIcon(gpu.vendor) }}
            </div>
            <div>
              <h4 class="font-medium text-white">{{ gpu.name || 'Unknown GPU' }}</h4>
              <p class="text-xs text-slate-400">
                {{ gpu.vendor }} | Driver: {{ gpu.driverVersion || 'N/A' }}
              </p>
            </div>
          </div>
          <div v-if="gpu.temperature" class="text-right">
            <span :class="[
              'text-lg font-bold',
              gpu.temperature > 80 ? 'text-red-400' :
              gpu.temperature > 60 ? 'text-amber-400' : 'text-green-400'
            ]">{{ gpu.temperature.toFixed(0) }}°C</span>
          </div>
        </div>

        <!-- GPU Metrics -->
        <div class="grid grid-cols-2 gap-4 mb-4">
          <!-- GPU Usage -->
          <div>
            <div class="flex justify-between text-sm mb-1">
              <span class="text-slate-400">GPU Usage</span>
              <span class="text-white font-medium">{{ (gpu.usagePercent || 0).toFixed(1) }}%</span>
            </div>
            <div class="h-2 bg-slate-700 rounded-full overflow-hidden">
              <div
                class="h-full bg-green-500 rounded-full transition-all duration-300"
                :style="{ width: `${gpu.usagePercent || 0}%` }"
              ></div>
            </div>
          </div>

          <!-- VRAM Usage -->
          <div>
            <div class="flex justify-between text-sm mb-1">
              <span class="text-slate-400">VRAM</span>
              <span class="text-white font-medium">
                {{ formatBytes(gpu.memoryUsed) }} / {{ formatBytes(gpu.memoryTotal) }}
              </span>
            </div>
            <div class="h-2 bg-slate-700 rounded-full overflow-hidden">
              <div
                class="h-full bg-purple-500 rounded-full transition-all duration-300"
                :style="{ width: `${gpu.memoryTotal ? (gpu.memoryUsed / gpu.memoryTotal) * 100 : 0}%` }"
              ></div>
            </div>
          </div>
        </div>

        <!-- Additional Info -->
        <div class="grid grid-cols-3 gap-3 text-sm">
          <div class="bg-slate-700/50 rounded-lg p-2">
            <div class="text-slate-400 text-xs">Power</div>
            <div class="text-white font-medium">
              {{ gpu.powerWatts || 0 }}W
              <span v-if="gpu.powerLimitWatts" class="text-slate-500 text-xs">/ {{ gpu.powerLimitWatts }}W</span>
            </div>
          </div>
          <div class="bg-slate-700/50 rounded-lg p-2">
            <div class="text-slate-400 text-xs">Core Clock</div>
            <div class="text-white font-medium">{{ gpu.clockCoreMhz || 0 }} MHz</div>
          </div>
          <div class="bg-slate-700/50 rounded-lg p-2">
            <div class="text-slate-400 text-xs">Fan Speed</div>
            <div class="text-white font-medium">{{ gpu.fanSpeedPercent || 0 }}%</div>
          </div>
        </div>

        <!-- Encoder/Decoder (if available) -->
        <div v-if="gpu.encoderUsage > 0 || gpu.decoderUsage > 0" class="mt-3 flex gap-4 text-xs">
          <div class="flex items-center gap-2">
            <span class="text-slate-400">Encoder:</span>
            <span class="text-white">{{ gpu.encoderUsage?.toFixed(0) || 0 }}%</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-slate-400">Decoder:</span>
            <span class="text-white">{{ gpu.decoderUsage?.toFixed(0) || 0 }}%</span>
          </div>
          <div v-if="gpu.pcieGeneration" class="flex items-center gap-2">
            <span class="text-slate-400">PCIe:</span>
            <span class="text-white">{{ gpu.pcieGeneration }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
