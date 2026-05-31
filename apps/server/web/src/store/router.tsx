// router.tsx — lightweight state-based router matching the design's route object.
import React, { createContext, useContext, useCallback, useState } from "react"

export type Page =
  | "dashboard"
  | "agents"
  | "agent-detail"
  | "alerts"
  | "assistant"
  | "operations"
  | "logs"
  | "tokens"
  | "devices"
  | "users"
  | "groups"
  | "permissions"
  | "audit"
  | "settings"

export interface Route {
  page: Page
  agentId?: string
  tab?: string
  focus?: string
  openWizard?: boolean
  openPair?: boolean
}

interface RouterContextValue {
  route: Route
  setRoute: (route: Route) => void
  navigate: (page: Page, extra?: Partial<Route>) => void
}

const RouterContext = createContext<RouterContextValue | undefined>(undefined)

export function RouterProvider({ children }: { children: React.ReactNode }) {
  const [route, setRoute] = useState<Route>({ page: "dashboard" })

  const navigate = useCallback((page: Page, extra?: Partial<Route>) => {
    setRoute({ page, ...extra })
  }, [])

  return <RouterContext.Provider value={{ route, setRoute, navigate }}>{children}</RouterContext.Provider>
}

export function useRouter() {
  const ctx = useContext(RouterContext)
  if (!ctx) throw new Error("useRouter must be used within RouterProvider")
  return ctx
}
