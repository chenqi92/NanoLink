import { useState, useEffect, useCallback } from "react"
import { api, authApi, type User, type AuthResponse } from "@/lib/api"

interface AuthState {
  user: User | null
  isAuthenticated: boolean
  loading: boolean
}

export function useAuth() {
  const [state, setState] = useState<AuthState>({
    user: null,
    isAuthenticated: false,
    loading: true,
  })

  const initAuth = useCallback(async () => {
    const token = api.getToken()
    if (!token) {
      setState({ user: null, isAuthenticated: false, loading: false })
      return
    }

    try {
      const user = await authApi.me()
      setState({ user, isAuthenticated: true, loading: false })
    } catch {
      api.setToken(null)
      setState({ user: null, isAuthenticated: false, loading: false })
    }
  }, [])

  const login = useCallback(async (username: string, password: string) => {
    const response: AuthResponse = await authApi.login({ username, password })
    api.setToken(response.token)
    setState({ user: response.user, isAuthenticated: true, loading: false })
    return response
  }, [])

  const register = useCallback(async (username: string, password: string, email?: string) => {
    const response: AuthResponse = await authApi.register({ username, password, email })
    api.setToken(response.token)
    setState({ user: response.user, isAuthenticated: true, loading: false })
    return response
  }, [])

  const logout = useCallback(() => {
    api.setToken(null)
    setState({ user: null, isAuthenticated: false, loading: false })
  }, [])

  useEffect(() => {
    initAuth()
  }, [initAuth])

  return {
    ...state,
    token: api.getToken(),
    login,
    register,
    logout,
    initAuth,
  }
}
