import { useEffect, useState, type ReactNode } from "react"
import { useTranslation } from "react-i18next"
import { serverApi, authApi, settingsApi, llmSettingsApi, type ServerInfo, type LLMSettings, type LLMProvider } from "@/lib/api"
import { useAuth } from "@/contexts/AuthContext"
import { useSettings, type Tweaks } from "@/store/settings"
import { PageHeader, FormBlock, KVRow } from "@/components/shell/primitives"
import { I } from "@/lib/icons"

function Segmented<T extends string>({ value, options, onChange }: { value: T; options: { v: T; label: ReactNode }[]; onChange: (v: T) => void }) {
  return (
    <div className="row gap-1" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: 3, alignSelf: "flex-start" }}>
      {options.map((o) => (
        <button key={o.v} className="btn btn-sm" onClick={() => onChange(o.v)}
          style={{ height: 24, padding: "0 12px", background: value === o.v ? "var(--panel)" : "transparent", border: value === o.v ? "1px solid var(--border-2)" : "1px solid transparent", color: value === o.v ? "var(--fg)" : "var(--fg-4)" }}>
          {o.label}
        </button>
      ))}
    </div>
  )
}

function Section({ title, icon, children }: { title: ReactNode; icon: ReactNode; children: ReactNode }) {
  return (
    <div className="card" style={{ padding: 0 }}>
      <div className="row gap-2" style={{ padding: "12px 16px", borderBottom: "1px solid var(--border)", alignItems: "center", color: "var(--fg-2)" }}>
        <span style={{ color: "var(--fg-4)" }}>{icon}</span>
        <span style={{ fontSize: 12.5, fontWeight: 500 }}>{title}</span>
      </div>
      <div className="col" style={{ padding: 16, gap: 18 }}>{children}</div>
    </div>
  )
}

const ACCENTS = ["", "#22c55e", "#3b82f6", "#a78bfa", "#f97316", "#ef4444"]

type TabKey = "appearance" | "server" | "updates" | "ai"

