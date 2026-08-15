import { useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { I, osIcon } from "@/lib/icons"
import {
  serverApi,
  configApi,
  type AgentArchitecture,
  type GeneratedConfig,
  type NASPackageManifest,
  type NASPlatform,
} from "@/lib/api"
import { Modal } from "@/components/shell/Dialog"
import { FormBlock } from "@/components/shell/primitives"
import "./agent-wizard.css"

type DesktopPlatform = "linux" | "darwin" | "windows"
type Platform = DesktopPlatform | NASPlatform

const NAS_PLATFORMS: NASPlatform[] = ["fnos", "synology", "ugos"]

function isNASPlatform(platform: Platform): platform is NASPlatform {
  return NAS_PLATFORMS.includes(platform as NASPlatform)
}

function splitEndpoint(endpoint: string, fallbackPort: number) {
  let value = endpoint.trim().replace(/^wss?:\/\//, "")
  value = value.split("/")[0]
  const bracketed = value.match(/^\[([^\]]+)](?::(\d+))?$/)
  if (bracketed) return { host: bracketed[1], port: Number(bracketed[2] || fallbackPort) }
  if (value.split(":").length === 2) {
    const [host, port] = value.split(":")
    return { host, port: Number(port || fallbackPort) }
  }
  return { host: value, port: fallbackPort }
}

function joinEndpoint(host: string, port: string) {
  const cleanHost = host.trim().replace(/^\[|]$/g, "")
  return `${cleanHost.includes(":") ? `[${cleanHost}]` : cleanHost}:${port}`
}

function architectureLabel(architecture: AgentArchitecture, platform: Platform) {
  if (architecture === "x86_64") return "x86_64 / AMD64"
  if (platform === "darwin") return "ARM64 / Apple Silicon"
  if (platform === "synology") return "ARMv8 / ARM64"
  return "ARM64 / AArch64"
}

function desktopReleaseAsset(platform: DesktopPlatform, architecture: AgentArchitecture) {
  const releasePlatform = platform === "darwin" ? "macos" : platform
  const releaseArchitecture = architecture === "arm64" ? "aarch64" : "x86_64"
  const extension = platform === "windows" ? ".exe" : ""
  return `nanolink-agent-${releasePlatform}-${releaseArchitecture}${extension}`
}

function releaseAssetURL(releaseURL: string, filename: string) {
  const normalized = releaseURL.trim().replace(/\/+$/, "")
  if (!normalized) return ""

  const githubTag = normalized.match(/^(https:\/\/github\.com\/[^/]+\/[^/]+\/releases)\/tag\/([^/?#]+)$/)
  if (githubTag) return `${githubTag[1]}/download/${githubTag[2]}/${encodeURIComponent(filename)}`
  if (/^https:\/\/github\.com\/[^/]+\/[^/]+\/releases$/.test(normalized)) {
    return `${normalized}/latest/download/${encodeURIComponent(filename)}`
  }

  try {
    const base = new URL(`${normalized}/`)
    if (base.protocol !== "https:") return ""
    return new URL(filename, base).toString()
  } catch {
    return ""
  }
}

function NASMark({ platform }: { platform: NASPlatform }) {
  const label = platform === "fnos" ? "fn" : platform === "synology" ? "DSM" : "UG"
  return (
    <span
      className="mono"
      style={{
        width: 32,
        height: 32,
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        border: "1px solid var(--border-2)",
        borderRadius: 7,
        background: "var(--panel-3)",
        color: "var(--fg-2)",
        fontSize: platform === "synology" ? 9 : 11,
        fontWeight: 700,
        letterSpacing: "-0.03em",
      }}
    >
      {label}
    </span>
  )
}

export function AgentWizard({ onClose }: { onClose: () => void }) {
  const { t } = useTranslation()
  const [step, setStep] = useState(1)
  const [platform, setPlatform] = useState<Platform>("linux")
  const [architecture, setArchitecture] = useState<AgentArchitecture>("x86_64")
  const [name, setName] = useState("")
  const [perm, setPerm] = useState(0)
  const [shell, setShell] = useState(false)
  const [tls, setTls] = useState(true)
  const [tlsCaCert, setTlsCaCert] = useState("")
  const [tlsServerName, setTlsServerName] = useState("")
  const [tlsClientCert, setTlsClientCert] = useState("")
  const [tlsClientKey, setTlsClientKey] = useState("")
  const [serverHost, setServerHost] = useState("")
  const [serverPort, setServerPort] = useState("39100")
  const [serverVersion, setServerVersion] = useState("")
  const [agentReleaseURL, setAgentReleaseURL] = useState("")
  const [packageManifest, setPackageManifest] = useState<NASPackageManifest | null>(null)
  const [packageLoading, setPackageLoading] = useState(true)
  const [packageError, setPackageError] = useState(false)
  const [generating, setGenerating] = useState(false)
  const [config, setConfig] = useState<GeneratedConfig | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [copied, setCopied] = useState("")

  const isNAS = isNASPlatform(platform)
  const parsedPort = Number(serverPort)
  const connectionValid = serverHost.trim() !== "" && Number.isInteger(parsedPort) && parsedPort > 0 && parsedPort <= 65535
  const selectedPackage = isNAS
    ? packageManifest?.packages.find((pkg) => pkg.platform === platform && pkg.arch === architecture)
    : undefined
  const releaseURL = packageManifest?.releaseUrl
    || agentReleaseURL
    || (serverVersion ? `https://github.com/chenqi92/NanoLink/releases/tag/v${serverVersion}` : "https://github.com/chenqi92/NanoLink/releases")

  useEffect(() => {
    let active = true
    serverApi.info().then((info) => {
      if (!active) return
      const fallbackPort = info.grpcPort || 39100
      const endpoint = splitEndpoint(info.grpcUrl || info.wsUrl || info.serverUrl || "", fallbackPort)
      setServerHost(info.agentHost || endpoint.host)
      setServerPort(String(endpoint.port || fallbackPort))
      setServerVersion(info.version)
      setAgentReleaseURL(info.agentReleaseUrl || "")
      if (typeof info.tlsEnabled === "boolean") setTls(info.tlsEnabled)
    }).catch(() => undefined)

    configApi.nasPackages().then((manifest) => {
      if (!active) return
      setPackageManifest(manifest)
      setPackageError(false)
    }).catch(() => {
      if (active) setPackageError(true)
    }).finally(() => {
      if (active) setPackageLoading(false)
    })
    return () => { active = false }
  }, [])

  function choosePlatform(nextPlatform: Platform) {
    setPlatform(nextPlatform)
    if (isNASPlatform(nextPlatform)) {
      setPerm(0)
      setShell(false)
      setTlsCaCert("")
      setTlsServerName("")
      setTlsClientCert("")
      setTlsClientKey("")
    }
  }

  async function generate() {
    setGenerating(true)
    setError(null)
    const previousToken = config?.generatedToken
    try {
      let endpoint = connectionValid ? joinEndpoint(serverHost, serverPort) : ""
      if (!endpoint) {
        const info = await serverApi.info()
        endpoint = info.grpcUrl || info.wsUrl || info.serverUrl || ""
      }
      const data = await configApi.generate({
        serverUrl: endpoint,
        token: previousToken,
        permission: isNAS ? 0 : perm,
        tlsVerify: tls,
        hostname: name || undefined,
        shellEnabled: isNAS ? false : shell,
        tlsCaCert: tlsCaCert || undefined,
        tlsServerName: tlsServerName || undefined,
        tlsClientCert: tlsClientCert || undefined,
        tlsClientKey: tlsClientKey || undefined,
      })
      setConfig(previousToken && !data.generatedToken ? { ...data, generatedToken: previousToken } : data)
    } catch (e) {
      setError(typeof e === "object" && e && "error" in e ? String((e as { error: unknown }).error) : t("common.error"))
    } finally {
      setGenerating(false)
    }
  }

  function next() {
    if (step === 2) {
      setStep(3)
      void generate()
    } else {
      setStep((current) => Math.min(3, current + 1))
    }
  }

  async function copyValue(value: string, key: string) {
    await navigator.clipboard?.writeText(value)
    setCopied(key)
    window.setTimeout(() => setCopied(""), 1500)
  }

  const installCmd = config ? (platform === "windows" ? config.installCommandWindows : config.installCommandUnix) : ""
  const desktopPlatforms: { k: DesktopPlatform; label: string; sub: string }[] = [
    { k: "linux", label: "Linux", sub: "curl | bash" },
    { k: "darwin", label: "macOS", sub: "brew / pkg" },
    { k: "windows", label: "Windows", sub: "PowerShell / msi" },
  ]
  const nasPlatforms: { k: NASPlatform; label: string; sub: string }[] = [
    { k: "fnos", label: t("wizard.fnos"), sub: ".fpk" },
    { k: "synology", label: t("wizard.synology"), sub: "DSM 7 · .spk" },
    { k: "ugos", label: t("wizard.ugos"), sub: "UGOS Pro · .upk" },
  ]
  const archLabel = architectureLabel(architecture, platform)
  const desktopAsset = !isNAS ? desktopReleaseAsset(platform, architecture) : ""
  const desktopDownloadURL = desktopAsset ? releaseAssetURL(releaseURL, desktopAsset) : ""
  const desktopPlatformLabel = !isNAS
    ? desktopPlatforms.find((item) => item.k === platform)?.label || platform
    : ""

  const footer = (
    <>
      {step > 1 && (
        <button className="btn btn-sm" onClick={() => setStep((current) => current - 1)} disabled={generating}>
          {I.back({ size: 13 })}<span>{t("wizard.back")}</span>
        </button>
      )}
      <div style={{ flex: 1 }} />
      <button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button>
      {step < 3 ? (
        <button className="btn btn-sm btn-primary" onClick={next} disabled={step === 2 && isNAS && !connectionValid}>
          {t("wizard.next")}{I.chev({ size: 13 })}
        </button>
      ) : (
        <button className="btn btn-sm btn-primary" onClick={onClose}>{I.check({ size: 13 })}<span>{t("wizard.done")}</span></button>
      )}
    </>
  )

  return (
    <Modal title={t("wizard.addAgent")} subtitle={`${t("wizard.step")} ${step} / 3`} onClose={onClose} width={720} footer={footer}>
      <div className="row gap-2" style={{ marginBottom: 20 }} aria-label={`${t("wizard.step")} ${step} / 3`}>
        {[1, 2, 3].map((item) => (
          <div key={item} className="row gap-2" style={{ alignItems: "center", flex: 1 }}>
            <div style={{ width: 22, height: 22, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11, fontWeight: 600, background: item <= step ? "var(--accent)" : "var(--panel-2)", color: item <= step ? "var(--accent-fg)" : "var(--fg-4)", border: "1px solid var(--border-2)" }}>{item < step ? "✓" : item}</div>
            {item < 3 && <div style={{ flex: 1, height: 1, background: item < step ? "var(--accent)" : "var(--border)" }} />}
          </div>
        ))}
      </div>

      {step === 1 && (
        <div className="col gap-4">
          <div className="muted" style={{ fontSize: 12 }}>{t("wizard.platformDescription")}</div>
          <FormBlock label={t("wizard.standardSystems")}>
            <div className="agent-wizard-platform-grid">
              {desktopPlatforms.map((item) => (
                <button key={item.k} onClick={() => choosePlatform(item.k)} aria-pressed={platform === item.k} className="card" style={{ minHeight: 108, padding: 15, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 8, cursor: "pointer", background: platform === item.k ? "var(--panel-2)" : "var(--panel)", borderColor: platform === item.k ? "var(--border-strong)" : "var(--border)", color: "var(--fg)" }}>
                  <span style={{ color: "var(--fg-3)" }}>{osIcon(item.k, 24)}</span>
                  <span style={{ fontSize: 13, fontWeight: 500 }}>{item.label}</span>
                  <span className="mono dim" style={{ fontSize: 10.5 }}>{item.sub}</span>
                </button>
              ))}
            </div>
          </FormBlock>
          <FormBlock label={t("wizard.nativeNAS")} hint={t("wizard.nativeNASHint")}>
            <div className="agent-wizard-platform-grid">
              {nasPlatforms.map((item) => (
                <button key={item.k} onClick={() => choosePlatform(item.k)} aria-pressed={platform === item.k} className="card" style={{ minHeight: 108, padding: 15, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 8, cursor: "pointer", background: platform === item.k ? "var(--panel-2)" : "var(--panel)", borderColor: platform === item.k ? "var(--border-strong)" : "var(--border)", color: "var(--fg)", position: "relative" }}>
                  <span style={{ position: "absolute", top: 8, right: 8, fontSize: 9 }} className="badge ok">{t("wizard.readOnly")}</span>
                  <NASMark platform={item.k} />
                  <span style={{ fontSize: 13, fontWeight: 500 }}>{item.label}</span>
                  <span className="mono dim" style={{ fontSize: 10.5 }}>{item.sub}</span>
                </button>
              ))}
            </div>
          </FormBlock>
          <FormBlock label={t("wizard.processorArchitecture")} hint={t("wizard.architectureHint")}>
            <div className="row gap-2" style={{ flexWrap: "wrap" }}>
              {(["x86_64", "arm64"] as AgentArchitecture[]).map((arch) => (
                <button key={arch} className={`btn btn-sm ${architecture === arch ? "btn-primary" : ""}`} onClick={() => setArchitecture(arch)} aria-pressed={architecture === arch}>
                  {architectureLabel(arch, platform)}
                </button>
              ))}
            </div>
          </FormBlock>
        </div>
      )}

      {step === 2 && (
        <div className="col gap-4">
          <FormBlock label={t("wizard.agentName")} hint={t("wizard.agentNamePlaceholder")}>
            <input className="input" value={name} onChange={(event) => setName(event.target.value)} placeholder={t("wizard.agentNamePlaceholder")} autoFocus />
          </FormBlock>

          {isNAS ? (
            <>
              <FormBlock label={t("wizard.serverConnection")} hint={t("wizard.serverConnectionHint")}>
                <div className="card col gap-3" style={{ padding: 12, background: "var(--panel-2)" }}>
                  <div className="row gap-2" style={{ alignItems: "center", color: "var(--fg-3)", fontSize: 11.5 }}>
                    <span className={`dot ${connectionValid ? "ok" : "warn"}`} />
                    <span>{connectionValid ? t("wizard.serverDetected") : t("wizard.serverNeedsInput")}</span>
                    <span style={{ flex: 1 }} />
                    <span className="badge">gRPC</span>
                  </div>
                  <div className="agent-wizard-connection-grid">
                    <FormBlock label={t("wizard.serverAddress")}>
                      <input className="input mono" value={serverHost} onChange={(event) => setServerHost(event.target.value)} placeholder="nas.example.lan" />
                    </FormBlock>
                    <FormBlock label={t("wizard.serverPort")}>
                      <input className="input mono" inputMode="numeric" value={serverPort} onChange={(event) => setServerPort(event.target.value)} placeholder="39100" />
                    </FormBlock>
                  </div>
                  <label className="row gap-2" style={{ alignItems: "center", cursor: "pointer", fontSize: 12.5 }}>
                    <input type="checkbox" checked={tls} onChange={(event) => setTls(event.target.checked)} style={{ accentColor: "var(--fg)" }} />
                    <span>{t("wizard.enableTls")}</span>
                  </label>
                </div>
              </FormBlock>
              <div className="card row gap-3" style={{ padding: 12, alignItems: "flex-start", background: "rgba(34,197,94,.04)" }}>
                <span style={{ color: "var(--ok)", marginTop: 1 }}>{I.shield({ size: 16 })}</span>
                <div className="col gap-1">
                  <strong style={{ fontSize: 12.5, fontWeight: 500 }}>{t("wizard.nasReadOnlyTitle")}</strong>
                  <span className="muted" style={{ fontSize: 11.5, lineHeight: 1.55 }}>{t("wizard.nasReadOnlyDescription")}</span>
                </div>
              </div>
            </>
          ) : (
            <>
              <FormBlock label={t("wizard.permissionLevel")}>
                <div className="col gap-2">
                  {[0, 1, 2, 3].map((level) => (
                    <button key={level} onClick={() => setPerm(level)} className="row gap-2" style={{ padding: "8px 12px", borderRadius: 6, cursor: "pointer", textAlign: "left", border: perm === level ? "1px solid var(--border-strong)" : "1px solid var(--border)", background: perm === level ? "var(--panel-2)" : "transparent", color: "var(--fg-2)", fontFamily: "inherit" }}>
                      <span className={`perm perm-${level}`}>L{level}</span>
                      <span style={{ fontSize: 12 }}>{t(`permission.l${level}`)}</span>
                      <span style={{ flex: 1 }} />
                      {perm === level && <span style={{ color: "var(--fg)" }}>{I.check({ size: 13 })}</span>}
                    </button>
                  ))}
                </div>
              </FormBlock>
              <FormBlock label={t("wizard.features")}>
                <div className="col gap-2">
                  <label className="row gap-2" style={{ alignItems: "center", cursor: perm < 1 ? "not-allowed" : "pointer", fontSize: 12.5, opacity: perm < 1 ? 0.5 : 1 }}>
                    <input type="checkbox" checked={shell} disabled={perm < 1} onChange={(event) => setShell(event.target.checked)} style={{ accentColor: "var(--fg)" }} />
                    <span>{t("wizard.enableShell")}</span>
                  </label>
                  <label className="row gap-2" style={{ alignItems: "center", cursor: "pointer", fontSize: 12.5 }}>
                    <input type="checkbox" checked={tls} onChange={(event) => {
                      setTls(event.target.checked)
                      if (!event.target.checked) {
                        setTlsCaCert("")
                        setTlsServerName("")
                        setTlsClientCert("")
                        setTlsClientKey("")
                      }
                    }} style={{ accentColor: "var(--fg)" }} />
                    <span>{t("wizard.enableTls")}</span>
                  </label>
                  {tls && (
                    <details className="card" style={{ padding: "9px 11px", marginTop: 4 }}>
                      <summary style={{ cursor: "pointer", fontSize: 12, color: "var(--fg-2)" }}>{t("wizard.tlsAdvanced")}</summary>
                      <div className="col gap-2" style={{ marginTop: 10 }}>
                        <input className="input mono" value={tlsCaCert} onChange={(event) => setTlsCaCert(event.target.value)} placeholder={t("wizard.tlsCaCertPlaceholder")} />
                        <input className="input mono" value={tlsServerName} onChange={(event) => setTlsServerName(event.target.value)} placeholder={t("wizard.tlsServerNamePlaceholder")} />
                        <input className="input mono" value={tlsClientCert} onChange={(event) => setTlsClientCert(event.target.value)} placeholder={t("wizard.tlsClientCertPlaceholder")} />
                        <input className="input mono" value={tlsClientKey} onChange={(event) => setTlsClientKey(event.target.value)} placeholder={t("wizard.tlsClientKeyPlaceholder")} />
                        <span className="dim" style={{ fontSize: 10.5 }}>{t("wizard.tlsAdvancedHint")}</span>
                      </div>
                    </details>
                  )}
                </div>
              </FormBlock>
            </>
          )}
        </div>
      )}

      {step === 3 && (
        <div className="col gap-3">
          {generating ? (
            <div style={{ padding: 30, textAlign: "center", color: "var(--fg-4)" }}><span className="dot pulse ok" /> {t("wizard.generating")}</div>
          ) : error ? (
            <div className="col gap-2">
              <div className="badge crit" style={{ height: "auto", padding: 10 }}>{error}</div>
              <button className="btn btn-sm" style={{ alignSelf: "flex-start" }} onClick={() => void generate()}>{I.refresh({ size: 12 })}{t("wizard.retry")}</button>
            </div>
          ) : config && isNAS ? (
            <>
              <div className="row gap-2" style={{ padding: "9px 10px", background: "rgba(245,158,11,.08)", border: "1px solid rgba(245,158,11,.25)", borderRadius: 6, fontSize: 11.5, alignItems: "flex-start" }}>
                <span style={{ color: "var(--warn)", marginTop: 1 }}>{I.warn({ size: 13 })}</span>
                <span style={{ color: "var(--fg-2)", lineHeight: 1.5 }}>{t("wizard.signedPackageNotice")}</span>
              </div>

              <div className="card" style={{ padding: 14 }}>
                <div className="row gap-3 agent-wizard-package-header" style={{ alignItems: "center" }}>
                  <NASMark platform={platform} />
                  <div className="col gap-1" style={{ minWidth: 0 }}>
                    <div className="row gap-2" style={{ alignItems: "center", flexWrap: "wrap" }}>
                      <strong style={{ fontSize: 13, fontWeight: 500 }}>{t(`wizard.${platform}`)}</strong>
                      <span className="badge mono">{archLabel}</span>
                      {packageManifest?.version && <span className="badge mono">v{packageManifest.version}</span>}
                    </div>
                    <span className="mono dim truncate" style={{ fontSize: 10.5 }}>{selectedPackage?.filename || t("wizard.packageUnavailable")}</span>
                  </div>
                  <span style={{ flex: 1 }} />
                  {selectedPackage ? (
                    <a className="btn btn-sm btn-primary agent-wizard-package-action" href={selectedPackage.downloadUrl} target="_blank" rel="noreferrer">
                      {I.download({ size: 13 })}<span>{t("wizard.downloadPackage")}</span>
                    </a>
                  ) : (
                    <button className="btn btn-sm btn-primary agent-wizard-package-action" disabled>{packageLoading ? t("wizard.loadingPackage") : t("wizard.packageUnavailable")}</button>
                  )}
                </div>
                {(packageError || (!packageLoading && !selectedPackage)) && (
                  <div className="row gap-2" style={{ marginTop: 10, paddingTop: 10, borderTop: "1px solid var(--border)", alignItems: "center", fontSize: 11.5 }}>
                    <span className="muted">{t("wizard.packageSourceError")}</span>
                    <a href={releaseURL} target="_blank" rel="noreferrer" style={{ color: "var(--fg-2)" }}>{t("wizard.openRelease")}</a>
                  </div>
                )}
              </div>

              <FormBlock label={t("wizard.installParameters")} hint={t("wizard.installParametersHint")}>
                <div className="card col" style={{ overflow: "hidden" }}>
                  {[
                    { key: "host", label: t("wizard.serverAddress"), value: serverHost },
                    { key: "port", label: t("wizard.serverPort"), value: serverPort },
                    { key: "token", label: t("wizard.token"), value: config.generatedToken || "" },
                    { key: "tls", label: "TLS", value: tls ? "true" : "false" },
                    ...(name ? [{ key: "name", label: t("wizard.agentName"), value: name }] : []),
                  ].map((item, index) => (
                    <div key={item.key} className="row gap-3 agent-wizard-copy-row" style={{ minHeight: 42, padding: "8px 10px", alignItems: "center", borderTop: index ? "1px solid var(--border)" : "none" }}>
                      <span style={{ width: 96, flexShrink: 0, color: "var(--fg-4)", fontSize: 11.5 }}>{item.label}</span>
                      <code className="mono" style={{ flex: 1, minWidth: 0, color: "var(--fg-2)", fontSize: 11.5, wordBreak: "break-all" }}>{item.value}</code>
                      <button className="btn btn-ghost btn-icon btn-sm" onClick={() => void copyValue(item.value, item.key)} aria-label={`${t("wizard.copy")} ${item.label}`}>
                        {copied === item.key ? I.check({ size: 12 }) : I.copy({ size: 12 })}
                      </button>
                    </div>
                  ))}
                </div>
                <button className="btn btn-sm" style={{ alignSelf: "flex-start", marginTop: 7 }} onClick={() => void copyValue([
                  `${t("wizard.serverAddress")}: ${serverHost}`,
                  `${t("wizard.serverPort")}: ${serverPort}`,
                  `${t("wizard.token")}: ${config.generatedToken || ""}`,
                  `TLS: ${tls ? "true" : "false"}`,
                  ...(name ? [`${t("wizard.agentName")}: ${name}`] : []),
                ].join("\n"), "all")}>
                  {copied === "all" ? I.check({ size: 12 }) : I.copy({ size: 12 })}<span>{copied === "all" ? t("wizard.copied") : t("wizard.copyAll")}</span>
                </button>
              </FormBlock>

              <div className="card" style={{ padding: "11px 13px" }}>
                <div className="upper" style={{ color: "var(--fg-4)", marginBottom: 8 }}>{t("wizard.installSteps")}</div>
                <ol style={{ margin: 0, paddingLeft: 19, color: "var(--fg-3)", fontSize: 11.5, lineHeight: 1.8 }}>
                  <li>{t("wizard.installStepDownload")}</li>
                  <li>{t("wizard.installStepParameters")}</li>
                  <li>{t("wizard.installStepOnline")}</li>
                </ol>
              </div>
            </>
          ) : config ? (
            <>
              <div className="row gap-2" style={{ padding: "8px 10px", background: "rgba(245,158,11,.08)", border: "1px solid rgba(245,158,11,.25)", borderRadius: 6, fontSize: 11.5 }}>
                <span style={{ color: "var(--warn)" }}>{I.warn({ size: 13 })}</span>
                <span style={{ color: "var(--fg-2)" }}>{t("wizard.tokenWarning")}</span>
              </div>
              <div className="card" style={{ padding: 14 }}>
                <div className="row gap-3 agent-wizard-package-header" style={{ alignItems: "center" }}>
                  <span style={{ color: "var(--fg-3)" }}>{osIcon(platform as DesktopPlatform, 24)}</span>
                  <div className="col gap-1" style={{ minWidth: 0 }}>
                    <div className="row gap-2" style={{ alignItems: "center", flexWrap: "wrap" }}>
                      <strong style={{ fontSize: 13, fontWeight: 500 }}>{desktopPlatformLabel}</strong>
                      <span className="badge mono">{archLabel}</span>
                      {serverVersion && <span className="badge mono">v{serverVersion}</span>}
                    </div>
                    <span className="mono dim truncate" style={{ fontSize: 10.5 }}>{desktopAsset}</span>
                  </div>
                  <span style={{ flex: 1 }} />
                  {desktopDownloadURL ? (
                    <a className="btn btn-sm agent-wizard-package-action" href={desktopDownloadURL} target="_blank" rel="noreferrer">
                      {I.download({ size: 13 })}<span>{t("wizard.downloadBinary")}</span>
                    </a>
                  ) : (
                    <a className="btn btn-sm agent-wizard-package-action" href={releaseURL} target="_blank" rel="noreferrer">
                      <span>{t("wizard.openRelease")}</span>
                    </a>
                  )}
                </div>
              </div>
              <FormBlock label={t("wizard.installCommand")} hint={t("wizard.installerArchitectureHint")}>
                <div className="code" style={{ whiteSpace: "pre-wrap", wordBreak: "break-all" }}>{installCmd}</div>
                <button className="btn btn-sm" style={{ alignSelf: "flex-start", marginTop: 6 }} onClick={() => void copyValue(installCmd, "command")}>
                  {I.copy({ size: 12 })}<span>{copied === "command" ? t("wizard.copied") : t("wizard.copy")}</span>
                </button>
              </FormBlock>
              {config.generatedToken && (
                <FormBlock label={t("wizard.token")}>
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
