import React, { createContext, useContext, useCallback, useEffect, useState } from 'react'
import { api, authApi, type User } from '@/lib/api'

interface AuthContextValue {
  user: User | null
  isAuthenticated: boolean
  isLoading: boolean
  error: string | null
  token: string | null

  login: (username: string, password: string) => Promise<void>
  register: (username: string, password: string, email?: string) => Promise<void>
  logout: () => void
  clearError: () => void
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [token, setTokenState] = useState<string | null>(null)

  useEffect(() => {
    const initAuth = async () => {
      const storedToken = api.getToken()
      if (!storedToken) {
        setIsLoading(false)
        return
      }

      setTokenState(storedToken)
      try {
        const userData = await authApi.me()
        setUser(userData)
        setError(null)
      } catch {
        api.setToken(null)
        setTokenState(null)
      } finally {
        setIsLoading(false)
      }
    }

    initAuth()
  }, [])

  const login = useCallback(async (username: string, password: string) => {
    setIsLoading(true)
    setError(null)
    try {
      const response = await authApi.login({ username, password })
      api.setToken(response.token)
      setTokenState(response.token)
      setUser(response.user)
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Login failed'
      setError(errorMsg)
      throw err
    } finally {
      setIsLoading(false)
    }
  }, [])

  const register = useCallback(async (username: string, password: string, email?: string) => {
    setIsLoading(true)
    setError(null)
    try {
      const response = await authApi.register({ username, password, email })
      api.setToken(response.token)
      setTokenState(response.token)
      setUser(response.user)
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Registration failed'
      setError(errorMsg)
      throw err
    } finally {
      setIsLoading(false)
    }
  }, [])

  const logout = useCallback(() => {
    api.setToken(null)
    setTokenState(null)
    setUser(null)
    setError(null)
  }, [])

  const clearError = useCallback(() => {
    setError(null)
  }, [])

  const value: AuthContextValue = {
    user,
    isAuthenticated: !!token && !!user,
    isLoading,
    error,
    token,
    login,
    register,
    logout,
    clearError,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider')
  }
  return context
}
