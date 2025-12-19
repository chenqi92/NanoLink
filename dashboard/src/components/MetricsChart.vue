<script setup>
import { computed, ref, watch, onMounted } from 'vue'
import { Line } from 'vue-chartjs'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler
} from 'chart.js'

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler
)

const props = defineProps({
  metrics: {
    type: Object,
    default: null
  }
})

const cpuHistory = ref([])
const memHistory = ref([])
const maxHistory = 60

watch(() => props.metrics, (newMetrics) => {
  if (newMetrics) {
    cpuHistory.value.push(newMetrics.cpu?.usagePercent || 0)
    memHistory.value.push(
      newMetrics.memory ? (newMetrics.memory.used / newMetrics.memory.total) * 100 : 0
    )

    if (cpuHistory.value.length > maxHistory) {
      cpuHistory.value.shift()
      memHistory.value.shift()
    }
  }
}, { immediate: true })

const chartData = computed(() => ({
  labels: Array(cpuHistory.value.length).fill(''),
  datasets: [
    {
      label: 'CPU',
      data: cpuHistory.value,
      borderColor: '#3b82f6',
      backgroundColor: 'rgba(59, 130, 246, 0.1)',
      fill: true,
      tension: 0.4,
      pointRadius: 0
    },
    {
      label: 'Memory',
      data: memHistory.value,
      borderColor: '#22c55e',
      backgroundColor: 'rgba(34, 197, 94, 0.1)',
      fill: true,
      tension: 0.4,
      pointRadius: 0
    }
  ]
}))

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: {
    mode: 'index',
    intersect: false
  },
  plugins: {
    legend: {
      position: 'top',
      labels: {
        color: '#94a3b8',
        usePointStyle: true,
        pointStyle: 'circle'
      }
    },
    tooltip: {
      backgroundColor: '#1e293b',
      titleColor: '#e2e8f0',
      bodyColor: '#94a3b8',
      borderColor: '#334155',
      borderWidth: 1,
      callbacks: {
        label: (context) => `${context.dataset.label}: ${context.raw.toFixed(1)}%`
      }
    }
  },
  scales: {
    x: {
      display: false
    },
    y: {
      min: 0,
      max: 100,
      grid: {
        color: '#334155'
      },
      ticks: {
        color: '#64748b',
        callback: (value) => value + '%'
      }
    }
  }
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

const cpuValue = computed(() => props.metrics?.cpu?.usagePercent?.toFixed(1) || '--')
const memValue = computed(() => {
  const mem = props.metrics?.memory
  if (!mem) return '--'
  return ((mem.used / mem.total) * 100).toFixed(1)
})
const diskValue = computed(() => {
  const disk = props.metrics?.disks?.[0]
  if (!disk) return '--'
  return ((disk.used / disk.total) * 100).toFixed(1)
})
const netRx = computed(() => formatBytes(props.metrics?.networks?.[0]?.rxBytesPerSec) + '/s')
const netTx = computed(() => formatBytes(props.metrics?.networks?.[0]?.txBytesPerSec) + '/s')
</script>

<template>
  <div class="space-y-6">
    <!-- Stats Cards -->
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
      <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm text-slate-400">CPU</span>
          <svg class="w-5 h-5 text-primary-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
          </svg>
        </div>
        <div class="text-2xl font-bold text-white">{{ cpuValue }}%</div>
        <div class="text-xs text-slate-500 mt-1">{{ metrics?.cpu?.coreCount || '--' }} cores</div>
        <div class="mt-2 h-1.5 bg-slate-700 rounded-full overflow-hidden">
          <div class="h-full bg-primary-500 rounded-full transition-all duration-300"
            :style="{ width: `${cpuValue}%` }"></div>
        </div>
      </div>

      <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm text-slate-400">Memory</span>
          <svg class="w-5 h-5 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
          </svg>
        </div>
        <div class="text-2xl font-bold text-white">{{ memValue }}%</div>
        <div class="text-xs text-slate-500 mt-1">
          {{ formatBytes(metrics?.memory?.used) }} / {{ formatBytes(metrics?.memory?.total) }}
        </div>
        <div class="mt-2 h-1.5 bg-slate-700 rounded-full overflow-hidden">
          <div class="h-full bg-green-500 rounded-full transition-all duration-300"
            :style="{ width: `${memValue}%` }"></div>
        </div>
      </div>

      <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm text-slate-400">Disk</span>
          <svg class="w-5 h-5 text-amber-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4" />
          </svg>
        </div>
        <div class="text-2xl font-bold text-white">{{ diskValue }}%</div>
        <div class="text-xs text-slate-500 mt-1">
          {{ formatBytes(metrics?.disks?.[0]?.used) }} / {{ formatBytes(metrics?.disks?.[0]?.total) }}
        </div>
        <div class="mt-2 h-1.5 bg-slate-700 rounded-full overflow-hidden">
          <div class="h-full bg-amber-500 rounded-full transition-all duration-300"
            :style="{ width: `${diskValue}%` }"></div>
        </div>
      </div>

      <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm text-slate-400">Network</span>
          <svg class="w-5 h-5 text-purple-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0" />
          </svg>
        </div>
        <div class="text-lg font-bold text-white">
          <span class="text-green-400">↓</span> {{ netRx }}
        </div>
        <div class="text-lg font-bold text-white">
          <span class="text-blue-400">↑</span> {{ netTx }}
        </div>
      </div>
    </div>

    <!-- Chart -->
    <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
      <h3 class="text-sm font-medium text-slate-300 mb-4">Real-time Usage</h3>
      <div class="h-64">
        <Line :data="chartData" :options="chartOptions" />
      </div>
    </div>
  </div>
</template>
