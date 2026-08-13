import { useCallback, useEffect, useState, type ReactNode } from "react"
import { useTranslation } from "react-i18next"
import { serverApi, settingsApi, llmSettingsApi, llmProfilesApi, versionApi, type ServerInfo, type ServerUpdateInfo, type LLMSettings, type LLMProvider, type LLMProfile, type ProviderInfo, type ProviderModel } from "@/lib/api"
import { useSettings, type Density, type Tweaks } from "@/store/settings"
import { PageHeader, FormBlock, KVRow } from "@/components/shell/primitives"
import { I } from "@/lib/icons"
import "./settings.css"

function Segmented<T extends string>({ value, options, onChange }: { value: T; options: { v: T; label: ReactNode }[]; onChange: (v: T) => void }) {
  return (
    <div className="settings-segmented" role="group">
      {options.map((o) => (
        <button
          key={o.v}
          type="button"
          className={`settings-segmented-option${value === o.v ? " is-active" : ""}`}
          aria-pressed={value === o.v}
          onClick={() => onChange(o.v)}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}

function Section({ title, icon, description, action, wide = false, children }: { title: ReactNode; icon: ReactNode; description?: ReactNode; action?: ReactNode; wide?: boolean; children: ReactNode }) {
  return (
    <section className={`card settings-section${wide ? " settings-section-wide" : ""}`}>
      <div className="settings-section-header">
        <div className="settings-section-heading">
          <span className="settings-section-icon">{icon}</span>
          <div>
            <h3>{title}</h3>
            {description && <p>{description}</p>}
          </div>
        </div>
        {action && <div className="settings-section-action">{action}</div>}
      </div>
      <div className="settings-section-body">{children}</div>
    </section>
  )
}

function ComponentSizePicker({ value, onChange, labels }: { value: Density; onChange: (value: Density) => void; labels: Record<Density, { title: string; description: string }> }) {
  const options: Density[] = ["compact", "regular", "comfy"]
  return (
    <div className="component-size-picker" role="radiogroup">
      {options.map((option) => (
        <button
          key={option}
          type="button"
          className={`component-size-option${value === option ? " is-active" : ""}`}
          role="radio"
          aria-checked={value === option}
          onClick={() => onChange(option)}
        >
          <span className="component-size-preview" data-preview-size={option} aria-hidden="true">
            <span className="component-size-preview-sidebar" />
            <span className="component-size-preview-main">
              <span />
              <span />
              <span />
            </span>
          </span>
          <span className="component-size-copy">
            <strong>{labels[option].title}</strong>
            <small>{labels[option].description}</small>
          </span>
          <span className="component-size-check" aria-hidden="true">{value === option && I.check({ size: 13 })}</span>
        </button>
      ))}
    </div>
  )
}

function ProviderOptions({ providers, internationalLabel, chinaLabel }: { providers: ProviderInfo[]; internationalLabel: string; chinaLabel: string }) {
  const international = providers.filter((provider) => provider.region !== "china")
  const china = providers.filter((provider) => provider.region === "china")
  return (
    <>
      {international.length > 0 && (
        <optgroup label={internationalLabel}>
          {international.map((provider) => <option key={provider.id} value={provider.id}>{provider.label}</option>)}
        </optgroup>
      )}
      {china.length > 0 && (
        <optgroup label={chinaLabel}>
          {china.map((provider) => <option key={provider.id} value={provider.id}>{provider.label}</option>)}
        </optgroup>
      )}
    </>
  )
}

const ACCENTS = ["", "#22c55e", "#3b82f6", "#a78bfa", "#f97316", "#ef4444"]

type TabKey = "appearance" | "server" | "updates" | "ai"

export function SettingsScreen() {
  const { t } = useTranslation()
  const { tweaks, setTweak, lang, setLang } = useSettings()
  const [activeTab, setActiveTab] = useState<TabKey>("appearance")
  const [info, setInfo] = useState<ServerInfo | null>(null)
  const [cfg, setCfg] = useState<Record<string, string>>({})
  const [cfgStatus, setCfgStatus] = useState<"idle" | "busy" | "done" | "error">("idle")
  const [llm, setLLM] = useState<LLMSettings | null>(null)
  const [llmApiKey, setLLMApiKey] = useState("")
  const [llmStatus, setLLMStatus] = useState<"idle" | "busy" | "done" | "tested" | "error">("idle")

  // LLM Profiles state
  const [profiles, setProfiles] = useState<LLMProfile[]>([])
  const [providers, setProviders] = useState<ProviderInfo[]>([])
  const [editingProfile, setEditingProfile] = useState<Partial<LLMProfile> | null>(null)
  const [profileForm, setProfileForm] = useState({ name: "", provider: "", model: "", baseUrl: "", apiKey: "", maxTokens: 4096 })
  const [profileStatus, setProfileStatus] = useState<"idle" | "busy" | "done" | "error">("idle")
  const [availableModels, setAvailableModels] = useState<ProviderModel[]>([])
  const [fetchingModels, setFetchingModels] = useState(false)

  // Version update state
  const [updateInfo, setUpdateInfo] = useState<ServerUpdateInfo | null>(null)
  const [updateStatus, setUpdateStatus] = useState<"idle" | "checking" | "applying" | "done" | "error">("idle")
  const [updateError, setUpdateError] = useState("")

  useEffect(() => { serverApi.info().then(setInfo).catch(() => {}) }, [])
  useEffect(() => { settingsApi.get().then(setCfg).catch(() => {}) }, [])
  useEffect(() => { llmSettingsApi.get().then(setLLM).catch(() => {}) }, [])
  useEffect(() => {
    if (activeTab === "ai") {
      llmProfilesApi.list().then(setProfiles).catch(() => {})
      llmProfilesApi.providers().then((r) => setProviders(r.providers)).catch(() => {})
    }
  }, [activeTab])

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

  const checkForUpdates = useCallback(async () => {
    setUpdateStatus("checking")
    setUpdateError("")
    try {
      const data = await versionApi.check(true)
      setUpdateInfo(data)
      setUpdateStatus("idle")
    } catch (err) {
      setUpdateError(String(err))
      setUpdateStatus("error")
    }
  }, [])

  async function applyUpdate() {
    if (!updateInfo?.updateAvailable || !updateInfo.latestVersion) return
    setUpdateStatus("applying")
    setUpdateError("")
    try {
      await versionApi.apply(updateInfo.latestVersion)
      setUpdateStatus("done")
      setTimeout(() => window.location.reload(), 3000)
    } catch (err) {
      setUpdateError(String(err))
      setUpdateStatus("error")
    }
  }

  useEffect(() => {
    if (activeTab === "updates" && !updateInfo) {
      void checkForUpdates()
    }
  }, [activeTab, checkForUpdates, updateInfo])

  const set = (k: keyof Tweaks, v: string) => setTweak(k, v as never)

  const openProfileForm = (profile?: LLMProfile) => {
    if (profile) {
      setEditingProfile(profile)
      setProfileForm({ name: profile.name, provider: profile.provider, model: profile.model, baseUrl: profile.baseUrl, apiKey: "", maxTokens: profile.maxTokens })
    } else {
      const defaultProvider = providers[0]
      setEditingProfile({})
      setProfileForm({ name: "", provider: defaultProvider?.id || "anthropic", model: "", baseUrl: defaultProvider?.defaultBaseUrl || "https://api.anthropic.com", apiKey: "", maxTokens: 4096 })
    }
    setAvailableModels([])
    setProfileStatus("idle")
  }

  const closeProfileForm = () => {
    setEditingProfile(null)
    setProfileForm({ name: "", provider: "", model: "", baseUrl: "", apiKey: "", maxTokens: 4096 })
    setAvailableModels([])
    setProfileStatus("idle")
  }

  const fetchModels = async () => {
    if (!profileForm.provider) return
    setFetchingModels(true)
    try {
      const { models } = await llmProfilesApi.listModels(
        profileForm.provider,
        profileForm.baseUrl || undefined,
        profileForm.apiKey || undefined,
        editingProfile?.id
      )
      setAvailableModels(models)
    } catch {
      setAvailableModels([])
    } finally {
      setFetchingModels(false)
    }
  }

  const saveProfile = async () => {
    if (!profileForm.name.trim() || !profileForm.provider || !profileForm.model.trim()) return
    setProfileStatus("busy")
    try {
      if (editingProfile?.id) {
        await llmProfilesApi.update(editingProfile.id, {
          name: profileForm.name,
          provider: profileForm.provider,
          model: profileForm.model,
          baseUrl: profileForm.baseUrl || undefined,
          apiKey: profileForm.apiKey || undefined,
          maxTokens: profileForm.maxTokens,
        })
      } else {
        await llmProfilesApi.create({
          name: profileForm.name,
          provider: profileForm.provider,
          model: profileForm.model,
          baseUrl: profileForm.baseUrl || undefined,
          apiKey: profileForm.apiKey || undefined,
          maxTokens: profileForm.maxTokens,
        })
      }
      const updated = await llmProfilesApi.list()
      setProfiles(updated)
      setProfileStatus("done")
      setTimeout(closeProfileForm, 800)
    } catch {
      setProfileStatus("error")
    }
  }

  const deleteProfile = async (id: number) => {
    if (!confirm(t("plat.confirmDeleteProfile"))) return
    setProfileStatus("busy")
    try {
      await llmProfilesApi.delete(id)
      const updated = await llmProfilesApi.list()
      setProfiles(updated)
      setProfileStatus("idle")
    } catch {
      setProfileStatus("error")
    }
  }

  const activateProfile = async (id: number) => {
    setProfileStatus("busy")
    try {
      await llmProfilesApi.activate(id)
      const updated = await llmProfilesApi.list()
      setProfiles(updated)
      setProfileStatus("idle")
    } catch {
      setProfileStatus("error")
    }
  }

  const tabs: { key: TabKey; label: string; description: string; icon: ReactNode }[] = [
    { key: "appearance", label: t("plat.appearance"), description: t("plat.appearanceDescription"), icon: I.settings({ size: 15 }) },
    { key: "server", label: t("plat.server"), description: t("plat.serverDescription"), icon: I.dashboard({ size: 15 }) },
    { key: "updates", label: t("plat.serverUpdate"), description: t("plat.updatesDescription"), icon: I.download({ size: 15 }) },
    { key: "ai", label: t("plat.aiProvider"), description: t("plat.aiProviderDescription"), icon: I.sparkle({ size: 15 }) },
  ]
  const activeTabInfo = tabs.find((tab) => tab.key === activeTab) ?? tabs[0]
  const chinaProviderCount = providers.filter((provider) => provider.region === "china").length
  const internationalProviderCount = providers.length - chinaProviderCount

  return (
    <div className="settings-screen">
      <PageHeader title={t("nav.settings")} subtitle={t("plat.settingsSubtitle")} />

      <div className="settings-workspace">
        <nav className="settings-nav" aria-label={t("plat.settingsNavigation")}>
          <div className="settings-nav-label">{t("plat.settingsNavigation")}</div>
          {tabs.map((tab) => (
            <button
              key={tab.key}
              type="button"
              onClick={() => setActiveTab(tab.key)}
              className={`settings-nav-item${activeTab === tab.key ? " is-active" : ""}`}
              aria-current={activeTab === tab.key ? "page" : undefined}
            >
              <span className="settings-nav-icon">{tab.icon}</span>
              <span className="settings-nav-copy">
                <strong>{tab.label}</strong>
                <small>{tab.description}</small>
              </span>
              <span className="settings-nav-arrow" aria-hidden="true">{I.chev({ size: 13 })}</span>
            </button>
          ))}
        </nav>

        <div className="settings-content">
          <div className="settings-content-inner">
            <header className="settings-content-header">
              <h2>{activeTabInfo.label}</h2>
              <p>{activeTabInfo.description}</p>
            </header>
        {/* Appearance Tab */}
        {activeTab === "appearance" && (
          <div className="settings-grid">
            <Section
              title={t("plat.componentSize")}
              description={t("plat.componentSizeHint")}
              icon={I.expand({ size: 15 })}
              wide
            >
              <ComponentSizePicker
                value={tweaks.density}
                onChange={(value) => set("density", value)}
                labels={{
                  compact: { title: t("plat.compact"), description: t("plat.compactDescription") },
                  regular: { title: t("plat.regular"), description: t("plat.regularDescription") },
                  comfy: { title: t("plat.comfy"), description: t("plat.comfyDescription") },
                }}
              />
            </Section>
            <Section title={t("plat.appearance")} description={t("plat.appearanceSectionHint")} icon={I.settings({ size: 15 })}>
              <FormBlock label={t("plat.theme")}>
                <Segmented value={tweaks.theme} onChange={(v) => set("theme", v)} options={[{ v: "dark", label: t("plat.dark") }, { v: "light", label: t("plat.light") }]} />
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
            </Section>
            <Section title={t("plat.typography")} description={t("plat.typographySectionHint")} icon={I.edit({ size: 15 })}>
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
              <FormBlock label={t("plat.language")}>
                <Segmented value={lang} onChange={(v) => setLang(v)} options={[{ v: "en", label: "EN" }, { v: "zh", label: "中文" }]} />
              </FormBlock>
            </Section>
          </div>
        )}

        {/* Server Tab */}
        {activeTab === "server" && (
          <div className="settings-grid">
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
                <button className="btn btn-primary" onClick={saveSettings} disabled={cfgStatus === "busy"}>{cfgStatus === "busy" && <span className="dot pulse ok" />}{t("common.save")}</button>
                {cfgStatus === "done" && <span className="badge ok">{t("plat.settingsSaved")}</span>}
                {cfgStatus === "error" && <span className="badge crit">{t("common.error")}</span>}
              </div>
            </Section>
          </div>
        )}

        {/* Updates Tab */}
        {activeTab === "updates" && (
          <div className="settings-single-column">
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
                      <span className="mono badge" style={{ fontSize: 13 }}>v{updateInfo.latestVersion || "—"}</span>
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
                  className="btn"
                  onClick={checkForUpdates}
                  disabled={updateStatus === "checking" || updateStatus === "applying"}
                >
                  {updateStatus === "checking" && <span className="dot pulse ok" />}
                  {updateStatus === "checking" ? t("plat.checking") : t("plat.checkForUpdates")}
                </button>

                {updateInfo?.updateAvailable && !updateInfo.blocker && (
                  <button
                    className="btn btn-primary"
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
        {activeTab === "ai" && (
          <div className="settings-ai-stack">
            {editingProfile ? (
              <Section
                title={editingProfile.id ? t("plat.editProfile") : t("plat.newProfile")}
                description={t("plat.profileFormDescription")}
                icon={I.sparkle({ size: 15 })}
                action={<button type="button" className="btn btn-ghost" onClick={closeProfileForm}>{I.back({ size: 14 })}{t("common.cancel")}</button>}
              >
                <div className="profile-form-grid">
                  <FormBlock label={t("plat.profileName")}>
                    <input className="input" value={profileForm.name} onChange={(e) => setProfileForm({ ...profileForm, name: e.target.value })} placeholder={t("plat.profileNamePlaceholder")} />
                  </FormBlock>
                  <FormBlock label={t("plat.aiProviderType")}>
                    <select className="input" value={profileForm.provider} onChange={(e) => { setProfileForm({ ...profileForm, provider: e.target.value, baseUrl: providers.find((p) => p.id === e.target.value)?.defaultBaseUrl || "" }); setAvailableModels([]) }}>
                      {providers.length === 0 && <option value={profileForm.provider}>{profileForm.provider}</option>}
                      <ProviderOptions providers={providers} internationalLabel={t("plat.internationalProviders")} chinaLabel={t("plat.chinaProviders")} />
                    </select>
                  </FormBlock>
                  <div className="profile-form-span-2">
                    <FormBlock label={t("plat.aiBaseUrl")} hint={t("plat.aiBaseUrlHint")}>
                      <input className="input mono" value={profileForm.baseUrl} onChange={(e) => setProfileForm({ ...profileForm, baseUrl: e.target.value })} placeholder={providers.find((p) => p.id === profileForm.provider)?.defaultBaseUrl} />
                    </FormBlock>
                  </div>
                  <FormBlock label={t("plat.apiKey")} hint={editingProfile.id ? t("plat.apiKeyUpdateHint") : undefined}>
                    <input className="input mono" type="password" autoComplete="new-password" value={profileForm.apiKey} onChange={(e) => setProfileForm({ ...profileForm, apiKey: e.target.value })} placeholder={editingProfile.id ? t("plat.apiKeyKeepExisting") : t("plat.apiKeyPlaceholder")} />
                  </FormBlock>
                  <FormBlock label={t("plat.aiMaxTokens")}>
                    <input className="input mono" type="number" min={1} max={65536} value={profileForm.maxTokens} onChange={(e) => setProfileForm({ ...profileForm, maxTokens: Number(e.target.value) })} />
                  </FormBlock>
                  <div className="profile-form-span-2">
                    <FormBlock label={t("plat.aiModel")}>
                      <div className="profile-model-row">
                        {availableModels.length === 0 ? (
                          <input className="input mono" value={profileForm.model} onChange={(e) => setProfileForm({ ...profileForm, model: e.target.value })} placeholder="claude-sonnet-4-5" />
                        ) : (
                          <select className="input mono" value={profileForm.model} onChange={(e) => setProfileForm({ ...profileForm, model: e.target.value })}>
                            <option value="">{t("plat.selectModel")}</option>
                            {availableModels.map((m) => (
                              <option key={m.id} value={m.id}>{m.displayName}</option>
                            ))}
                          </select>
                        )}
                        <button type="button" className="btn" onClick={fetchModels} disabled={fetchingModels || !profileForm.provider}>
                          {fetchingModels && <span className="dot pulse ok" />}
                          {t("plat.fetchModels")}
                        </button>
                      </div>
                      {availableModels.length > 0 && <div className="hint">{t("plat.fetchedModels", { count: availableModels.length })}</div>}
                    </FormBlock>
                  </div>
                </div>
                <div className="settings-actions">
                  <button className="btn btn-primary" onClick={saveProfile} disabled={profileStatus === "busy" || !profileForm.name.trim() || !profileForm.model.trim()}>
                    {profileStatus === "busy" && <span className="dot pulse ok" />}{t("common.save")}
                  </button>
                  {profileStatus === "done" && <span className="badge ok">{t("plat.settingsSaved")}</span>}
                  {profileStatus === "error" && <span className="badge crit">{t("common.error")}</span>}
                </div>
              </Section>
            ) : (
              <Section
                title={t("plat.llmProfiles")}
                description={t("plat.providerProfilesDescription")}
                icon={I.sparkle({ size: 15 })}
                action={<button className="btn btn-primary" onClick={() => openProfileForm()} disabled={profileStatus === "busy"}>{I.plus({ size: 14 })}<span>{t("plat.newProfile")}</span></button>}
              >
                <div className="provider-catalog-summary">
                  <span className="provider-catalog-icon">{I.globe({ size: 16 })}</span>
                  <div className="provider-catalog-copy">
                    <strong>{t("plat.providerCatalogAvailable", { count: providers.length })}</strong>
                    <span>{t("plat.providerCatalogHint")}</span>
                  </div>
                  <div className="provider-catalog-badges">
                    <span className="badge">{t("plat.internationalProviderCount", { count: internationalProviderCount })}</span>
                    <span className="badge">{t("plat.chinaProviderCount", { count: chinaProviderCount })}</span>
                  </div>
                </div>
                {profileStatus === "error" && <div className="badge crit" role="alert">{t("common.error")}</div>}
                {profiles.length === 0 ? (
                  <div className="provider-empty-state">
                    <span>{I.sparkle({ size: 20 })}</span>
                    <strong>{t("plat.noProfilesTitle")}</strong>
                    <p>{t("plat.noProfiles")}</p>
                    <button className="btn" onClick={() => openProfileForm()}>{I.plus({ size: 14 })}{t("plat.newProfile")}</button>
                  </div>
                ) : (
                  <div className="provider-profile-grid">
                    {profiles.map((profile) => {
                      const provider = providers.find((item) => item.id === profile.provider)
                      const providerLabel = provider?.label || profile.provider
                      return (
                        <article key={profile.id} className={`provider-profile-card${profile.isActive ? " is-active" : ""}`}>
                          <div className="provider-profile-header">
                            <span className="provider-profile-mark" title={providerLabel}>{profile.provider.slice(0, 2).toUpperCase()}</span>
                            <div className="provider-profile-title">
                              <div>
                                <strong>{profile.name}</strong>
                                {profile.isActive && <span className="badge ok">{t("plat.active")}</span>}
                              </div>
                              <span>{providerLabel}</span>
                            </div>
                          </div>
                          <dl className="provider-profile-meta">
                            <div><dt>{t("plat.aiModel")}</dt><dd className="mono">{profile.model}</dd></div>
                            <div><dt>{t("plat.aiMaxTokens")}</dt><dd className="mono num">{profile.maxTokens.toLocaleString()}</dd></div>
                            <div><dt>{t("plat.apiKey")}</dt><dd className={profile.apiKeyConfigured ? "status-ok" : "status-warn"}>{profile.apiKeyConfigured ? t("plat.configured") : t("plat.notConfigured")}</dd></div>
                          </dl>
                          <div className="provider-profile-actions">
                            {!profile.isActive && <button className="btn btn-ghost" onClick={() => activateProfile(profile.id)} disabled={profileStatus === "busy"}>{I.check({ size: 13 })}{t("plat.activate")}</button>}
                            <span className="provider-profile-action-spacer" />
                            <button className="btn btn-ghost btn-icon" onClick={() => openProfileForm(profile)} disabled={profileStatus === "busy"} aria-label={t("common.edit")} title={t("common.edit")}>{I.edit({ size: 14 })}</button>
                            <button className="btn btn-ghost btn-icon" onClick={() => deleteProfile(profile.id)} disabled={profileStatus === "busy"} aria-label={t("common.delete")} title={t("common.delete")}>{I.trash({ size: 14 })}</button>
                          </div>
                        </article>
                      )
                    })}
                  </div>
                )}
                <div className="hint">{t("plat.profilesHint")}</div>
              </Section>
            )}

            {!editingProfile && llm && (
              <Section title={t("plat.globalLLMFallback")} description={t("plat.globalFallbackHint")} icon={I.settings({ size: 15 })}>
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
                    onChange={(e) => {
                      const provider = providers.find((item) => item.id === e.target.value)
                      setLLM({ ...llm, provider: e.target.value as LLMProvider, baseUrl: provider?.defaultBaseUrl || "" })
                      setLLMStatus("idle")
                    }}
                  >
                    {providers.length === 0 && <option value={llm.provider}>{llm.provider}</option>}
                    <ProviderOptions providers={providers} internationalLabel={t("plat.internationalProviders")} chinaLabel={t("plat.chinaProviders")} />
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
                    placeholder={providers.find((provider) => provider.id === llm.provider)?.defaultBaseUrl || "https://api.example.com"}
                  />
                  <div className="hint" style={{ marginTop: 6 }}>{t("plat.aiBaseUrlHint")}</div>
                </FormBlock>
                <FormBlock label={t("plat.apiKey")}>
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
                <div className="settings-actions">
                  <button className="btn btn-primary" onClick={() => saveLLM(false)} disabled={llmStatus === "busy"}>
                    {llmStatus === "busy" && <span className="dot pulse ok" />}{t("common.save")}
                  </button>
                  <button className="btn" onClick={() => saveLLM(true)} disabled={llmStatus === "busy" || (!llm.apiKeyConfigured && !llmApiKey.trim()) || !llm.model.trim()}>
                    {t("plat.saveAndTest")}
                  </button>
                  {llm.apiKeyConfigured && llm.apiKeySource === "stored" && (
                    <button className="btn btn-ghost" onClick={clearLLMApiKey} disabled={llmStatus === "busy"}>{t("plat.removeApiKey")}</button>
                  )}
                  {llmStatus === "done" && <span className="badge ok">{t("plat.settingsSaved")}</span>}
                  {llmStatus === "tested" && <span className="badge ok">{t("plat.connectionSucceeded")}</span>}
                  {llmStatus === "error" && <span className="badge crit">{t("plat.connectionOrSaveFailed")}</span>}
                </div>
              </Section>
            )}
          </div>
        )}
          </div>
        </div>
      </div>
    </div>
  )
}
