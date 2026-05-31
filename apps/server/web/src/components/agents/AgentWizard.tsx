import { useState } from "react"
import { useTranslation } from "react-i18next"
import { I, osIcon } from "@/lib/icons"
import { serverApi, configApi, type GeneratedConfig } from "@/lib/api"
import { Modal } from "@/components/shell/Dialog"
import { FormBlock } from "@/components/shell/primitives"

type Platform = "linux" | "darwin" | "windows"

export function AgentWizard({ onClose }: { onClose: () => void }) {
  const { t } = useTranslation()
  const [step, setStep] = useState(1)
  const [platform, setPlatform] = useState<Platform>("linux")
  const [name, setName] = useState("")
  const [perm, setPerm] = useState(0)
  const [shell, setShell] = useState(false)
  const [tls, setTls] = useState(true)
  const [generating, setGenerating] = useState(false)
  const [config, setConfig] = useState<GeneratedConfig | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)

  async function generate() {
    setGenerating(true)
    setError(null)
    try {
      const info = await serverApi.info().catch(() => null)
      const data = await configApi.generate({
        serverUrl: info?.wsUrl || info?.serverUrl,
        permission: perm,
        tlsVerify: tls,
        hostname: name || undefined,
        shellEnabled: shell,
      })
      setConfig(data)
    } catch (e) {
      setError(typeof e === "object" && e && "error" in e ? String((e as { error: unknown }).error) : "failed")
    } finally {
      setGenerating(false)
    }
  }

  function next() {
    if (step === 2) {
      setStep(3)
      generate()
    } else setStep((s) => Math.min(3, s + 1))
  }

  const installCmd = config ? (platform === "windows" ? config.installCommandWindows : config.installCommandUnix) : ""

  const platforms: { k: Platform; label: string; sub: string }[] = [
    { k: "linux", label: "Linux", sub: "curl | bash" },
    { k: "darwin", label: "macOS", sub: "brew / pkg" },
    { k: "windows", label: "Windows", sub: "PowerShell / msi" },
  ]

  const footer = (
    <>
      {step > 1 && step < 3 && <button className="btn btn-sm" onClick={() => setStep((s) => s - 1)}>{I.back({ size: 13 })}<span>{t("wizard.back")}</span></button>}
      <div style={{ flex: 1 }} />
      <button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button>
      {step < 3 ? (
        <button className="btn btn-sm btn-primary" onClick={next}>{t("wizard.next")}{I.chev({ size: 13 })}</button>
      ) : (
        <button className="btn btn-sm btn-primary" onClick={onClose}>{I.check({ size: 13 })}<span>{t("wizard.done")}</span></button>
      )}
    </>
  )

  return (
    <Modal title={t("wizard.addAgent")} subtitle={`${t("wizard.step")} ${step} / 3`} onClose={onClose} width={640} footer={footer}>
      {/* step indicator */}
      <div className="row gap-2" style={{ marginBottom: 18 }}>
        {[1, 2, 3].map((s) => (
          <div key={s} className="row gap-2" style={{ alignItems: "center", flex: 1 }}>
            <div style={{ width: 22, height: 22, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11, fontWeight: 600, background: s <= step ? "var(--accent)" : "var(--panel-2)", color: s <= step ? "var(--accent-fg)" : "var(--fg-4)", border: "1px solid var(--border-2)" }}>{s < step ? "✓" : s}</div>
            {s < 3 && <div style={{ flex: 1, height: 1, background: s < step ? "var(--accent)" : "var(--border)" }} />}
          </div>
        ))}
      </div>

      {step === 1 && (
        <div className="col gap-3">
          <div className="muted" style={{ fontSize: 12 }}>{t("wizard.platformDescription")}</div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10 }}>
            {platforms.map((p) => (
              <button key={p.k} onClick={() => setPlatform(p.k)} className="card" style={{ padding: 16, display: "flex", flexDirection: "column", alignItems: "center", gap: 8, cursor: "pointer", background: platform === p.k ? "var(--panel-2)" : "var(--panel)", borderColor: platform === p.k ? "var(--border-strong)" : "var(--border)", color: "var(--fg)" }}>
                <span style={{ color: "var(--fg-3)" }}>{osIcon(p.k, 24)}</span>
                <span style={{ fontSize: 13, fontWeight: 500 }}>{p.label}</span>
                <span className="mono dim" style={{ fontSize: 10.5 }}>{p.sub}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {step === 2 && (
        <div className="col gap-4">
          <FormBlock label={t("wizard.agentName")} hint={t("wizard.agentNamePlaceholder")}>
            <input className="input" value={name} onChange={(e) => setName(e.target.value)} placeholder={t("wizard.agentNamePlaceholder")} autoFocus />
          </FormBlock>
          <FormBlock label={t("wizard.permissionLevel")}>
            <div className="col gap-2">
              {[0, 1, 2, 3].map((l) => (
                <button key={l} onClick={() => setPerm(l)} className="row gap-2" style={{ padding: "8px 12px", borderRadius: 6, cursor: "pointer", textAlign: "left", border: perm === l ? "1px solid var(--border-strong)" : "1px solid var(--border)", background: perm === l ? "var(--panel-2)" : "transparent", color: "var(--fg-2)", fontFamily: "inherit" }}>
                  <span className={`perm perm-${l}`}>L{l}</span>
                  <span style={{ fontSize: 12 }}>{t(`permission.l${l}`)}</span>
                  <span style={{ flex: 1 }} />
                  {perm === l && <span style={{ color: "var(--fg)" }}>{I.check({ size: 13 })}</span>}
                </button>
              ))}
            </div>
          </FormBlock>
          <FormBlock label={t("wizard.features")}>
            <div className="col gap-2">
              <label className="row gap-2" style={{ alignItems: "center", cursor: perm < 1 ? "not-allowed" : "pointer", fontSize: 12.5, opacity: perm < 1 ? 0.5 : 1 }}>
                <input type="checkbox" checked={shell} disabled={perm < 1} onChange={(e) => setShell(e.target.checked)} style={{ accentColor: "var(--fg)" }} />
                <span>{t("wizard.enableShell")}</span>
              </label>
              <label className="row gap-2" style={{ alignItems: "center", cursor: "pointer", fontSize: 12.5 }}>
                <input type="checkbox" checked={tls} onChange={(e) => setTls(e.target.checked)} style={{ accentColor: "var(--fg)" }} />
                <span>{t("wizard.enableTls")}</span>
              </label>
            </div>
          </FormBlock>
        </div>
      )}

      {step === 3 && (
        <div className="col gap-3">
          {generating ? (
            <div style={{ padding: 30, textAlign: "center", color: "var(--fg-4)" }}><span className="dot pulse ok" /> {t("wizard.generating")}</div>
          ) : error ? (
            <div className="badge crit" style={{ height: "auto", padding: 10 }}>{error}</div>
          ) : config ? (
            <>
              <div className="row gap-2" style={{ padding: "8px 10px", background: "rgba(245,158,11,.08)", border: "1px solid rgba(245,158,11,.25)", borderRadius: 6, fontSize: 11.5 }}>
                <span style={{ color: "var(--warn)" }}>{I.warn({ size: 13 })}</span>
                <span style={{ color: "var(--fg-2)" }}>{t("wizard.tokenWarning")}</span>
              </div>
              <FormBlock label={t("wizard.installCommand")}>
                <div className="code" style={{ whiteSpace: "pre-wrap", wordBreak: "break-all" }}>{installCmd}</div>
                <button className="btn btn-sm" style={{ alignSelf: "flex-start", marginTop: 6 }} onClick={() => { navigator.clipboard?.writeText(installCmd); setCopied(true); setTimeout(() => setCopied(false), 1500) }}>
                  {I.copy({ size: 12 })}<span>{copied ? t("wizard.copied") : t("wizard.copy")}</span>
                </button>
              </FormBlock>
              {config.generatedToken && (
                <FormBlock label="Token">
                  <div className="code" style={{ wordBreak: "break-all" }}>{config.generatedToken}</div>
                </FormBlock>
              )}
            </>
          ) : null}
        </div>
      )}
    </Modal>
  )
}
