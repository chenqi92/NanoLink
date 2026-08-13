import { useEffect, useId, useRef, type ReactNode } from "react"
import { createPortal } from "react-dom"
import { I } from "@/lib/icons"

const focusableSelector = [
  "button:not([disabled])",
  "a[href]",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  '[tabindex]:not([tabindex="-1"])',
].join(",")

export function Drawer({
  open,
  title,
  closeLabel,
  side = "right",
  width = 360,
  onClose,
  children,
  className = "",
}: {
  open: boolean
  title: ReactNode
  closeLabel: string
  side?: "left" | "right"
  width?: number
  onClose: () => void
  children: ReactNode
  className?: string
}) {
  const titleId = useId()
  const panelRef = useRef<HTMLDivElement>(null)
  const restoreFocusRef = useRef<HTMLElement | null>(null)

  useEffect(() => {
    if (!open) return

    restoreFocusRef.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    const panel = panelRef.current
    const focusables = panel?.querySelectorAll<HTMLElement>(focusableSelector)
    ;(focusables?.[0] ?? panel)?.focus()

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault()
        onClose()
        return
      }
      if (event.key !== "Tab" || !panel) return

      const items = Array.from(panel.querySelectorAll<HTMLElement>(focusableSelector))
      if (items.length === 0) {
        event.preventDefault()
        panel.focus()
        return
      }
      const first = items[0]
      const last = items[items.length - 1]
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }

    document.addEventListener("keydown", onKeyDown)
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.removeEventListener("keydown", onKeyDown)
      document.body.style.overflow = previousOverflow
      restoreFocusRef.current?.focus()
    }
  }, [onClose, open])

  if (!open) return null

  return createPortal(
    <div className="scrim drawer-scrim" onMouseDown={onClose}>
      <div
        ref={panelRef}
        className={`drawer drawer-${side} ${className}`.trim()}
        style={{ width: `min(${width}px, calc(100% - 24px))` }}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="drawer-header">
          <h2 id={titleId}>{title}</h2>
          <button className="btn btn-ghost btn-icon drawer-close" onClick={onClose} aria-label={closeLabel} title={closeLabel}>
            {I.x({ size: 15 })}
          </button>
        </div>
        <div className="drawer-content">{children}</div>
      </div>
    </div>,
    document.body,
  )
}
