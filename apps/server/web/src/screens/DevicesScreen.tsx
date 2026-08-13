import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { QRCodeSVG } from "qrcode.react"
import { I } from "@/lib/icons"
import { devicesApi, type DeviceToken, type DevicePairing } from "@/lib/api"
import { PageHeader, Perm, EmptyState, FormBlock } from "@/components/shell/primitives"
import { Modal, ConfirmDialog } from "@/components/shell/Dialog"
import { useRouter } from "@/store/router"
import { timeAgo } from "@/lib/format"

export function DevicesScreen() {
  const { t } = useTranslation()
  const { route, setRoute } = useRouter()
  const [devices, setDevices] = useState<DeviceToken[]>([])
  const [loading, setLoading] = useState(true)
  const [pairing, setPairing] = useState(false)
  const [editing, setEditing] = useState<DeviceToken | null>(null)
  const [deleting, setDeleting] = useState<DeviceToken | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try { setDevices(await devicesApi.list()) } catch { setDevices([]) } finally { setLoading(false) }
  }, [])
  useEffect(() => { load() }, [load])

  useEffect(() => {
    if (route.openPair) { setPairing(true); setRoute({ ...route, openPair: false }) }
  }, [route, setRoute])

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader
        title={t("nav.devices")}
        subtitle={t("acc.devicesSubtitle")}
        actions={<button className="btn btn-sm btn-primary" onClick={() => setPairing(true)}>{I.qr({ size: 13 })}<span>{t("acc.generatePairing")}</span></button>}
      />
      <div style={{ padding: "0 24px 24px", overflow: "auto", flex: 1 }}>
        {loading && devices.length === 0 ? (
          <div style={{ padding: 40, textAlign: "center", color: "var(--fg-4)", fontSize: 12.5 }}>{t("common.loading")}</div>
        ) : (
          <div className="auto-card-grid-280" style={{ gap: 12 }}>
            {devices.map((d) => (
              <div key={d.id} className="card" style={{ padding: 14, opacity: d.isActive ? 1 : 0.55 }}>
                <div className="row" style={{ justifyContent: "space-between", marginBottom: 10 }}>
                  <div className="row gap-2" style={{ alignItems: "center", minWidth: 0 }}>
                    <div style={{ width: 32, height: 32, borderRadius: 6, background: "var(--panel-2)", border: "1px solid var(--border)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--fg-3)" }}>
                      {d.deviceType === "desktop" ? I.dashboard({ size: 16 }) : I.device({ size: 16 })}
                    </div>
                    <div className="col" style={{ gap: 1, minWidth: 0 }}>
                      <div className="truncate" style={{ fontSize: 12.5, fontWeight: 500 }}>{d.deviceName}</div>
                      <div className="dim mono" style={{ fontSize: 10.5 }}>{d.deviceType} · {d.deviceOs}</div>
                    </div>
                  </div>
                </div>
                <div className="hr" />
                <div className="col" style={{ gap: 6, fontSize: 11.5 }}>
                  <div className="row" style={{ justifyContent: "space-between" }}><span className="muted">{t("acc.permission")}</span><Perm level={d.permissionLevel} /></div>
                  <div className="row" style={{ justifyContent: "space-between" }}><span className="muted">{t("acc.status")}</span><span className={`badge ${d.isActive ? "ok" : ""}`}>{d.isActive ? t("acc.enabled") : t("acc.disabled")}</span></div>
                  <div className="row" style={{ justifyContent: "space-between" }}><span className="muted">{t("acc.lastIp")}</span><span className="mono">{d.lastIp || "—"}</span></div>
                  <div className="row" style={{ justifyContent: "space-between" }}><span className="muted">{t("acc.lastUsed")}</span><span>{d.lastUsedAt ? timeAgo(Number(d.lastUsedAt)) : "—"}</span></div>
                </div>
                <div className="hr" />
                <div className="row gap-2">
                  <button className="btn btn-sm btn-ghost" style={{ flex: 1 }} onClick={() => setEditing(d)}>{I.edit({ size: 12 })}<span>{t("common.edit")}</span></button>
                  <button className="btn btn-sm btn-ghost btn-icon" onClick={() => setDeleting(d)}><span style={{ color: "var(--crit)" }}>{I.trash({ size: 12 })}</span></button>
                </div>
              </div>
            ))}
            <button onClick={() => setPairing(true)} className="card" style={{ padding: 14, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 8, minHeight: 200, cursor: "pointer", color: "var(--fg-3)", background: "transparent", borderStyle: "dashed" }}>
              {I.qr({ size: 28 })}
              <div style={{ fontSize: 12.5, fontWeight: 500 }}>{t("acc.pairNew")}</div>
              <div className="dim" style={{ fontSize: 11, textAlign: "center" }}>{t("acc.qrOr6")}</div>
            </button>
          </div>
        )}
        {!loading && devices.length === 0 && (
          <div style={{ marginTop: 16 }}>
            <EmptyState icon={I.device({ size: 28 })} title={t("nav.devices")} desc={t("acc.devicesSubtitle")} />
          </div>
        )}
      </div>

      {pairing && <PairingModal onClose={() => { setPairing(false); load() }} />}
      {editing && <DeviceEditor device={editing} onClose={() => setEditing(null)} onDone={() => { setEditing(null); load() }} />}
      {deleting && (
        <ConfirmDialog title={t("common.delete")} danger message={t("acc.deleteDeviceConfirm", { name: deleting.deviceName })} confirmLabel={t("common.delete")} onClose={() => setDeleting(null)} onConfirm={async () => { await devicesApi.delete(deleting.id); setDeleting(null); load() }} />
      )}
    </div>
  )
}

