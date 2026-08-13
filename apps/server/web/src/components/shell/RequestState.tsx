import type { ReactNode } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { requestIssue, requestIssueCopy, type RequestIssueKind } from "@/lib/errors"

type ContentStateKind = RequestIssueKind | "empty" | "admin"

const stateIcon: Record<ContentStateKind, ReactNode> = {
  session: I.lock({ size: 17 }),
  forbidden: I.shield({ size: 17 }),
  network: I.net({ size: 17 }),
  unavailable: I.info({ size: 17 }),
  failed: I.warn({ size: 17 }),
  empty: I.audit({ size: 17 }),
  admin: I.lock({ size: 17 }),
}

export function ContentState({
  kind,
  eyebrow,
  title,
  description,
  action,
  compact = false,
}: {
  kind: ContentStateKind
  eyebrow?: ReactNode
  title: ReactNode
  description?: ReactNode
  action?: ReactNode
  compact?: boolean
}) {
  return (
    <div className={`content-state content-state--${kind}${compact ? " content-state--compact" : ""}`} role={kind === "failed" ? "alert" : "status"}>
      <div className="content-state__body">
        <div className="content-state__icon" aria-hidden="true">{stateIcon[kind]}</div>
        <div className="content-state__copy">
          {eyebrow && <div className="content-state__eyebrow">{eyebrow}</div>}
          <div className="content-state__title">{title}</div>
          {description && <div className="content-state__description">{description}</div>}
          {action && <div className="content-state__action">{action}</div>}
        </div>
      </div>
    </div>
  )
}

export function RequestState({ error, onRetry, compact = false }: { error: unknown; onRetry?: () => void; compact?: boolean }) {
  const { t } = useTranslation()
  const issue = requestIssue(error)
  const copy = requestIssueCopy(issue, t)
  return (
    <ContentState
      kind={issue.kind}
      eyebrow={copy.eyebrow}
      title={copy.title}
      description={copy.description}
      compact={compact}
      action={onRetry && issue.kind !== "session" ? (
        <button className="btn btn-sm" onClick={onRetry}>{I.refresh({ size: 12 })}<span>{t("access.retry")}</span></button>
      ) : undefined}
    />
  )
}

export function LoadingState({ compact = false }: { compact?: boolean }) {
  const { t } = useTranslation()
  return (
    <div className={`content-loading${compact ? " content-loading--compact" : ""}`} role="status">
      <span className="dot pulse ok" />
      <span>{t("common.loading")}</span>
    </div>
  )
}

export function InlineIssue({ error, onDismiss }: { error: unknown; onDismiss?: () => void }) {
  const { t } = useTranslation()
  const issue = requestIssue(error)
  const copy = requestIssueCopy(issue, t)
  return (
    <div className={`inline-issue inline-issue--${issue.kind}`} role={issue.kind === "failed" ? "alert" : "status"}>
      <span className="inline-issue__icon" aria-hidden="true">{stateIcon[issue.kind]}</span>
      <div className="inline-issue__copy">
        <strong>{copy.title}</strong>
        <span>{copy.description}</span>
      </div>
      {onDismiss && <button className="btn btn-sm btn-ghost btn-icon" onClick={onDismiss} aria-label={t("common.cancel")}>{I.x({ size: 12 })}</button>}
    </div>
  )
}