export function SettingsScreen() {
  const { t } = useTranslation()
  const { tweaks, setTweak, lang, setLang } = useSettings()
  const { user } = useAuth()
  const [activeTab, setActiveTab] = useState<TabKey>("appearance")
  const [info, setInfo] = useState<ServerInfo | null>(null)
  const [cfg, setCfg] = useState<Record<string, string>>({})
  const [cfgStatus, setCfgStatus] = useState<"idle" | "busy" | "done" | "error">("idle")
  const [llm, setLLM] = useState<LLMSettings | null>(null)
  const [llmApiKey, setLLMApiKey] = useState("")
  const [llmStatus, setLLMStatus] = useState<"idle" | "busy" | "done" | "tested" | "error">("idle")

  // Version update state
  const [updateInfo, setUpdateInfo] = useState<any>(null)
  const [updateStatus, setUpdateStatus] = useState<"idle" | "checking" | "applying" | "done" | "error">("idle")
  const [updateError, setUpdateError] = useState("")

  useEffect(() => { serverApi.info().then(setInfo).catch(() => {}) }, [])
  useEffect(() => { settingsApi.get().then(setCfg).catch(() => {}) }, [])
  useEffect(() => { llmSettingsApi.get().then(setLLM).catch(() => {}) }, [])

  const setCfgVal = (k: string, v: string) => { setCfg((c) => ({ ...c, [k]: v })); setCfgStatus("idle") }
  async function saveSettings() {
    setCfgStatus("busy")
    try {
      const next = await settingsApi.update(cfg)
      setCfg(next)
      setCfgStatus("done")
    } catch {
      setCfgStatus("error")
    }
  }

  const llmPayload = (value: LLMSettings) => ({
    enabled: value.enabled,
    provider: value.provider,
    model: value.model,
    baseUrl: value.baseUrl,
    maxTokens: value.maxTokens,
  })

  async function saveLLM(testAfterSave = false) {
    if (!llm) return
    setLLMStatus("busy")
    try {
      const next = await llmSettingsApi.update({
        ...llmPayload(llm),
        ...(llmApiKey.trim() ? { apiKey: llmApiKey.trim() } : {}),
      })
      setLLM(next)
      setLLMApiKey("")
      if (testAfterSave) {
        await llmSettingsApi.test()
        setLLMStatus("tested")
      } else {
        setLLMStatus("done")
      }
    } catch {
      setLLMStatus("error")
    }
  }

  async function clearLLMApiKey() {
    if (!llm) return
    setLLMStatus("busy")
    try {
      const next = await llmSettingsApi.update({ ...llmPayload(llm), clearApiKey: true })
      setLLM(next)
      setLLMApiKey("")
      setLLMStatus("done")
    } catch {
      setLLMStatus("error")
    }
  }

  async function checkForUpdates() {
    setUpdateStatus("checking")
    setUpdateError("")
    try {
      const res = await fetch("/api/version/check?refresh=true")
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      setUpdateInfo(data)
      setUpdateStatus("idle")
    } catch (err) {
      setUpdateError(String(err))
      setUpdateStatus("error")
    }
  }

  async function applyUpdate() {
    if (!updateInfo?.updateAvailable) return
    setUpdateStatus("applying")
    setUpdateError("")
    try {
      const res = await fetch("/api/version/apply", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ version: updateInfo.latest.version }),
      })
      if (!res.ok) {
        const errorData = await res.json().catch(() => ({}))
        throw new Error(errorData.error || `HTTP ${res.status}`)
      }
      setUpdateStatus("done")
      setTimeout(() => window.location.reload(), 3000)
    } catch (err) {
      setUpdateError(String(err))
      setUpdateStatus("error")
    }
  }

  useEffect(() => {
    if (activeTab === "updates" && !updateInfo) {
      checkForUpdates()
    }
  }, [activeTab])

  const set = (k: keyof Tweaks, v: string) => setTweak(k, v as never)

  const tabs: { key: TabKey; label: string; icon: ReactNode }[] = [
    { key: "appearance", label: t("plat.appearance"), icon: I.settings({ size: 13 }) },
    { key: "server", label: t("plat.server"), icon: I.dashboard({ size: 13 }) },
    { key: "updates", label: t("plat.serverUpdate"), icon: I.download({ size: 13 }) },
    { key: "ai", label: t("plat.aiProvider"), icon: I.sparkle({ size: 13 }) },
  ]

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader title={t("nav.settings")} subtitle={t("plat.settingsSubtitle")} />

      {/* Tabs */}
      <div style={{ padding: "0 24px", borderBottom: "1px solid var(--border)" }}>
        <div className="row gap-1">
          {tabs.map((tab) => (
            <button
              key={tab.key}
              onClick={() => setActiveTab(tab.key)}
              className="row gap-2"
              style={{
                appearance: "none",
                border: "none",
                background: "transparent",
                padding: "10px 14px",
                cursor: "pointer",
                fontFamily: "inherit",
                fontSize: 13,
                color: activeTab === tab.key ? "var(--fg)" : "var(--fg-3)",
                fontWeight: activeTab === tab.key ? 500 : 400,
                borderBottom: activeTab === tab.key ? "2px solid var(--accent)" : "2px solid transparent",
                alignItems: "center",
              }}
            >
              <span style={{ color: activeTab === tab.key ? "var(--accent)" : "var(--fg-4)" }}>
                {tab.icon}
              </span>
              <span>{tab.label}</span>
            </button>
          ))}
        </div>
      </div>

      <div style={{ padding: 24, overflow: "auto", flex: 1 }}>
        {/* Appearance Tab */}
        {activeTab === "appearance" && (
          <div className="col gap-16" style={{ maxWidth: 700 }}>
            <Section title={t("plat.appearance")} icon={I.settings({ size: 13 })}>
              <FormBlock label={t("plat.theme")}>
                <Segmented value={tweaks.theme} onChange={(v) => set("theme", v)} options={[{ v: "dark", label: t("plat.dark") }, { v: "light", label: t("plat.light") }]} />
              </FormBlock>
              <FormBlock label={t("plat.density")}>
                <Segmented value={tweaks.density} onChange={(v) => set("density", v)} options={[{ v: "compact", label: t("plat.compact") }, { v: "regular", label: t("plat.regular") }, { v: "comfy", label: t("plat.comfy") }]} />
              </FormBlock>
              <FormBlock label={t("plat.fontFamily")}>
                <Segmented value={tweaks.font} onChange={(v) => set("font", v)} options={[
                  { v: "sans", label: t("plat.sans") },
                  { v: "mono", label: t("plat.mono") },
                  { v: "serif", label: t("plat.serif") },
                  { v: "system", label: t("plat.system") }
                ]} />
              </FormBlock>
              <FormBlock label={t("plat.fontWeight")}>
                <Segmented value={tweaks.fontWeight} onChange={(v) => set("fontWeight", v)} options={[
                  { v: "300", label: t("plat.light") },
                  { v: "400", label: t("plat.regular") },
                  { v: "500", label: t("plat.medium") },
                  { v: "600", label: t("plat.semibold") },
                  { v: "700", label: t("plat.bold") }
                ]} />
              </FormBlock>
              <FormBlock label={t("plat.fontSize")}>
                <Segmented value={tweaks.fontSize} onChange={(v) => set("fontSize", v)} options={[
                  { v: "small", label: t("plat.small") },
                  { v: "medium", label: t("plat.medium") },
                  { v: "large", label: t("plat.large") }
                ]} />
              </FormBlock>
              <FormBlock label={t("plat.cardStyle")}>
                <Segmented value={tweaks.card} onChange={(v) => set("card", v)} options={[{ v: "elevated", label: t("plat.elevated") }, { v: "outlined", label: t("plat.outlined") }, { v: "flat", label: t("plat.flat") }]} />
              </FormBlock>
              <FormBlock label={t("plat.accent")}>
                <div className="row gap-2">
                  {ACCENTS.map((a) => (
                    <button key={a || "default"} onClick={() => setTweak("accent", a)} title={a || t("plat.accentDefault")}
                      style={{ width: 26, height: 26, borderRadius: 6, cursor: "pointer", background: a || "linear-gradient(135deg,var(--fg),var(--fg-4))", border: tweaks.accent === a ? "2px solid var(--fg)" : "1px solid var(--border-2)" }} />
                  ))}
                </div>
              </FormBlock>
              <FormBlock label={t("plat.language")}>
                <Segmented value={lang} onChange={(v) => setLang(v)} options={[{ v: "en", label: "EN" }, { v: "zh", label: "中文" }]} />
              </FormBlock>
            </Section>
          </div>
        )}

        {/* Server Tab */}
        {activeTab === "server" && (
          <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)", gap: 16, alignItems: "start" }}>
            <Section title={t("plat.server")} icon={I.dashboard({ size: 13 })}>
              <KVRow label={t("plat.serverName")} value={info?.serverName || "NanoOps"} />
              <KVRow label={t("plat.version")} value={info?.version ? `v${info.version}` : "—"} />
              {info?.serverUrl && <KVRow label="URL" value={info.serverUrl} />}
              {info?.grpcPort && (
                <>
                  <KVRow label="gRPC" value={String(info.grpcPort)} />
                  <KVRow label={t("plat.grpcVersion")} value="v1.60.0" />
                </>
              )}
              {(info?.retentionDays != null || info?.dailyRetentionDays != null) && (
                <FormBlock label={t("plat.metricRetention")}>
                  <div className="row gap-2" style={{ flexWrap: "wrap" }}>
                    <span className="badge mono">{t("plat.rawData")} {info?.retentionDays ?? "—"}{t("plat.days")}</span>
                    <span className="badge mono">{t("plat.hourlyData")} {info?.hourlyRetentionDays ?? "—"}{t("plat.days")}</span>
                    <span className="badge mono">{t("plat.dailyData")} {info?.dailyRetentionDays ?? "—"}{t("plat.days")}</span>
                  </div>
                </FormBlock>
              )}
              {info?.tlsEnabled != null && (
                <KVRow label={t("plat.tls")} value={<span className={`badge ${info.tlsEnabled ? "ok" : "warn"}`}>{info.tlsEnabled ? t("plat.tlsOn") : t("plat.tlsOff")}</span>} />
              )}
              <div className="hint">{t("plat.configReadOnly")}</div>
            </Section>

            <Section title={t("plat.serverSettings")} icon={I.settings({ size: 13 })}>
              <FormBlock label={t("plat.serverName")}>
                <input className="input" value={cfg.serverName ?? ""} onChange={(e) => setCfgVal("serverName", e.target.value)} placeholder="NanoOps" />
              </FormBlock>
              <FormBlock label={t("plat.grpcPort")}>
                <input className="input" type="number" value={cfg.grpcPort ?? "39100"} onChange={(e) => setCfgVal("grpcPort", e.target.value)} placeholder="39100" />
              </FormBlock>
              <FormBlock label={t("plat.agentAutoUpdate")}>
                <Segmented value={(cfg.agentAutoUpdate as "enabled" | "manual") || "manual"} onChange={(v) => setCfgVal("agentAutoUpdate", v)} options={[{ v: "enabled", label: t("plat.autoUpdateOn") }, { v: "manual", label: t("plat.autoUpdateManual") }]} />
              </FormBlock>
              <div className="row gap-2" style={{ alignItems: "center" }}>
                <button className="btn btn-sm btn-primary" onClick={saveSettings} disabled={cfgStatus === "busy"}>{cfgStatus === "busy" && <span className="dot pulse ok" />}{t("common.save")}</button>
                {cfgStatus === "done" && <span className="badge ok">{t("plat.settingsSaved")}</span>}
                {cfgStatus === "error" && <span className="badge crit">{t("common.error")}</span>}
              </div>
            </Section>
          </div>
        )}

        {/* Updates Tab */}
        {activeTab === "updates" && (
          <div className="col gap-16" style={{ maxWidth: 700 }}>
            <Section title={t("plat.serverUpdate")} icon={I.download({ size: 13 })}>
              <FormBlock label={t("plat.currentVersion")}>
                <div className="row gap-2" style={{ alignItems: "center" }}>
                  <span className="mono badge" style={{ fontSize: 13 }}>v{info?.version || "—"}</span>
                </div>
              </FormBlock>

              {updateInfo && (
                <>
                  <FormBlock label={t("plat.latestVersion")}>
                    <div className="row gap-2" style={{ alignItems: "center" }}>
                      <span className="mono badge" style={{ fontSize: 13 }}>v{updateInfo.latest?.version || "—"}</span>
                      {updateInfo.updateAvailable && (
                        <span className="badge ok">{t("plat.updateAvailable")}</span>
                      )}
                      {!updateInfo.updateAvailable && updateStatus !== "checking" && (
                        <span className="badge">{t("plat.upToDate")}</span>
                      )}
                    </div>
                  </FormBlock>

                  {updateInfo.blocker && (
                    <div className="hint" style={{ color: "var(--warn)" }}>
                      {updateInfo.blocker}
                    </div>
                  )}
                </>
              )}

              <div className="row gap-2" style={{ alignItems: "center", flexWrap: "wrap" }}>
                <button
                  className="btn btn-sm"
                  onClick={checkForUpdates}
                  disabled={updateStatus === "checking" || updateStatus === "applying"}
                >
                  {updateStatus === "checking" && <span className="dot pulse ok" />}
                  {updateStatus === "checking" ? t("plat.checking") : t("plat.checkForUpdates")}
                </button>

                {updateInfo?.updateAvailable && !updateInfo.blocker && (
                  <button
                    className="btn btn-sm btn-primary"
                    onClick={applyUpdate}
                    disabled={updateStatus === "applying"}
                  >
                    {updateStatus === "applying" && <span className="dot pulse ok" />}
                    {updateStatus === "applying" ? t("plat.applying") : t("plat.applyUpdate")}
                  </button>
                )}

                {updateStatus === "done" && (
                  <span className="badge ok">{t("plat.updateSuccess")}</span>
                )}
                {updateStatus === "error" && (
                  <span className="badge crit">{updateError || t("plat.updateFailed")}</span>
                )}
              </div>

              <div className="hint">
                {t("plat.updateNotice")}
              </div>
            </Section>
          </div>
        )}

        {/* AI Tab */}
        {activeTab === "ai" && llm && (
          <div className="col gap-16" style={{ maxWidth: 700 }}>
            <Section title={t("plat.aiProvider")} icon={I.sparkle({ size: 13 })}>
              <FormBlock label={t("plat.aiAssistant")}>
                <Segmented
                  value={llm.enabled ? "enabled" : "disabled"}
                  onChange={(v) => { setLLM((current) => current ? { ...current, enabled: v === "enabled" } : current); setLLMStatus("idle") }}
                  options={[
                    { v: "enabled", label: t("plat.enabled") },
                    { v: "disabled", label: t("plat.disabled") },
                  ]}
                />
              </FormBlock>
              <FormBlock label={t("plat.aiProviderType")}>
                <select
                  className="input"
                  value={llm.provider}
                  onChange={(e) => { setLLM({ ...llm, provider: e.target.value as LLMProvider }); setLLMStatus("idle") }}
                >
                  <option value="anthropic">Anthropic</option>
                  <option value="openai">OpenAI</option>
                  <option value="openai-compatible">{t("plat.openAICompatible")}</option>
                </select>
              </FormBlock>
              <FormBlock label={t("plat.aiModel")}>
                <input
                  className="input mono"
                  value={llm.model}
                  onChange={(e) => { setLLM({ ...llm, model: e.target.value }); setLLMStatus("idle") }}
                  placeholder={llm.provider === "anthropic" ? "claude-sonnet-4-5" : "gpt-5"}
                />
              </FormBlock>
              <FormBlock label={t("plat.aiBaseUrl")}>
                <input
                  className="input mono"
                  value={llm.baseUrl}
                  onChange={(e) => { setLLM({ ...llm, baseUrl: e.target.value }); setLLMStatus("idle") }}
                  placeholder={llm.provider === "anthropic" ? "https://api.anthropic.com" : "https://api.openai.com"}
                />
                <div className="hint" style={{ marginTop: 6 }}>{t("plat.aiBaseUrlHint")}</div>
              </FormBlock>
              <FormBlock label="API Key">
                <input
                  className="input mono"
                  type="password"
                  autoComplete="new-password"
                  value={llmApiKey}
                  onChange={(e) => { setLLMApiKey(e.target.value); setLLMStatus("idle") }}
                  placeholder={llm.apiKeyConfigured ? t("plat.apiKeyConfigured") : t("plat.apiKeyPlaceholder")}
                />
                <div className="row gap-2" style={{ marginTop: 6, flexWrap: "wrap", alignItems: "center" }}>
                  <span className={`badge ${llm.apiKeyConfigured ? "ok" : "warn"}`}>
                    {llm.apiKeyConfigured ? t("plat.apiKeyConfigured") : t("plat.apiKeyMissing")}
                  </span>
                  {llm.apiKeyConfigured && <span className="badge mono">{llm.apiKeySource === "stored" ? t("plat.apiKeyStored") : t("plat.apiKeyEnvironment")}</span>}
                </div>
              </FormBlock>
              <FormBlock label={t("plat.aiMaxTokens")}>
                <input
                  className="input mono"
                  type="number"
                  min={1}
                  max={65536}
                  value={llm.maxTokens}
                  onChange={(e) => { setLLM({ ...llm, maxTokens: Number(e.target.value) }); setLLMStatus("idle") }}
                />
              </FormBlock>
              <div className="row gap-2" style={{ alignItems: "center", flexWrap: "wrap" }}>
                <button className="btn btn-sm btn-primary" onClick={() => saveLLM(false)} disabled={llmStatus === "busy"}>
                  {llmStatus === "busy" && <span className="dot pulse ok" />}{t("common.save")}
                </button>
                <button className="btn btn-sm" onClick={() => saveLLM(true)} disabled={llmStatus === "busy" || (!llm.apiKeyConfigured && !llmApiKey.trim()) || !llm.model.trim()}>
                  {t("plat.saveAndTest")}
                </button>
                {llm.apiKeyConfigured && llm.apiKeySource === "stored" && (
                  <button className="btn btn-sm btn-ghost" onClick={clearLLMApiKey} disabled={llmStatus === "busy"}>{t("plat.removeApiKey")}</button>
                )}
                {llmStatus === "done" && <span className="badge ok">{t("plat.settingsSaved")}</span>}
                {llmStatus === "tested" && <span className="badge ok">{t("plat.connectionSucceeded")}</span>}
                {llmStatus === "error" && <span className="badge crit">{t("plat.connectionOrSaveFailed")}</span>}
              </div>
            </Section>
          </div>
        )}
      </div>
    </div>
  )
}