function PairingModal({ onClose }: { onClose: () => void }) {
  const { t } = useTranslation()
  const [data, setData] = useState<DevicePairing | null>(null)
  const [seconds, setSeconds] = useState(60)
  const [error, setError] = useState(false)

  const generate = useCallback(async () => {
    setError(false)
    try {
      const r = await devicesApi.createToken()
      setData(r)
      setSeconds(60)
    } catch {
      setError(true)
    }
  }, [])

  useEffect(() => { generate() }, [generate])
  useEffect(() => {
    if (!data) return
    const id = setInterval(() => setSeconds((s) => Math.max(0, s - 1)), 1000)
    return () => clearInterval(id)
  }, [data])

  const code = data?.pairingCode || "------"
  const codeFmt = code.length === 6 ? `${code.slice(0, 3)}-${code.slice(3)}` : code

  return (
    <Modal
      title={t("acc.pairNew")}
      subtitle={t("acc.qrOr6")}
      onClose={onClose}
      width={480}
      footer={
        <>
          <button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button>
          <button className="btn btn-sm" onClick={() => navigator.clipboard?.writeText(code)}>{I.copy({ size: 13 })}<span>{t("acc.pairingCode")}</span></button>
          <button className="btn btn-sm btn-primary" onClick={generate}>{I.refresh({ size: 13 })}<span>{t("acc.regenerate")}</span></button>
        </>
      }
    >
      {error ? (
        <div className="badge crit" style={{ height: "auto", padding: "10px" }}>{t("mon.requestFailed")}</div>
      ) : (
        <div className="row gap-4" style={{ alignItems: "center" }}>
          <div style={{ padding: 10, background: "#fff", borderRadius: 8 }}>
            {data?.qrData ? <QRCodeSVG value={data.qrData} size={132} /> : <div style={{ width: 132, height: 132 }} className="skeleton" />}
          </div>
          <div className="col gap-3" style={{ flex: 1 }}>
            <div className="col" style={{ gap: 2 }}>
              <div className="upper" style={{ color: "var(--fg-4)" }}>{t("acc.pairingCode")}</div>
              <div className="num mono" style={{ fontSize: 30, fontWeight: 600, letterSpacing: "0.06em" }}>{codeFmt.toUpperCase()}</div>
            </div>
            <div className="mono num" style={{ fontSize: 13, color: seconds <= 10 ? "var(--crit)" : "var(--fg-3)" }}>{t("acc.expiresIn", { s: seconds })}</div>
            <div className="meter"><div className="meter-fill" style={{ width: `${(seconds / 60) * 100}%`, background: seconds <= 10 ? "var(--crit)" : "var(--fg-2)" }} /></div>
          </div>
        </div>
      )}
    </Modal>
  )
}

function DeviceEditor({ device, onClose, onDone }: { device: DeviceToken; onClose: () => void; onDone: () => void }) {
  const { t } = useTranslation()
  const [name, setName] = useState(device.deviceName)
  const [perm, setPerm] = useState(device.permissionLevel)
  const [active, setActive] = useState(device.isActive)
  const [busy, setBusy] = useState(false)

  async function submit() {
    setBusy(true)
    try {
      await devicesApi.update(device.id, { deviceName: name, permissionLevel: perm, isActive: active })
      onDone()
    } finally { setBusy(false) }
  }

  return (
    <Modal title={t("common.edit")} onClose={onClose} footer={<><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-sm btn-primary" onClick={submit} disabled={busy}>{busy && <span className="dot pulse ok" />}{t("common.save")}</button></>}>
      <div className="col gap-4">
        <FormBlock label={t("acc.deviceName")}><input className="input" value={name} onChange={(e) => setName(e.target.value)} /></FormBlock>
        <FormBlock label={t("acc.permission")}>
          <select className="select" value={perm} onChange={(e) => setPerm(Number(e.target.value))}>
            {[0, 1, 2, 3].map((l) => <option key={l} value={l}>L{l} · {t(`permission.l${l}`)}</option>)}
          </select>
        </FormBlock>
        <label className="row gap-2" style={{ alignItems: "center", cursor: "pointer", fontSize: 12.5 }}>
          <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} style={{ accentColor: "var(--fg)" }} />
          <span>{t("acc.active")}</span>
        </label>
      </div>
    </Modal>
  )
}
