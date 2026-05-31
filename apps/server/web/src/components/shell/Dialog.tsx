import type { ReactNode } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"

export function Modal({ title, subtitle, onClose, footer, children, width = 520 }: { title: ReactNode; subtitle?: ReactNode; onClose: () => void; footer?: ReactNode; children: ReactNode; width?: number }) {
  return (
    <div className="scrim" onClick={onClose}>
      <div className="dialog" style={{ width }} onClick={(e) => e.stopPropagation()}>
        <div className="dialog-hd">
          <div className="col" style={{ gap: 2 }}>
            <div style={{ fontSize: 14, fontWeight: 500 }}>{title}</div>
            {subtitle && <div className="muted" style={{ fontSize: 11.5 }}>{subtitle}</div>}
          </div>
          <button className="btn btn-ghost btn-icon btn-sm" onClick={onClose}>{I.x({ size: 14 })}</button>
        </div>
        <div className="dialog-bd">{children}</div>
        {footer && <div className="dialog-ft">{footer}</div>}
      </div>
    </div>
  )
}

export function ConfirmDialog({ title, message, danger, confirmLabel, onConfirm, onClose, busy }: { title: ReactNode; message: ReactNode; danger?: boolean; confirmLabel?: ReactNode; onConfirm: () => void; onClose: () => void; busy?: boolean }) {
  const { t } = useTranslation()
  return (
    <Modal
      title={title}
      onClose={onClose}
      width={420}
      footer={
        <>
          <button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button>
          <button className={`btn btn-sm ${danger ? "btn-danger" : "btn-primary"}`} onClick={onConfirm} disabled={busy}>
            {busy && <span className="dot pulse ok" />}
            {confirmLabel ?? t("common.confirm")}
          </button>
        </>
      }
    >
      <div className="muted" style={{ fontSize: 12.5, lineHeight: 1.5 }}>{message}</div>
    </Modal>
  )
}
