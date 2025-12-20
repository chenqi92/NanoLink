import { reactive, readonly } from 'vue'

// Auth state
const state = reactive({
  user: null,
  token: null,
  isAuthenticated: false,
  loading: true,
})

// API base URL
const API_BASE = '/api'

// Get stored token
function getStoredToken() {
  return localStorage.getItem('nanolink_token')
}

// Set stored token
function setStoredToken(token) {
  if (token) {
    localStorage.setItem('nanolink_token', token)
  } else {
    localStorage.removeItem('nanolink_token')
  }
}

// Get auth headers
function getAuthHeaders() {
  const token = state.token || getStoredToken()
  return token ? { 'Authorization': `Bearer ${token}` } : {}
}

// Fetch with auth
async function authFetch(url, options = {}) {
  const headers = {
    'Content-Type': 'application/json',
    ...getAuthHeaders(),
    ...options.headers,
  }
  
  const response = await fetch(`${API_BASE}${url}`, {
    ...options,
    headers,
  })
  
  // Handle 401 - token expired or invalid
  if (response.status === 401) {
    logout()
    throw new Error('Authentication required')
  }
  
  return response
}

// Login
async function login(username, password) {
  const response = await fetch(`${API_BASE}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  })
  
  if (!response.ok) {
    const data = await response.json()
    throw new Error(data.error || 'Login failed')
  }
  
  const data = await response.json()
  state.token = data.token
  state.user = data.user
  state.isAuthenticated = true
  setStoredToken(data.token)
  
  return data
}

// Register
async function register(username, password, email) {
  const response = await fetch(`${API_BASE}/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password, email }),
  })
  
  if (!response.ok) {
    const data = await response.json()
    throw new Error(data.error || 'Registration failed')
  }
  
  const data = await response.json()
  state.token = data.token
  state.user = data.user
  state.isAuthenticated = true
  setStoredToken(data.token)
  
  return data
}

// Logout
function logout() {
  state.token = null
  state.user = null
  state.isAuthenticated = false
  setStoredToken(null)
}

// Initialize auth state from stored token
async function initAuth() {
  state.loading = true
  const token = getStoredToken()
  
  if (!token) {
    state.loading = false
    return false
  }
  
  state.token = token
  
  try {
    const response = await authFetch('/auth/me')
    if (response.ok) {
      const user = await response.json()
      state.user = user
      state.isAuthenticated = true
      state.loading = false
      return true
    }
  } catch (e) {
    // Token invalid or expired
    console.error('Auth init failed:', e)
  }
  
  logout()
  state.loading = false
  return false
}

// Export auth store
export function useAuth() {
  return {
    state: readonly(state),
    login,
    register,
    logout,
    initAuth,
    authFetch,
    getAuthHeaders,
  }
}
