<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  agent: {
    type: Object,
    required: true
  }
})

const searchQuery = ref('')
const sortBy = ref('cpu')

// Demo processes
const processes = ref([
  { pid: 1, name: 'systemd', user: 'root', cpuPercent: 0.1, memoryBytes: 12 * 1024 * 1024, status: 'running' },
  { pid: 1234, name: 'nginx', user: 'www-data', cpuPercent: 2.5, memoryBytes: 45 * 1024 * 1024, status: 'running' },
  { pid: 2345, name: 'java', user: 'app', cpuPercent: 15.3, memoryBytes: 512 * 1024 * 1024, status: 'running' },
  { pid: 3456, name: 'node', user: 'app', cpuPercent: 8.2, memoryBytes: 128 * 1024 * 1024, status: 'running' },
  { pid: 4567, name: 'postgres', user: 'postgres', cpuPercent: 3.1, memoryBytes: 256 * 1024 * 1024, status: 'running' },
  { pid: 5678, name: 'redis-server', user: 'redis', cpuPercent: 1.2, memoryBytes: 64 * 1024 * 1024, status: 'running' },
])

const filteredProcesses = computed(() => {
  let result = processes.value

  if (searchQuery.value) {
    const query = searchQuery.value.toLowerCase()
    result = result.filter(p =>
      p.name.toLowerCase().includes(query) ||
      p.user.toLowerCase().includes(query) ||
      p.pid.toString().includes(query)
    )
  }

  result = [...result].sort((a, b) => {
    if (sortBy.value === 'cpu') return b.cpuPercent - a.cpuPercent
    if (sortBy.value === 'memory') return b.memoryBytes - a.memoryBytes
    if (sortBy.value === 'name') return a.name.localeCompare(b.name)
    return 0
  })

  return result
})

const formatBytes = (bytes) => {
  if (!bytes) return '--'
  const units = ['B', 'KB', 'MB', 'GB']
  let i = 0
  while (bytes >= 1024 && i < units.length - 1) {
    bytes /= 1024
    i++
  }
  return bytes.toFixed(1) + ' ' + units[i]
}

const killProcess = (pid) => {
  if (confirm(`Kill process ${pid}?`)) {
    console.log('Killing process', pid)
    // Send kill command
  }
}
</script>

<template>
  <div class="bg-slate-800 rounded-xl border border-slate-700">
    <div class="p-4 border-b border-slate-700">
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-lg font-semibold text-white">Processes</h3>
        <select v-model="sortBy"
          class="bg-slate-700 text-sm text-slate-300 rounded-lg px-3 py-1.5 border border-slate-600 focus:outline-none focus:border-primary-500">
          <option value="cpu">Sort by CPU</option>
          <option value="memory">Sort by Memory</option>
          <option value="name">Sort by Name</option>
        </select>
      </div>
      <input
        v-model="searchQuery"
        type="text"
        placeholder="Search processes..."
        class="w-full bg-slate-700 text-slate-300 rounded-lg px-4 py-2 text-sm border border-slate-600 focus:outline-none focus:border-primary-500"
      >
    </div>

    <div class="overflow-auto max-h-96">
      <table class="w-full">
        <thead class="bg-slate-700/50 sticky top-0">
          <tr>
            <th class="text-left text-xs font-medium text-slate-400 px-4 py-2">PID</th>
            <th class="text-left text-xs font-medium text-slate-400 px-4 py-2">Name</th>
            <th class="text-left text-xs font-medium text-slate-400 px-4 py-2">User</th>
            <th class="text-right text-xs font-medium text-slate-400 px-4 py-2">CPU</th>
            <th class="text-right text-xs font-medium text-slate-400 px-4 py-2">Memory</th>
            <th class="text-center text-xs font-medium text-slate-400 px-4 py-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="process in filteredProcesses" :key="process.pid"
            class="border-t border-slate-700/50 hover:bg-slate-700/30">
            <td class="px-4 py-2 text-sm text-slate-400">{{ process.pid }}</td>
            <td class="px-4 py-2">
              <span class="text-sm font-medium text-white">{{ process.name }}</span>
            </td>
            <td class="px-4 py-2 text-sm text-slate-400">{{ process.user }}</td>
            <td class="px-4 py-2 text-sm text-right">
              <span :class="process.cpuPercent > 50 ? 'text-red-400' : 'text-slate-300'">
                {{ process.cpuPercent.toFixed(1) }}%
              </span>
            </td>
            <td class="px-4 py-2 text-sm text-right text-slate-300">
              {{ formatBytes(process.memoryBytes) }}
            </td>
            <td class="px-4 py-2 text-center">
              <button
                @click="killProcess(process.pid)"
                class="text-red-400 hover:text-red-300 p-1"
                title="Kill process"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                    d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
