import type { Page } from "@/store/router"

const SUPER_ADMIN_PAGES = new Set<Page>([
  "tokens",
  "users",
  "groups",
  "permissions",
  "audit",
  "alert-config",
  "settings",
  "deployments",
])

export function pageRequiresSuperAdmin(page: Page): boolean {
  return SUPER_ADMIN_PAGES.has(page)
}
