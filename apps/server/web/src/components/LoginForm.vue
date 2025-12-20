<script setup>
import { ref } from 'vue'
import { useAuth } from '../composables/useAuth.js'

const emit = defineEmits(['login-success'])

const { login, register } = useAuth()

const mode = ref('login') // 'login' or 'register'
const username = ref('')
const password = ref('')
const email = ref('')
const error = ref(null)
const loading = ref(false)

async function handleSubmit() {
  error.value = null
  loading.value = true
  
  try {
    if (mode.value === 'login') {
      await login(username.value, password.value)
    } else {
      await register(username.value, password.value, email.value)
    }
    emit('login-success')
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

function toggleMode() {
  mode.value = mode.value === 'login' ? 'register' : 'login'
  error.value = null
}
</script>

<template>
  <div class="min-h-screen bg-gray-900 flex items-center justify-center px-4">
    <div class="max-w-md w-full">
      <!-- Logo -->
      <div class="text-center mb-8">
        <div class="flex items-center justify-center space-x-3 mb-4">
          <svg class="w-12 h-12 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
          </svg>
          <h1 class="text-3xl font-bold text-white">NanoLink</h1>
        </div>
        <p class="text-gray-400">Server Monitoring Dashboard</p>
      </div>

      <!-- Login/Register Form -->
      <div class="bg-gray-800 rounded-xl shadow-xl p-8 border border-gray-700">
        <h2 class="text-xl font-semibold text-white mb-6 text-center">
          {{ mode === 'login' ? 'Sign In' : 'Create Account' }}
        </h2>

        <!-- Error Alert -->
        <div v-if="error" class="mb-4 bg-red-900/50 border border-red-700 rounded-lg p-3">
          <p class="text-red-300 text-sm">{{ error }}</p>
        </div>

        <form @submit.prevent="handleSubmit" class="space-y-4">
          <!-- Username -->
          <div>
            <label class="block text-sm font-medium text-gray-300 mb-2">Username</label>
            <input
              v-model="username"
              type="text"
              required
              minlength="3"
              maxlength="50"
              class="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition"
              placeholder="Enter your username"
            />
          </div>

          <!-- Email (register only) -->
          <div v-if="mode === 'register'">
            <label class="block text-sm font-medium text-gray-300 mb-2">Email (optional)</label>
            <input
              v-model="email"
              type="email"
              class="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition"
              placeholder="Enter your email"
            />
          </div>

          <!-- Password -->
          <div>
            <label class="block text-sm font-medium text-gray-300 mb-2">Password</label>
            <input
              v-model="password"
              type="password"
              required
              minlength="6"
              class="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition"
              placeholder="Enter your password"
            />
          </div>

          <!-- Submit Button -->
          <button
            type="submit"
            :disabled="loading"
            class="w-full py-3 px-4 bg-blue-600 hover:bg-blue-700 disabled:bg-blue-800 disabled:cursor-not-allowed text-white font-medium rounded-lg transition flex items-center justify-center"
          >
            <svg v-if="loading" class="animate-spin -ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            {{ mode === 'login' ? 'Sign In' : 'Create Account' }}
          </button>
        </form>

        <!-- Toggle Mode -->
        <div class="mt-6 text-center">
          <p class="text-gray-400">
            {{ mode === 'login' ? "Don't have an account?" : 'Already have an account?' }}
            <button
              @click="toggleMode"
              class="text-blue-400 hover:text-blue-300 font-medium ml-1"
            >
              {{ mode === 'login' ? 'Sign Up' : 'Sign In' }}
            </button>
          </p>
        </div>
      </div>

      <!-- Footer -->
      <p class="mt-6 text-center text-gray-500 text-sm">
        NanoLink Server Monitoring © 2024
      </p>
    </div>
  </div>
</template>
