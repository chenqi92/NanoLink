<script setup>
import { ref } from 'vue'

const emit = defineEmits(['close', 'add'])

const name = ref('')
const url = ref('ws://localhost:9100')
const token = ref('')

function submit() {
  if (!name.value || !url.value) return

  emit('add', {
    name: name.value,
    url: url.value,
    token: token.value,
  })
}
</script>

<template>
  <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50" @click.self="$emit('close')">
    <div class="bg-gray-800 rounded-lg p-6 w-full max-w-md shadow-xl">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Add Server</h2>
        <button @click="$emit('close')" class="p-1 rounded hover:bg-gray-700 text-gray-400">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <form @submit.prevent="submit" class="space-y-4">
        <div>
          <label class="block text-sm text-gray-400 mb-1">Name</label>
          <input
            v-model="name"
            type="text"
            placeholder="My Server"
            class="input w-full"
            required
          />
        </div>

        <div>
          <label class="block text-sm text-gray-400 mb-1">WebSocket URL</label>
          <input
            v-model="url"
            type="text"
            placeholder="ws://localhost:9100"
            class="input w-full"
            required
          />
        </div>

        <div>
          <label class="block text-sm text-gray-400 mb-1">Token (optional)</label>
          <input
            v-model="token"
            type="password"
            placeholder="Authentication token"
            class="input w-full"
          />
        </div>

        <div class="flex justify-end space-x-3 pt-4">
          <button type="button" @click="$emit('close')" class="btn btn-secondary">
            Cancel
          </button>
          <button type="submit" class="btn btn-primary">
            Add Server
          </button>
        </div>
      </form>
    </div>
  </div>
</template>
