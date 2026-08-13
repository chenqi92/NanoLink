import type { TFunction } from "i18next"

export type RequestIssueKind = "session" | "forbidden" | "network" | "unavailable" | "failed"

export interface RequestIssue {
  kind: RequestIssueKind
  raw?: string
  status?: number
  requiredLevel?: string
}

function recordOf(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" ? value as Record<string, unknown> : null
}

export function requestIssue(error: unknown): RequestIssue {
  const record = recordOf(error)
  const status = typeof record?.status === "number" ? record.status : undefined
  const raw = typeof record?.error === "string"
    ? record.error
    : error instanceof Error
      ? error.message
      : typeof error === "string"
        ? error
        : undefined
  const requiredLevel = typeof record?.requiredLevel === "string" ? record.requiredLevel : undefined
  const normalized = raw?.trim().toLowerCase() ?? ""

  if (
    status === 401 ||
    normalized.includes("authentication required") ||
    normalized.includes("not authenticated") ||
    normalized.includes("token expired") ||
    normalized.includes("invalid token") ||
    normalized.includes("token revoked")
  ) return { kind: "session", raw, status, requiredLevel }

  if (
    status === 403 ||
    normalized.includes("insufficient permission") ||
    normalized.includes("access denied") ||
    normalized.includes("access required") ||
    normalized.includes("permission denied")
  ) return { kind: "forbidden", raw, status, requiredLevel }

  if (status === 502 || status === 503 || status === 504) {
    return { kind: "unavailable", raw, status, requiredLevel }
  }

  if (
    error instanceof TypeError && (normalized.includes("fetch") || normalized.includes("network")) ||
    normalized.includes("failed to fetch") ||
    normalized.includes("networkerror")
  ) return { kind: "network", raw, status, requiredLevel }

  return { kind: "failed", raw, status, requiredLevel }
}

export function requestIssueCopy(issue: RequestIssue, t: TFunction) {
  switch (issue.kind) {
    case "session":
      return { eyebrow: t("access.sessionEyebrow"), title: t("access.sessionTitle"), description: t("access.sessionExpired") }
    case "forbidden":
      return {
        eyebrow: t("access.restricted"),
        title: t("access.noPermissionTitle"),
        description: issue.requiredLevel
          ? t("access.permissionLevelDesc", { level: issue.requiredLevel })
          : t("access.noPermissionDesc"),
      }
    case "network":
      return { eyebrow: t("access.connectionEyebrow"), title: t("access.networkTitle"), description: t("access.networkDesc") }
    case "unavailable":
      return { eyebrow: t("access.serviceEyebrow"), title: t("access.unavailableTitle"), description: t("access.unavailableDesc") }
    default:
      return { eyebrow: t("access.requestEyebrow"), title: t("access.requestFailedTitle"), description: t("access.requestFailedDesc") }
  }
}

/** Short localized copy for inline action feedback. */
export function userErrorMessage(error: unknown, t: TFunction): string {
  const issue = requestIssue(error)
  const copy = requestIssueCopy(issue, t)
  if (issue.kind !== "failed") return issue.requiredLevel ? `${copy.title} · ${copy.description}` : copy.description
  return issue.raw && !["failed", "request failed", "upload failed"].includes(issue.raw.toLowerCase())
    ? issue.raw
    : copy.description
}
