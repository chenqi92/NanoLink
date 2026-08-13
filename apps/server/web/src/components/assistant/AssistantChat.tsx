import { useEffect, useRef, useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useAssistant } from "@/contexts/AssistantContext"

export function AssistantChat() {
  const { t } = useTranslation()
  const {
    messages, input, setInput, selectedProfileId, setSelectedProfileId, status, profiles,
    findings, sending, chatError, trimmedContext, send, retry, cancel, newChat,
  } = useAssistant()
  const [copiedId, setCopiedId] = useState<string | null>(null)
  const listRef = useRef<HTMLDivElement>(null)
  const [nearBottom, setNearBottom] = useState(true)

  useEffect(() => {
    const element = listRef.current
    if (!element || !nearBottom) return
    element.scrollTop = element.scrollHeight
  }, [messages, nearBottom])

  const inputBytes = new TextEncoder().encode(input.trim()).byteLength
  const selectedProfile = profiles.data.find((profile) => profile.id === selectedProfileId)
  const activeProfile = profiles.data.find((profile) => profile.isActive)
  const defaultProfileConfigured = Boolean(activeProfile?.model && activeProfile.apiKeyConfigured)
  const configured = selectedProfileId == null ? defaultProfileConfigured || status.data?.enabled : Boolean(selectedProfile?.model && selectedProfile.apiKeyConfigured)
  const canSend = Boolean(input.trim()) && Boolean(configured) && !sending && inputBytes <= 4096
  const modelHint = selectedProfile
    ? `${selectedProfile.name} · ${selectedProfile.model}`
    : activeProfile
      ? `${activeProfile.name} · ${activeProfile.model}`
      : status.data?.model || t("assistant.defaultModel")

  const copy = async (id: string, content: string) => {
    await navigator.clipboard?.writeText(content)
    setCopiedId(id)
    window.setTimeout(() => setCopiedId((current) => current === id ? null : current), 1500)
  }

  const submit = () => { void send() }

  return (
    <section className="assistant-chat card" aria-label={t("assistant.chatLabel")}>
      <div className="assistant-chat-header">
        <div className="col" style={{ gap: 2, minWidth: 0 }}>
          <span className="upper">{t("assistant.conversation")}</span>
          <span className="muted assistant-model-hint">
            {modelHint}
          </span>
        </div>
        <div className="row gap-2 assistant-chat-actions">
          <label className="visually-hidden" htmlFor="assistant-profile">{t("assistant.selectModel")}</label>
          <select
            id="assistant-profile"
            className="select assistant-profile-select"
            value={selectedProfileId ?? ""}
            onChange={(event) => setSelectedProfileId(event.target.value ? Number(event.target.value) : undefined)}
            disabled={profiles.loading}
          >
            <option value="">{t("assistant.defaultModel")}{activeProfile?.model ? ` · ${activeProfile.model}` : status.data?.model ? ` · ${status.data.model}` : ""}</option>
            {profiles.data.map((profile) => (
              <option key={profile.id} value={profile.id} disabled={!profile.apiKeyConfigured || !profile.model}>
                {profile.name} · {profile.model}{profile.isActive ? ` · ${t("assistant.active")}` : ""}
              </option>
            ))}
          </select>
          <button className="btn btn-ghost btn-sm" onClick={newChat} disabled={messages.length === 0 && !input}>
            {I.plus({ size: 13 })}<span>{t("assistant.newChat")}</span>
          </button>
        </div>
      </div>

      {status.error && <div className="assistant-inline-error" role="alert">{status.error}</div>}
      {!configured && !status.loading && <div className="assistant-config-hint" role="status">{t("assistant.configureHint")}</div>}

      <div
        ref={listRef}
        className="assistant-message-list"
        role="log"
        aria-live="polite"
        onScroll={(event) => {
          const element = event.currentTarget
          setNearBottom(element.scrollHeight - element.scrollTop - element.clientHeight < 80)
        }}
      >
        {messages.length === 0 ? (
          <div className="assistant-empty-state">
            <div className="assistant-empty-icon">{I.ai({ size: 24 })}</div>
            <h2>{t("assistant.greeting")}</h2>
            <p className="muted">{t("assistant.greetingDetail")}</p>
            <div className="assistant-suggestions">
              {(findings.data.length > 0 ? findings.data.slice(0, 3).map((finding) => finding.title) : [t("assistant.promptFleet"), t("assistant.promptAlerts"), t("assistant.promptMetrics")]).map((prompt) => (
                <button key={prompt} className="btn btn-ghost assistant-suggestion" onClick={() => { setInput(prompt); void send(prompt) }} disabled={!configured || sending}>{prompt}</button>
              ))}
            </div>
          </div>
        ) : (
          <>
            {trimmedContext && <div className="assistant-context-divider">{t("assistant.contextTrimmed")}</div>}
            {messages.map((message) => (
              <article key={message.id} className={`assistant-message assistant-message-${message.role}`}>
                <div className="assistant-message-avatar" aria-hidden="true">{message.role === "user" ? I.user({ size: 14 }) : I.ai({ size: 14 })}</div>
                <div className="assistant-message-body">
                  <div className="assistant-message-meta"><span>{message.role === "user" ? t("assistant.you") : t("assistant.name")}</span>{message.model?.model && <span className="dim mono">{message.model.model}</span>}</div>
                  {message.state === "pending" ? <div className="muted assistant-pending"><span className="dot pulse ok" /> {t("assistant.generating")}</div> : <p className={`assistant-message-content ${message.state === "failed" ? "assistant-message-error" : ""}`}>{message.content}</p>}
                  {message.state === "complete" && message.role === "assistant" && (
                    <button className="btn btn-ghost btn-sm assistant-copy" onClick={() => void copy(message.id, message.content)} aria-label={copiedId === message.id ? t("assistant.copied") : t("assistant.copy")}>
                      {copiedId === message.id ? I.check({ size: 11 }) : I.copy({ size: 11 })}<span>{copiedId === message.id ? t("assistant.copied") : t("assistant.copy")}</span>
                    </button>
                  )}
                  {message.state === "failed" && <button className="btn btn-sm btn-ghost" onClick={() => void retry()}>{I.refresh({ size: 12 })}<span>{t("assistant.retry")}</span></button>}
                </div>
              </article>
            ))}
          </>
        )}
      </div>

      {!nearBottom && messages.length > 0 && <button className="btn btn-sm assistant-jump" onClick={() => { if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight }}>{t("assistant.jumpLatest")}</button>}
      {chatError && <div className="assistant-chat-error" role="alert">{chatError}</div>}
      <div className="assistant-composer-wrap">
        <textarea
          className="textarea assistant-composer"
          aria-label={t("assistant.composerLabel")}
          placeholder={configured ? t("plat.askPlaceholder") : t("assistant.configureHint")}
          value={input}
          onChange={(event) => setInput(event.target.value)}
          onKeyDown={(event) => { if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); submit() } }}
          disabled={!configured || sending}
          rows={2}
        />
        <div className="row assistant-composer-footer">
          <span className={`assistant-counter ${inputBytes > 3800 ? "warn" : ""}`}>{inputBytes > 3800 ? `${inputBytes}/4096` : t("assistant.shiftEnterHint")}</span>
          <div className="row gap-2">
            {sending && <button className="btn btn-sm btn-ghost" onClick={cancel}>{I.x({ size: 12 })}<span>{t("assistant.cancel")}</span></button>}
            <button className="btn btn-primary btn-icon" onClick={submit} disabled={!canSend} aria-label={t("assistant.send")} title={t("assistant.send")}>{I.arrow({ size: 14 })}</button>
          </div>
        </div>
      </div>
    </section>
  )
}
