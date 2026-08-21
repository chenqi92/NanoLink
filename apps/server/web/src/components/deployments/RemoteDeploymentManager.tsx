import { useCallback, useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { FormBlock } from "@/components/shell/primitives"
import { I } from "@/lib/icons"
import {
  deploymentsApi,
  type Agent,
  type DeploymentTarget,
  type DeploymentTargetInput,
  type EnvironmentScript,
  type EnvironmentScriptInput,
  type EnvironmentScriptRun,
} from "@/lib/api"

type Tab = "targets" | "scripts"

export function RemoteDeploymentManager({ agents, onChanged }: { agents: Agent[]; onChanged: () => void }) {
  const { t } = useTranslation()
  const [tab, setTab] = useState<Tab>("targets")
  const [targets, setTargets] = useState<DeploymentTarget[]>([])
  const [scripts, setScripts] = useState<EnvironmentScript[]>([])
  const [targetForm, setTargetForm] = useState<DeploymentTarget | "new" | null>(null)
  const [scriptForm, setScriptForm] = useState<EnvironmentScript | "new" | null>(null)
  const [run, setRun] = useState<EnvironmentScriptRun | null>(null)
  const [error, setError] = useState<string | null>(null)

  const reload = useCallback(async () => {
    try {
      const [targetRows, scriptRows] = await Promise.all([deploymentsApi.targets(), deploymentsApi.environmentScripts()])
      setTargets(targetRows)
      setScripts(scriptRows)
      setError(null)
      onChanged()
    } catch (e) {
      setError(messageOf(e))
    }
  }, [onChanged])

  useEffect(() => { reload() }, [reload])
  useEffect(() => {
    if (!run || run.status === "success" || run.status === "failed") return
    const timer = window.setInterval(async () => {
      try {
        const next = await deploymentsApi.environmentScriptRun(run.id)
        setRun(next)
        if (next.status === "success" || next.status === "failed") window.clearInterval(timer)
      } catch (e) {
        setError(messageOf(e))
      }
    }, 1500)
    return () => window.clearInterval(timer)
  }, [run])

  async function editScript(script: EnvironmentScript) {
    try {
      setScriptForm(await deploymentsApi.environmentScript(script.id))
    } catch (e) {
      setError(messageOf(e))
    }
  }

  async function removeTarget(target: DeploymentTarget) {
    if (!window.confirm(t("deploy.remote.confirmDeleteTarget", { name: target.name }))) return
    try {
      await deploymentsApi.deleteTarget(target.id)
      await reload()
    } catch (e) { setError(messageOf(e)) }
  }

  async function removeScript(script: EnvironmentScript) {
    if (!window.confirm(t("deploy.remote.confirmDeleteScript", { name: script.name }))) return
    try {
      await deploymentsApi.deleteEnvironmentScript(script.id)
      await reload()
    } catch (e) { setError(messageOf(e)) }
  }

  async function runScript(script: EnvironmentScript) {
    try {
      setRun(await deploymentsApi.runEnvironmentScript(script.id))
      setError(null)
    } catch (e) { setError(messageOf(e)) }
  }

  if (targetForm) {
    return <TargetEditor agents={agents} target={targetForm === "new" ? undefined : targetForm} onCancel={() => setTargetForm(null)} onSaved={async () => { setTargetForm(null); await reload() }} />
  }
  if (scriptForm) {
    return <ScriptEditor targets={targets} script={scriptForm === "new" ? undefined : scriptForm} onCancel={() => setScriptForm(null)} onSaved={async () => { setScriptForm(null); await reload() }} />
  }

  return (
    <div className="remote-manager">
      <div className="tabs">
        <button className={`tab ${tab === "targets" ? "active" : ""}`} onClick={() => setTab("targets")}>{I.globe({ size: 13 })}{t("deploy.remote.targets")}</button>
        <button className={`tab ${tab === "scripts" ? "active" : ""}`} onClick={() => setTab("scripts")}>{I.term({ size: 13 })}{t("deploy.remote.scripts")}</button>
      </div>
      {error && <div className="deploy-modal-error">{error}</div>}
      {tab === "targets" ? (
        <>
          <div className="remote-manager-head"><span className="hint">{t("deploy.remote.targetsHint")}</span><button className="btn btn-primary btn-sm" onClick={() => setTargetForm("new")}>{I.plus({ size: 12 })}{t("deploy.remote.newTarget")}</button></div>
          <div className="remote-card-list">
            {targets.map((target) => (
              <div className="remote-card" key={target.id}>
                <div className="remote-card-icon">{I.globe({ size: 18 })}</div>
                <div className="col flex-1" style={{ gap: 3, minWidth: 0 }}>
                  <div className="row gap-2"><strong>{target.name}</strong><span className="badge">{target.authType === "password" ? t("deploy.remote.password") : t("deploy.remote.privateKey")}</span>{target.allowUnknownHost && <span className="badge warn">{t("deploy.remote.unverifiedHost")}</span>}</div>
                  <span className="mono dim truncate">{target.username}@{target.host}:{target.port}</span>
                  <span className="muted">{t("deploy.remote.relayAgent")}: {agentName(agents, target.agentId)}{target.useSudo ? ` · ${t("deploy.remote.sudo")}` : ""}</span>
                </div>
                <button className="btn btn-sm" onClick={() => setTargetForm(target)}>{I.edit({ size: 12 })}</button>
                <button className="btn btn-sm danger" onClick={() => removeTarget(target)}>{I.trash({ size: 12 })}</button>
              </div>
            ))}
            {targets.length === 0 && <div className="deploy-list-empty">{t("deploy.remote.noTargets")}</div>}
          </div>
        </>
      ) : (
        <>
          <div className="remote-manager-head"><span className="hint">{t("deploy.remote.scriptsHint")}</span><button className="btn btn-primary btn-sm" disabled={targets.length === 0} onClick={() => setScriptForm("new")}>{I.plus({ size: 12 })}{t("deploy.remote.newScript")}</button></div>
          <div className="remote-card-list">
            {scripts.map((script) => (
              <div className="remote-card" key={script.id}>
                <div className="remote-card-icon">{I.term({ size: 18 })}</div>
                <div className="col flex-1" style={{ gap: 3, minWidth: 0 }}>
                  <div className="row gap-2"><strong>{script.name}</strong><span className="badge">{script.timeoutSeconds}s</span></div>
                  <span className="muted truncate">{script.description || "—"}</span>
                  <span className="mono dim">{script.target?.name ?? targetName(targets, script.targetId)}</span>
                </div>
                <button className="btn btn-sm" disabled={run?.status === "running"} onClick={() => runScript(script)}>{I.bolt({ size: 12 })}{t("deploy.remote.run")}</button>
                <button className="btn btn-sm" onClick={() => editScript(script)}>{I.edit({ size: 12 })}</button>
                <button className="btn btn-sm danger" onClick={() => removeScript(script)}>{I.trash({ size: 12 })}</button>
              </div>
            ))}
            {scripts.length === 0 && <div className="deploy-list-empty">{t("deploy.remote.noScripts")}</div>}
          </div>
          {run && <div className="remote-run-result"><div className="row gap-2"><strong>{run.script?.name ?? t("deploy.remote.scriptRun")}</strong><span className={`badge ${run.status === "success" ? "ok" : run.status === "failed" ? "crit" : "warn"}`}>{t(`deploy.status.${run.status}`)}</span></div>{run.output && <pre className="deploy-output">{run.output}</pre>}{run.error && run.error !== run.output && <div className="deploy-task-error">{run.error}</div>}</div>}
        </>
      )}
    </div>
  )
}

function TargetEditor({ agents, target, onCancel, onSaved }: { agents: Agent[]; target?: DeploymentTarget; onCancel: () => void; onSaved: () => void }) {
  const { t } = useTranslation()
  const [form, setForm] = useState<DeploymentTargetInput>({
    name: target?.name ?? "",
    agentId: target?.agentId ?? agents[0]?.id ?? "",
    host: target?.host ?? "",
    port: target?.port ?? 22,
    username: target?.username ?? "root",
    authType: target?.authType ?? "private_key",
    credential: "",
    sshKnownHosts: target?.sshKnownHosts ?? "",
    allowUnknownHost: target?.allowUnknownHost ?? false,
    useSudo: target?.useSudo ?? false,
  })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  function set<K extends keyof DeploymentTargetInput>(key: K, value: DeploymentTargetInput[K]) { setForm({ ...form, [key]: value }) }
  async function save() {
    setBusy(true)
    try {
      if (target) await deploymentsApi.updateTarget(target.id, form)
      else await deploymentsApi.createTarget(form)
      onSaved()
    } catch (e) { setError(messageOf(e)) } finally { setBusy(false) }
  }
  const credentialReady = form.credential || (target?.credentialConfigured && target.authType === form.authType)
  const ready = form.name && form.agentId && form.host && form.username && credentialReady && (form.allowUnknownHost || form.sshKnownHosts)
  return (
    <div className="remote-editor">
      <div className="remote-editor-head"><button className="btn btn-sm" onClick={onCancel}>{I.back({ size: 12 })}{t("common.back")}</button><strong>{target ? t("deploy.remote.editTarget") : t("deploy.remote.newTarget")}</strong></div>
      <div className="deploy-form-grid">
        <FormBlock label={t("deploy.remote.targetName")}><input className="input" value={form.name} onChange={(e) => set("name", e.target.value)} placeholder="production-east" /></FormBlock>
        <FormBlock label={t("deploy.remote.relayAgent")}><select className="select" value={form.agentId} onChange={(e) => set("agentId", e.target.value)}>{agents.map((a) => <option key={a.id} value={a.id}>{a.hostname} · {a.id.slice(0, 8)}</option>)}</select></FormBlock>
        <FormBlock label={t("deploy.remote.host")}><input className="input mono" value={form.host} onChange={(e) => set("host", e.target.value)} placeholder="203.0.113.10" /></FormBlock>
        <FormBlock label={t("deploy.remote.port")}><input className="input" type="number" min={1} max={65535} value={form.port} onChange={(e) => set("port", Number(e.target.value))} /></FormBlock>
        <FormBlock label={t("deploy.remote.username")}><input className="input mono" value={form.username} onChange={(e) => set("username", e.target.value)} /></FormBlock>
        <FormBlock label={t("deploy.remote.authType")}><select className="select" value={form.authType} onChange={(e) => set("authType", e.target.value as DeploymentTargetInput["authType"])}><option value="private_key">{t("deploy.remote.privateKey")}</option><option value="password">{t("deploy.remote.password")}</option></select></FormBlock>
        <div className="deploy-form-wide"><FormBlock label={form.authType === "password" ? t("deploy.remote.password") : t("deploy.remote.privateKey")} hint={target?.credentialConfigured ? t("deploy.remote.credentialPreserve") : undefined}>{form.authType === "password" ? <input className="input" type="password" value={form.credential} onChange={(e) => set("credential", e.target.value)} /> : <textarea className="textarea mono" rows={6} value={form.credential} onChange={(e) => set("credential", e.target.value)} placeholder="-----BEGIN OPENSSH PRIVATE KEY-----" />}</FormBlock></div>
        <div className="deploy-form-wide"><FormBlock label="known_hosts" hint={t("deploy.remote.knownHostsHint")}><textarea className="textarea mono" rows={3} value={form.sshKnownHosts} disabled={form.allowUnknownHost} onChange={(e) => set("sshKnownHosts", e.target.value)} placeholder="host ssh-ed25519 AAAA…" /></FormBlock></div>
        <label className="deploy-toggle"><input type="checkbox" checked={form.allowUnknownHost} onChange={(e) => set("allowUnknownHost", e.target.checked)} /><span><strong>{t("deploy.remote.allowUnknownHost")}</strong><small>{t("deploy.remote.allowUnknownHostHint")}</small></span></label>
        <label className="deploy-toggle"><input type="checkbox" checked={form.useSudo} onChange={(e) => set("useSudo", e.target.checked)} /><span><strong>{t("deploy.remote.useSudo")}</strong><small>{t("deploy.remote.useSudoHint")}</small></span></label>
      </div>
      {error && <div className="deploy-modal-error">{error}</div>}
      <div className="remote-editor-actions"><button className="btn btn-sm" onClick={onCancel}>{t("common.cancel")}</button><button className="btn btn-primary btn-sm" disabled={!ready || busy} onClick={save}>{busy && <span className="dot pulse ok" />}{t("common.save")}</button></div>
    </div>
  )
}

function ScriptEditor({ targets, script, onCancel, onSaved }: { targets: DeploymentTarget[]; script?: EnvironmentScript; onCancel: () => void; onSaved: () => void }) {
  const { t } = useTranslation()
  const [form, setForm] = useState<EnvironmentScriptInput>({ name: script?.name ?? "", description: script?.description ?? "", targetId: script?.targetId ?? targets[0]?.id ?? 0, content: script?.content ?? "", timeoutSeconds: script?.timeoutSeconds ?? 600 })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  function set<K extends keyof EnvironmentScriptInput>(key: K, value: EnvironmentScriptInput[K]) { setForm({ ...form, [key]: value }) }
  async function save() {
    setBusy(true)
    try {
      if (script) await deploymentsApi.updateEnvironmentScript(script.id, form)
      else await deploymentsApi.createEnvironmentScript(form)
      onSaved()
    } catch (e) { setError(messageOf(e)) } finally { setBusy(false) }
  }
  return (
    <div className="remote-editor">
      <div className="remote-editor-head"><button className="btn btn-sm" onClick={onCancel}>{I.back({ size: 12 })}{t("common.back")}</button><strong>{script ? t("deploy.remote.editScript") : t("deploy.remote.newScript")}</strong></div>
      <div className="deploy-form-grid">
        <FormBlock label={t("deploy.remote.scriptName")}><input className="input" value={form.name} onChange={(e) => set("name", e.target.value)} placeholder="install-java-runtime" /></FormBlock>
        <FormBlock label={t("deploy.remote.target")}><select className="select" value={form.targetId} onChange={(e) => set("targetId", Number(e.target.value))}>{targets.map((target) => <option key={target.id} value={target.id}>{target.name} · {target.host}</option>)}</select></FormBlock>
        <FormBlock label={t("deploy.remote.timeout")}><input className="input" type="number" min={1} max={3600} value={form.timeoutSeconds} onChange={(e) => set("timeoutSeconds", Number(e.target.value))} /></FormBlock>
        <FormBlock label={t("deploy.remote.description")}><input className="input" value={form.description} onChange={(e) => set("description", e.target.value)} /></FormBlock>
        <div className="deploy-form-wide"><FormBlock label={t("deploy.remote.scriptContent")} hint={t("deploy.remote.scriptContentHint")}><textarea className="textarea mono remote-script-source" rows={14} value={form.content} onChange={(e) => set("content", e.target.value)} placeholder={'#!/bin/sh\nset -eu'} /></FormBlock></div>
      </div>
      {error && <div className="deploy-modal-error">{error}</div>}
      <div className="remote-editor-actions"><button className="btn btn-sm" onClick={onCancel}>{t("common.cancel")}</button><button className="btn btn-primary btn-sm" disabled={busy || !form.name || !form.targetId || (!script && !form.content)} onClick={save}>{busy && <span className="dot pulse ok" />}{t("common.save")}</button></div>
    </div>
  )
}

function agentName(agents: Agent[], id: string) { return agents.find((agent) => agent.id === id)?.hostname ?? id }
function targetName(targets: DeploymentTarget[], id: number) { return targets.find((target) => target.id === id)?.name ?? String(id) }
function messageOf(error: unknown) { return error instanceof Error ? error.message : String(error) }
