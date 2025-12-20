<script setup>
import { ref } from 'vue'
import { useAuth } from '../composables/useAuth.js'

const { state, logout } = useAuth()
const showMenu = ref(false)

function handleLogout() {
  logout()
  showMenu.value = false
}
</script>

<template>
  <div class="relative">
    <!-- User Button -->
    <button
      @click="showMenu = !showMenu"
      class="flex items-center space-x-2 px-3 py-2 rounded-lg hover:bg-gray-700 transition"
    >
      <div class="w-8 h-8 bg-blue-600 rounded-full flex items-center justify-center">
        <span class="text-sm font-medium text-white">
          {{ state.user?.username?.charAt(0)?.toUpperCase() || 'U' }}
        </span>
      </div>
      <span class="text-sm text-gray-300 hidden sm:inline">{{ state.user?.username }}</span>
      <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
      </svg>
    </button>

    <!-- Dropdown Menu -->
    <div
      v-if="showMenu"
      class="absolute right-0 mt-2 w-56 bg-gray-800 rounded-lg shadow-xl border border-gray-700 py-2 z-50"
    >
      <!-- User Info -->
      <div class="px-4 py-3 border-b border-gray-700">
        <p class="text-sm font-medium text-white">{{ state.user?.username }}</p>
        <p class="text-xs text-gray-400">{{ state.user?.email || 'No email' }}</p>
        <span
          v-if="state.user?.isSuperAdmin"
          class="inline-block mt-2 px-2 py-0.5 bg-purple-600 text-purple-100 text-xs font-medium rounded"
        >
          Super Admin
        </span>
      </div>

      <!-- Menu Items -->
      <div class="py-1">
        <a
          href="#"
          @click.prevent="$emit('show-settings')"
          class="flex items-center px-4 py-2 text-sm text-gray-300 hover:bg-gray-700"
        >
          <svg class="w-4 h-4 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          Settings
        </a>

        <!-- Admin Menu (super admin only) -->
        <template v-if="state.user?.isSuperAdmin">
          <div class="border-t border-gray-700 my-1"></div>
          <a
            href="#"
            @click.prevent="$emit('show-users')"
            class="flex items-center px-4 py-2 text-sm text-gray-300 hover:bg-gray-700"
          >
            <svg class="w-4 h-4 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z" />
            </svg>
            User Management
          </a>
          <a
            href="#"
            @click.prevent="$emit('show-groups')"
            class="flex items-center px-4 py-2 text-sm text-gray-300 hover:bg-gray-700"
          >
            <svg class="w-4 h-4 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            Group Management
          </a>
          <a
            href="#"
            @click.prevent="$emit('show-permissions')"
            class="flex items-center px-4 py-2 text-sm text-gray-300 hover:bg-gray-700"
          >
            <svg class="w-4 h-4 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
            </svg>
            Permissions
          </a>
        </template>

        <div class="border-t border-gray-700 my-1"></div>
        <button
          @click="handleLogout"
          class="flex items-center w-full px-4 py-2 text-sm text-red-400 hover:bg-gray-700"
        >
          <svg class="w-4 h-4 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
          </svg>
          Sign Out
        </button>
      </div>
    </div>

    <!-- Backdrop to close menu -->
    <div
      v-if="showMenu"
      class="fixed inset-0 z-40"
      @click="showMenu = false"
    ></div>
  </div>
</template>
