<script setup>
import { ref } from 'vue'

const props = defineProps({
  agent: {
    type: Object,
    required: true
  }
})

const selectedCommand = ref(null)
const commandTarget = ref('')
const commandOutput = ref('')
const isExecuting = ref(false)

const commands = [
  { id: 'process_list', name: 'List Processes', icon: '📋', permission: 0 },
  { id: 'service_status', name: 'Service Status', icon: '🔍', permission: 0, needsTarget: true, targetLabel: 'Service name' },
  { id: 'service_restart', name: 'Restart Service', icon: '🔄', permission: 2, needsTarget: true, targetLabel: 'Service name' },
  { id: 'docker_list', name: 'List Containers', icon: '🐳', permission: 0 },
  { id: 'docker_restart', name: 'Restart Container', icon: '🔄', permission: 2, needsTarget: true, targetLabel: 'Container name' },
  { id: 'docker_logs', name: 'Container Logs', icon: '📜', permission: 1, needsTarget: true, targetLabel: 'Container name' },
  { id: 'file_tail', name: 'Tail File', icon: '📄', permission: 0, needsTarget: true, targetLabel: 'File path' },
  { id: 'file_truncate', name: 'Truncate File', icon: '🗑️', permission: 1, needsTarget: true, targetLabel: 'File path' },
]

const permissionLevel = ref(props.agent?.permissionLevel || 0)

const canExecute = (cmd) => {
  return cmd.permission <= permissionLevel.value
}

const selectCommand = (cmd) => {
  if (canExecute(cmd)) {
    selectedCommand.value = cmd
    commandTarget.value = ''
    commandOutput.value = ''
  }
}

const executeCommand = async () => {
  if (!selectedCommand.value) return
  if (selectedCommand.value.needsTarget && !commandTarget.value) {
    alert('Please enter the target')
    return
  }

  isExecuting.value = true
  commandOutput.value = 'Executing...\n'

  // Simulate command execution
  await new Promise(resolve => setTimeout(resolve, 1000))

  // Demo output
  const outputs = {
    process_list: `PID    NAME            CPU%    MEM
1      systemd         0.1%    12M
1234   nginx           2.5%    45M
2345   java            15.3%   512M
3456   node            8.2%    128M`,
    service_status: `● ${commandTarget.value || 'nginx'}.service - Service
   Loaded: loaded
   Active: active (running)
   Main PID: 1234`,
    service_restart: `Restarting ${commandTarget.value}...
Service restarted successfully.`,
    docker_list: `CONTAINER ID   IMAGE          STATUS
abc123         nginx:latest   Up 2 days
def456         redis:7        Up 5 days
ghi789         postgres:15    Up 1 week`,
    docker_restart: `Restarting container ${commandTarget.value}...
Container restarted successfully.`,
    docker_logs: `[2024-01-15 10:30:00] INFO: Starting service...
[2024-01-15 10:30:01] INFO: Listening on port 80
[2024-01-15 10:30:05] INFO: Request from 192.168.1.1`,
    file_tail: `2024-01-15 10:30:00 INFO: Application started
2024-01-15 10:30:01 DEBUG: Loading configuration
2024-01-15 10:30:02 INFO: Ready to serve requests`,
    file_truncate: `File ${commandTarget.value} truncated successfully.`,
  }

  commandOutput.value = outputs[selectedCommand.value.id] || 'Command executed.'
  isExecuting.value = false
}

const clearOutput = () => {
  commandOutput.value = ''
  selectedCommand.value = null
  commandTarget.value = ''
}
</script>

<template>
  <div class="bg-slate-800 rounded-xl border border-slate-700">
    <div class="p-4 border-b border-slate-700">
      <h3 class="text-lg font-semibold text-white">Commands</h3>
      <p class="text-sm text-slate-400 mt-1">
        Permission Level: {{ permissionLevel }}
        <span class="text-xs ml-2">
          ({{ ['Read Only', 'Basic Write', 'Service Control', 'System Admin'][permissionLevel] }})
        </span>
      </p>
    </div>

    <!-- Command Buttons -->
    <div class="p-4 border-b border-slate-700">
      <div class="grid grid-cols-2 gap-2">
        <button
          v-for="cmd in commands"
          :key="cmd.id"
          @click="selectCommand(cmd)"
          :disabled="!canExecute(cmd)"
          :class="[
            'flex items-center gap-2 px-3 py-2 rounded-lg text-sm transition-colors',
            selectedCommand?.id === cmd.id
              ? 'bg-primary-500 text-white'
              : canExecute(cmd)
                ? 'bg-slate-700 text-slate-300 hover:bg-slate-600'
                : 'bg-slate-700/50 text-slate-500 cursor-not-allowed'
          ]"
        >
          <span>{{ cmd.icon }}</span>
          <span>{{ cmd.name }}</span>
        </button>
      </div>
    </div>

    <!-- Command Input -->
    <div v-if="selectedCommand" class="p-4 border-b border-slate-700 space-y-3">
      <div class="flex items-center gap-2">
        <span class="text-2xl">{{ selectedCommand.icon }}</span>
        <span class="font-medium text-white">{{ selectedCommand.name }}</span>
      </div>

      <div v-if="selectedCommand.needsTarget">
        <label class="block text-sm text-slate-400 mb-1">{{ selectedCommand.targetLabel }}</label>
        <input
          v-model="commandTarget"
          type="text"
          :placeholder="selectedCommand.targetLabel"
          class="w-full bg-slate-700 text-slate-300 rounded-lg px-4 py-2 text-sm border border-slate-600 focus:outline-none focus:border-primary-500"
        >
      </div>

      <div class="flex gap-2">
        <button
          @click="executeCommand"
          :disabled="isExecuting"
          class="flex-1 bg-primary-500 hover:bg-primary-600 disabled:bg-primary-500/50 text-white font-medium py-2 px-4 rounded-lg transition-colors"
        >
          {{ isExecuting ? 'Executing...' : 'Execute' }}
        </button>
        <button
          @click="clearOutput"
          class="bg-slate-700 hover:bg-slate-600 text-slate-300 py-2 px-4 rounded-lg transition-colors"
        >
          Clear
        </button>
      </div>
    </div>

    <!-- Output -->
    <div class="p-4">
      <div class="flex items-center justify-between mb-2">
        <span class="text-sm text-slate-400">Output</span>
      </div>
      <div class="bg-slate-900 rounded-lg p-4 font-mono text-sm text-green-400 min-h-[150px] max-h-[300px] overflow-auto whitespace-pre-wrap">
        {{ commandOutput || 'Select a command to execute...' }}
      </div>
    </div>
  </div>
</template>
