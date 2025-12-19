<script setup>
import { ref, onMounted } from 'vue'
import { invoke } from '@tauri-apps/api/tauri'
import ServerList from './components/ServerList.vue'
import Dashboard from './components/Dashboard.vue'
import AddServerModal from './components/AddServerModal.vue'

const servers = ref([])
const selectedServer = ref(null)
const showAddModal = ref(false)
const connected = ref(false)
const agents = ref([])
const metrics = ref({})

async function loadServers() {
  try {
    servers.value = await invoke('get_servers')
  } catch (e) {
    console.error('Failed to load servers:', e)
  }
}

async function addServer(server) {
  try {
    await invoke('add_server', {
      url: server.url,
      token: server.token,
      name: server.name,
    })
    await loadServers()
    showAddModal.value = false
  } catch (e) {
    console.error('Failed to add server:', e)
  }
}

async function removeServer(index) {
  try {
    await invoke('remove_server', { index })
    await loadServers()
    if (selectedServer.value === index) {
      selectedServer.value = null
      connected.value = false
    }
  } catch (e) {
    console.error('Failed to remove server:', e)
  }
}

async function connectToServer(index) {
  const server = servers.value[index]
  try {
    await invoke('connect_to_server', {
      url: server.url,
      token: server.token,
    })
    selectedServer.value = index
    connected.value = true
    startPolling(server)
  } catch (e) {
    console.error('Failed to connect:', e)
  }
}

let pollInterval = null

async function startPolling(server) {
  if (pollInterval) clearInterval(pollInterval)

  const fetchData = async () => {
    try {
      const baseUrl = server.url.replace('ws://', 'http://').replace('wss://', 'https://').replace(':9100', ':8080')

      const [agentsRes, metricsRes] = await Promise.all([
        fetch(`${baseUrl}/api/agents`),
        fetch(`${baseUrl}/api/metrics`),
      ])

      if (agentsRes.ok) agents.value = await agentsRes.json()
      if (metricsRes.ok) metrics.value = await metricsRes.json()
    } catch (e) {
      console.error('Failed to fetch data:', e)
    }
  }

  await fetchData()
  pollInterval = setInterval(fetchData, 2000)
}

function disconnect() {
  if (pollInterval) clearInterval(pollInterval)
  selectedServer.value = null
  connected.value = false
  agents.value = []
  metrics.value = {}
}

onMounted(() => {
  loadServers()
})
</script>

<template>
  <div class="min-h-screen bg-gray-900 text-white flex">
    <!-- Sidebar -->
    <div class="w-64 bg-gray-800 border-r border-gray-700 flex flex-col">
      <div class="p-4 border-b border-gray-700">
        <div class="flex items-center space-x-2">
          <svg class="w-8 h-8 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
          </svg>
          <span class="text-xl font-bold">NanoLink</span>
        </div>
      </div>

      <ServerList
        :servers="servers"
        :selectedIndex="selectedServer"
        @select="connectToServer"
        @remove="removeServer"
        @add="showAddModal = true"
      />

      <div class="mt-auto p-4 border-t border-gray-700">
        <div v-if="connected" class="flex items-center space-x-2 text-sm text-green-400">
          <div class="w-2 h-2 rounded-full bg-green-500"></div>
          <span>Connected</span>
        </div>
        <div v-else class="flex items-center space-x-2 text-sm text-gray-500">
          <div class="w-2 h-2 rounded-full bg-gray-600"></div>
          <span>Not connected</span>
        </div>
      </div>
    </div>

    <!-- Main Content -->
    <div class="flex-1 overflow-auto">
      <Dashboard
        v-if="connected"
        :agents="agents"
        :metrics="metrics"
        @disconnect="disconnect"
      />
      <div v-else class="flex items-center justify-center h-full">
        <div class="text-center">
          <svg class="w-16 h-16 text-gray-600 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2" />
          </svg>
          <h2 class="text-xl font-semibold text-gray-400 mb-2">No Server Selected</h2>
          <p class="text-gray-500">Add a server and connect to start monitoring</p>
        </div>
      </div>
    </div>

    <!-- Add Server Modal -->
    <AddServerModal
      v-if="showAddModal"
      @close="showAddModal = false"
      @add="addServer"
    />
  </div>
</template>
