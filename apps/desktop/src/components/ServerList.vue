<script setup>
defineProps({
  servers: Array,
  selectedIndex: Number,
})

defineEmits(['select', 'remove', 'add'])
</script>

<template>
  <div class="flex-1 overflow-auto p-4">
    <div class="flex items-center justify-between mb-4">
      <h3 class="text-sm font-semibold text-gray-400 uppercase">Servers</h3>
      <button
        @click="$emit('add')"
        class="p-1 rounded hover:bg-gray-700 text-gray-400 hover:text-white"
      >
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
        </svg>
      </button>
    </div>

    <div v-if="servers.length === 0" class="text-center py-8">
      <p class="text-gray-500 text-sm">No servers added</p>
      <button
        @click="$emit('add')"
        class="mt-2 text-blue-400 hover:text-blue-300 text-sm"
      >
        Add a server
      </button>
    </div>

    <div v-else class="space-y-2">
      <div
        v-for="(server, index) in servers"
        :key="index"
        :class="[
          'p-3 rounded-lg cursor-pointer transition-colors group',
          selectedIndex === index
            ? 'bg-blue-600/20 border border-blue-500'
            : 'bg-gray-700/50 hover:bg-gray-700 border border-transparent'
        ]"
        @click="$emit('select', index)"
      >
        <div class="flex items-center justify-between">
          <div class="flex-1 min-w-0">
            <div class="font-medium truncate">{{ server.name }}</div>
            <div class="text-xs text-gray-500 truncate">{{ server.url }}</div>
          </div>
          <button
            @click.stop="$emit('remove', index)"
            class="p-1 rounded opacity-0 group-hover:opacity-100 hover:bg-gray-600 text-gray-400 hover:text-red-400"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
