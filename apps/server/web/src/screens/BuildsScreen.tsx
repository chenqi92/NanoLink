import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties } from "react"
import { useTranslation } from "react-i18next"
import {
  agentsApi,
  buildsApi,
  deploymentsApi,
  type Agent,
  type ApiError,
  type BuildPipeline,
  type BuildPipelineInput,
  type BuildRun,
  type BuildStage,
  type DeploymentProject,
} from "@/lib/api"
import { I } from "@/lib/icons"
import { Modal } from "@/components/shell/Dialog"
import { EmptyState, FormBlock, PageHeader } from "@/components/shell/primitives"
import { runAgentCommand } from "@/hooks/useAgentCommand"
import "./builds.css"

const terminal = (status?: string) => status === "success" || status === "failed" || status === "canceled"

interface GitCredentialStatus {
  username: string
  gitVersion: string
  credentialHelper: string
  sshAgent: boolean
  publicKeys: { name: string; key: string }[]
}

export function BuildsScreen() {
  const { t } = useTranslation()
  const [pipelines, setPipelines] = useState<BuildPipeline[]>([])
  const [agents, setAgents] = useState<Agent[]>([])
  const [deployments, setDeployments] = useState<DeploymentProject[]>([])
  const [overviewRuns, setOverviewRuns] = useState<BuildRun[]>([])
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [detail, setDetail] = useState<BuildPipeline | null>(null)
  const [selectedRun, setSelectedRun] = useState<BuildRun | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [editor, setEditor] = useState<BuildPipeline | "new" | null>(null)
  const [runOpen, setRunOpen] = useState(false)
  const [webhookToken, setWebhookToken] = useState<string | null>(null)

  const loadOverview = useCallback(async () => {
    setLoading(true)
    try {
      const [pipelineRows, agentRows, deploymentRows, runRows] = await Promise.all([
        buildsApi.pipelines(), agentsApi.list(), deploymentsApi.projects(), buildsApi.runs(undefined, 100),
      ])
      setPipelines(pipelineRows)
      setAgents(agentRows)
      setDeployments(deploymentRows)
      setOverviewRuns(runRows)
      setSelectedId((current) => current ?? pipelineRows[0]?.id ?? null)
      setError(null)
    } catch (reason) {
      setError(messageOf(reason))
    } finally {
      setLoading(false)
    }
  }, [])

  const loadDetail = useCallback(async (id: number) => {
    try {
      const data = await buildsApi.pipeline(id)
      setDetail(data)
      setSelectedRun((current) => {
        const currentInList = data.runs?.find((run) => run.id === current?.id)
        return currentInList ?? data.runs?.find((run) => !terminal(run.status)) ?? data.runs?.[0] ?? null
      })
      setError(null)
    } catch (reason) {
      setError(messageOf(reason))
    }
  }, [])

  useEffect(() => { loadOverview() }, [loadOverview])
  useEffect(() => { if (selectedId) loadDetail(selectedId); else setDetail(null) }, [selectedId, loadDetail])

  const liveRunId = selectedRun?.id
  const liveRunStatus = selectedRun?.status
  useEffect(() => {
    if (!liveRunId || terminal(liveRunStatus)) return
    const timer = window.setInterval(async () => {
      try {
        const next = await buildsApi.runDetail(liveRunId)
        setSelectedRun(next)
        if (terminal(next.status) && selectedId) {
          window.clearInterval(timer)
          await Promise.all([loadDetail(selectedId), loadOverview()])
        }
      } catch (reason) {
        setError(messageOf(reason))
      }
    }, 1600)
    return () => window.clearInterval(timer)
  }, [liveRunId, liveRunStatus, selectedId, loadDetail, loadOverview])

  const hostnames = useMemo(() => new Map(agents.map((agent) => [agent.id, agent.hostname])), [agents])
  const stats = useMemo(() => {
    return {
      enabled: pipelines.filter((pipeline) => pipeline.enabled).length,
      scheduled: pipelines.filter((pipeline) => pipeline.schedule).length,
      running: overviewRuns.filter((run) => !terminal(run.status)).length,
    }
  }, [pipelines, overviewRuns])

  async function rotateWebhook() {
    if (!detail) return
    try {
      const result = await buildsApi.rotateWebhookToken(detail.id)
      setWebhookToken(result.webhookToken)
      await loadDetail(detail.id)
    } catch (reason) {
      setError(messageOf(reason))
    }
  }

  async function cancelRun(run: BuildRun) {
    if (!window.confirm(t("build.cancelConfirm", { number: run.runNumber }))) return
    try {
      const canceled = await buildsApi.cancelRun(run.id)
      setSelectedRun(canceled)
      if (selectedId) await Promise.all([loadDetail(selectedId), loadOverview()])
    } catch (reason) {
      setError(messageOf(reason))
    }
  }

  return (
    <div className="col build-page">
      <PageHeader
        eyebrow={t("build.eyebrow")}
        title={t("build.title")}
        subtitle={t("build.subtitle")}
        actions={
          <>
            <button className="btn" onClick={loadOverview}>{I.refresh({ size: 13 })}<span>{t("common.refresh")}</span></button>
            <button className="btn btn-primary" onClick={() => setEditor("new")}>{I.plus({ size: 13 })}<span>{t("build.newPipeline")}</span></button>
          </>
        }
      />

      {error && <div className="build-alert" role="alert"><span>{I.warn({ size: 14 })}</span><span>{error}</span><button aria-label={t("common.close")} title={t("common.close")} onClick={() => setError(null)}>{I.x({ size: 12 })}</button></div>}

      <div className="build-kpis" aria-label={t("build.summary")}>
        <span><strong className="mono">{stats.enabled}</strong>{t("build.enabledPipelines")}</span>
        <span><strong className="mono">{stats.running}</strong>{t("build.runningNow")}</span>
        <span><strong className="mono">{stats.scheduled}</strong>{t("build.scheduled")}</span>
        <span className="build-safety">{I.shield({ size: 12 })}{t("build.runnerBoundary")}</span>
      </div>

      <div className="build-grid">
        <aside className="card build-pipelines">
          <div className="build-panel-head"><span>{t("build.pipelines")}</span><span className="mono dim">{pipelines.length}</span></div>
          <div className="build-pipeline-list">
            {pipelines.map((pipeline) => {
              const active = pipeline.id === selectedId
              return (
                <button key={pipeline.id} className={`build-pipeline-item ${active ? "active" : ""}`} onClick={() => setSelectedId(pipeline.id)}>
                  <span className={`build-source-mark ${pipeline.sourceType}`}>{sourceGlyph(pipeline.sourceType)}</span>
                  <span className="col flex-1" style={{ gap: 3, minWidth: 0 }}>
                    <span className="truncate" style={{ fontWeight: 500 }}>{pipeline.name}</span>
                    <span className="mono truncate dim" style={{ fontSize: 10 }}>{t("build.stageCount", { count: pipeline.stages.length })} · {hostnames.get(pipeline.agentId) ?? pipeline.agentId}</span>
                  </span>
                  <span className={`dot ${pipeline.enabled ? "ok" : "off"}`} />
                </button>
              )
            })}
            {!loading && pipelines.length === 0 && <div className="build-list-empty">{t("build.noPipelinesShort")}</div>}
          </div>
        </aside>

        <main className="build-main">
          {loading && !detail ? (
            <div className="card build-loading"><span className="dot pulse ok" />{t("common.loading")}</div>
          ) : !detail ? (
            <EmptyState
              icon={I.bolt({ size: 34 })}
              title={t("build.noPipelines")}
              desc={t("build.noPipelinesDesc")}
              action={<button className="btn btn-primary" onClick={() => setEditor("new")}>{t("build.createFirst")}</button>}
            />
          ) : (
            <>
              <section className="card build-identity">
                <div className="build-identity-main">
                  <span className={`build-source-mark large ${detail.sourceType}`}>{sourceGlyph(detail.sourceType)}</span>
                  <div className="col flex-1" style={{ gap: 5, minWidth: 0 }}>
                    <div className="row gap-2 build-title-row">
                      <h2>{detail.name}</h2>
                      <span className={`badge ${detail.enabled ? "ok" : ""}`}>{detail.enabled ? t("build.enabled") : t("build.disabled")}</span>
                      <span className="badge mono">{detail.runnerType === "docker" ? detail.containerImage : t("build.hostRunner")}</span>
                    </div>
                    <p>{detail.description || t("build.noDescription")}</p>
                    <div className="build-meta mono">
                      <span>{I.agents({ size: 12 })}{hostnames.get(detail.agentId) ?? detail.agentId}</span>
                      <span>{sourceIcon(detail.sourceType)}{sourceLabel(t, detail)}</span>
                      {detail.schedule && <span>{I.clock({ size: 12 })}{detail.schedule}</span>}
                    </div>
                  </div>
                  <div className="row gap-2 build-identity-actions">
                    <button className="btn" onClick={() => setEditor(detail)}>{I.edit({ size: 13 })}<span>{t("common.edit")}</span></button>
                    <button className="btn btn-primary" disabled={!detail.enabled} onClick={() => setRunOpen(true)}>{I.bolt({ size: 13 })}<span>{t("build.runNow")}</span></button>
                  </div>
                </div>
              </section>

              <PipelineBlueprint pipeline={detail} run={selectedRun} />

              <div className="build-lower-grid">
                <RunConsole
                  run={selectedRun}
                  onCancel={cancelRun}
                  onDownload={(id) => window.open(buildsApi.artifactDownloadUrl(id), "_blank", "noopener,noreferrer")}
                />
                <AutomationCard pipeline={detail} deployment={deployments.find((item) => item.id === detail.publishProjectId)} onRotate={rotateWebhook} />
              </div>

              <RunHistory runs={detail.runs ?? []} selectedId={selectedRun?.id} onSelect={setSelectedRun} />
            </>
          )}
        </main>
      </div>

      {editor && (
        <PipelineEditor
          pipeline={editor === "new" ? undefined : editor}
          agents={agents}
          deployments={deployments}
          onClose={() => setEditor(null)}
          onSaved={async (saved) => {
            setEditor(null)
            setSelectedId(saved.id)
            if (saved.webhookToken) setWebhookToken(saved.webhookToken)
            await Promise.all([loadOverview(), loadDetail(saved.id)])
          }}
        />
      )}
      {runOpen && detail && <RunPipelineModal pipeline={detail} onClose={() => setRunOpen(false)} onStarted={async (run) => { setRunOpen(false); setSelectedRun(run); await loadDetail(detail.id) }} />}
      {webhookToken && <SecretOnceModal token={webhookToken} onClose={() => setWebhookToken(null)} />}
    </div>
  )
}

function PipelineBlueprint({ pipeline, run }: { pipeline: BuildPipeline; run: BuildRun | null }) {
  const { t } = useTranslation()
  const stageStates = parseStageStates(run?.output ?? "")
  return (
    <section className="card build-blueprint">
      <div className="build-panel-head">
        <div className="row gap-2"><span>{t("build.orchestration")}</span><span className="badge mono">DAG</span></div>
        <span className="mono dim">{run ? `#${run.runNumber} · ${run.version}` : t("build.definitionView")}</span>
      </div>
      <div className="build-track" style={{ "--stage-count": pipeline.stages.length } as CSSProperties}>
        <div className="build-track-source">
          <span>{sourceIcon(pipeline.sourceType)}</span>
          <small>{t("build.source")}</small>
          <strong>{t(`build.sourceTypes.${pipeline.sourceType}`)}</strong>
        </div>
        <div className="build-stage-lane">
          {pipeline.stages.map((stage, index) => {
            const state = stageStates.get(stage.id) ?? (run?.status === "success" ? "done" : "idle")
            return (
              <div className={`build-stage-node ${state}`} key={stage.id}>
                <span className="build-stage-index mono">{state === "done" ? I.check({ size: 11 }) : state === "failed" ? I.x({ size: 10 }) : index + 1}</span>
                <div className="col" style={{ gap: 3, minWidth: 0 }}>
                  <strong className="truncate">{stage.name}</strong>
                  <span className="mono truncate">{stage.needs.length ? `← ${stage.needs.join(", ")}` : t("build.rootStage")}</span>
                </div>
                {stage.allowFailure && <span className="badge warn">{t("build.softFailure")}</span>}
              </div>
            )
          })}
        </div>
        <div className={`build-track-output ${run?.artifact ? "ready" : ""}`}>
          <span>{I.disk({ size: 15 })}</span>
          <small>{t("build.output")}</small>
          <strong className="truncate">{pipeline.artifactName}</strong>
        </div>
      </div>
    </section>
  )
}

function RunConsole({ run, onDownload, onCancel }: { run: BuildRun | null; onDownload: (id: string) => void; onCancel: (run: BuildRun) => void }) {
  const { t } = useTranslation()
  if (!run) return <section className="card build-console empty"><div>{I.term({ size: 18 })}</div><strong>{t("build.noRuns")}</strong><span>{t("build.noRunsDesc")}</span></section>
  const log = cleanRunOutput(run.output)
  return (
    <section className="card build-console">
      <div className="build-panel-head">
        <div className="row gap-2"><span>{t("build.liveConsole")}</span><span className={`badge ${statusTone(run.status)}`}>{t(`build.status.${run.status}`)}</span></div>
        <div className="row gap-2">
          <span className="mono dim">#{run.runNumber} · {triggerLabel(t, run.trigger)}</span>
          {!terminal(run.status) && <button className="btn btn-sm btn-danger" onClick={() => onCancel(run)}>{t("build.cancelRun")}</button>}
        </div>
      </div>
      <pre>{log || (terminal(run.status) ? t("build.noLogOutput") : t("build.waitingForAgent"))}</pre>
      {run.error && <div className="build-run-error">{run.error}</div>}
      {run.artifact && (
        <button className="build-artifact-bar" onClick={() => onDownload(run.artifact!.id)}>
          <span className="build-artifact-icon">{I.download({ size: 15 })}</span>
          <span className="col flex-1" style={{ gap: 2, minWidth: 0 }}><strong className="mono truncate">{run.artifact.name}</strong><small className="mono">{formatBytes(run.artifact.size)} · sha256:{run.artifact.sha256.slice(0, 12)}</small></span>
          {run.artifact.deploymentReleaseId && <span className="badge ok">{t("build.published")}</span>}
          {I.chev({ size: 12 })}
        </button>
      )}
    </section>
  )
}

function AutomationCard({ pipeline, deployment, onRotate }: { pipeline: BuildPipeline; deployment?: DeploymentProject; onRotate: () => void }) {
  const { t } = useTranslation()
  const webhookPath = `${window.location.origin}/api/build-webhooks/${pipeline.id}`
  return (
    <section className="card build-automation">
      <div className="build-panel-head"><span>{t("build.automation")}</span><span className={`dot ${pipeline.enabled ? "ok" : "off"}`} /></div>
      <div className="build-automation-body">
        <div className="build-automation-row">
          <span className="build-automation-icon">{I.clock({ size: 14 })}</span>
          <div className="col flex-1" style={{ gap: 2 }}><strong>{t("build.schedule")}</strong><span className="mono">{pipeline.schedule || t("build.manualOnly")}</span></div>
        </div>
        <div className="build-automation-row">
          <span className="build-automation-icon">{I.net({ size: 14 })}</span>
          <div className="col flex-1" style={{ gap: 2, minWidth: 0 }}><strong>{t("build.webhook")}</strong><span className="mono truncate" title={webhookPath}>{webhookPath}</span></div>
          <button className="btn btn-sm btn-ghost" onClick={onRotate}>{t("build.rotateToken")}</button>
        </div>
        <div className="build-automation-row">
          <span className="build-automation-icon">{I.arrowUp({ size: 14 })}</span>
          <div className="col flex-1" style={{ gap: 2 }}><strong>{t("build.afterSuccess")}</strong><span>{deployment ? t("build.publishTo", { name: deployment.name }) : t("build.keepArtifact")}</span></div>
        </div>
      </div>
    </section>
  )
}

function RunHistory({ runs, selectedId, onSelect }: { runs: BuildRun[]; selectedId?: string; onSelect: (run: BuildRun) => void }) {
  const { t } = useTranslation()
  return (
    <section className="card build-history">
      <div className="build-panel-head"><span>{t("build.runHistory")}</span><span className="mono dim">{runs.length}</span></div>
      {runs.length === 0 ? <div className="build-list-empty">{t("build.noRuns")}</div> : (
        <div className="build-history-list">
          {runs.map((run) => (
            <button key={run.id} className={run.id === selectedId ? "active" : ""} onClick={() => onSelect(run)}>
              <span className={`dot ${statusDot(run.status)}`} />
              <strong className="mono">#{run.runNumber}</strong>
              <span className="mono">{run.version}</span>
              <span className="badge">{triggerLabel(t, run.trigger)}</span>
              <span className="muted flex-1 truncate">{run.createdByName}</span>
              <span className="mono dim">{durationOf(run)}</span>
              <span className="mono dim">{formatDate(run.createdAt)}</span>
              {I.chev({ size: 12 })}
            </button>
          ))}
        </div>
      )}
    </section>
  )
}

function PipelineEditor({ pipeline, agents, deployments, onClose, onSaved }: { pipeline?: BuildPipeline; agents: Agent[]; deployments: DeploymentProject[]; onClose: () => void; onSaved: (pipeline: BuildPipeline) => void }) {
  const { t } = useTranslation()
  const [form, setForm] = useState<BuildPipelineInput>(() => pipelineToInput(pipeline, agents[0]?.id ?? "", t))
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [section, setSection] = useState<"source" | "flow" | "delivery">("source")
  const [gitStatus, setGitStatus] = useState<GitCredentialStatus | null>(null)
  const [gitStatusLoading, setGitStatusLoading] = useState(false)
  const [gitStatusError, setGitStatusError] = useState<string | null>(null)

  useEffect(() => {
    setGitStatus(null)
    setGitStatusError(null)
  }, [form.agentId])

  function set<K extends keyof BuildPipelineInput>(key: K, value: BuildPipelineInput[K]) { setForm((current) => ({ ...current, [key]: value })) }
  function suggest() { setForm((current) => ({ ...current, ...smartPreset(current.name, current.sourceUrl, current.artifactName, t) })) }
  function updateStage(index: number, patch: Partial<BuildStage>) { set("stages", form.stages.map((stage, i) => i === index ? { ...stage, ...patch } : stage)) }
  function moveStage(index: number, direction: -1 | 1) {
    const target = index + direction
    if (target < 0 || target >= form.stages.length) return
    const next = [...form.stages]; [next[index], next[target]] = [next[target], next[index]]; set("stages", next)
  }
  function removeStage(index: number) {
    const removed = form.stages[index].id
    set("stages", form.stages.filter((_, i) => i !== index).map((stage) => ({ ...stage, needs: stage.needs.filter((id) => id !== removed) })))
  }
  function addStage() {
    const id = uniqueStageId(form.stages, "stage")
    set("stages", [...form.stages, { id, name: t("build.newStage"), command: "", needs: form.stages.length ? [form.stages.at(-1)!.id] : [], allowFailure: false, timeoutSeconds: 0 }])
  }
  function addVariable() { set("variables", [...form.variables, { name: "", value: "", secret: false, required: false }]) }
  function setSourceAuth(patch: Partial<BuildPipelineInput["sourceAuth"]>) { set("sourceAuth", { ...form.sourceAuth, ...patch }) }
  async function rotateSshKey() {
    if (!pipeline) return
    setBusy(true); setError(null)
    try {
      const sourceAuth = await buildsApi.rotateSshKey(pipeline.id)
      set("sourceAuth", sourceAuth)
    } catch (reason) {
      setError(messageOf(reason))
    } finally {
      setBusy(false)
    }
  }

  async function inspectGitCredentials() {
    if (!form.agentId) return
    setGitStatusLoading(true)
    setGitStatusError(null)
    try {
      const result = await runAgentCommand(form.agentId, "BUILD_GIT_STATUS")
      setGitStatus(JSON.parse(result.output ?? "{}") as GitCredentialStatus)
    } catch (reason) {
      setGitStatus(null)
      setGitStatusError(messageOf(reason))
    } finally {
      setGitStatusLoading(false)
    }
  }

  async function save() {
    setBusy(true); setError(null)
    try {
      const saved = pipeline ? await buildsApi.updatePipeline(pipeline.id, form) : await buildsApi.createPipeline(form)
      onSaved(saved)
    } catch (reason) {
      setError(messageOf(reason))
    } finally {
      setBusy(false)
    }
  }

  const valid = form.name.trim() && form.agentId && form.stages.length > 0 && form.stages.every((stage) => stage.id && stage.name && stage.command) && form.artifactPattern && form.artifactName && (form.sourceType === "upload" || form.sourceUrl) && (form.runnerType === "host" || form.containerImage)
  return (
    <Modal
      title={pipeline ? t("build.editPipeline") : t("build.newPipeline")}
      subtitle={t("build.editorSubtitle")}
      onClose={onClose}
      width={920}
      footer={<><span className="muted flex-1" style={{ fontSize: 11 }}>{t("build.securityFootnote")}</span><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-primary btn-sm" disabled={!valid || busy} onClick={save}>{busy && <span className="dot pulse ok" />}{t("common.save")}</button></>}
    >
      <div className="build-editor-tabs tabs">
        {(["source", "flow", "delivery"] as const).map((key) => <button key={key} className={`tab ${section === key ? "active" : ""}`} onClick={() => setSection(key)}>{t(`build.editor.${key}`)}</button>)}
      </div>

      {section === "source" && (
        <div className="build-editor-section">
          <div className="build-section-heading"><div><strong>{t("build.identityAndSource")}</strong><span>{t("build.identityAndSourceDesc")}</span></div><button className="btn btn-sm" onClick={suggest}>{I.sparkle({ size: 12 })}<span>{t("build.smartSuggest")}</span></button></div>
          <div className="build-form-grid">
            <FormBlock label={t("build.pipelineName")}><input className="input" value={form.name} onChange={(event) => set("name", event.target.value)} placeholder="orders-release" /></FormBlock>
            <FormBlock label={t("build.buildAgent")}>
              <select className="select" value={form.agentId} onChange={(event) => set("agentId", event.target.value)}>
                {!form.agentId && <option value="" disabled>{t("build.noConnectedAgents")}</option>}
                {form.agentId && !agents.some((agent) => agent.id === form.agentId) && <option value={form.agentId}>{form.agentId} · {t("build.agentUnavailable")}</option>}
                {agents.map((agent) => <option value={agent.id} key={agent.id}>{agent.hostname} · {agent.os}/{agent.arch}</option>)}
              </select>
            </FormBlock>
            <div className="build-form-wide"><FormBlock label={t("build.description")}><input className="input" value={form.description} onChange={(event) => set("description", event.target.value)} placeholder={t("build.descriptionPlaceholder")} /></FormBlock></div>
          </div>
          <div className="build-source-options">
            {(["git", "url", "upload"] as const).map((source) => (
              <button key={source} className={form.sourceType === source ? "active" : ""} onClick={() => set("sourceType", source)}>
                <span>{sourceIcon(source)}</span><strong>{t(`build.sourceTypes.${source}`)}</strong><small>{t(`build.sourceTypeDesc.${source}`)}</small>
              </button>
            ))}
          </div>
          {form.sourceType !== "upload" ? (
            <div className="build-form-grid">
              <div className={form.sourceType === "url" ? "build-form-wide" : ""}><FormBlock label={form.sourceType === "git" ? t("build.repositoryUrl") : t("build.packageUrl")} hint={t("build.noEmbeddedCredentials")}><input className="input mono" value={form.sourceUrl} onChange={(event) => set("sourceUrl", event.target.value)} placeholder={form.sourceType === "git" ? "https://git.example.com/team/app.git" : "https://artifacts.example.com/source.tar.gz"} /></FormBlock></div>
              {form.sourceType === "git" && <FormBlock label={t("build.branchOrTag")}><input className="input mono" value={form.sourceRef} onChange={(event) => set("sourceRef", event.target.value)} placeholder="main" /></FormBlock>}
            </div>
          ) : <div className="build-upload-note">{I.arrowUp({ size: 16 })}<span><strong>{t("build.uploadAtRun")}</strong>{t("build.uploadAtRunDesc")}</span></div>}
          {form.sourceType === "git" && (
            <>
              <div className="build-form-grid">
                <FormBlock label={t("build.gitAuth")} hint={t("build.gitAuthHint")}>
                  <select className="select" value={form.sourceAuth.type} onChange={(event) => setSourceAuth({ type: event.target.value as "none" | "basic" | "ssh", password: "" })}>
                    <option value="none">{t("build.gitAuthNone")}</option>
                    <option value="basic">{t("build.gitAuthBasic")}</option>
                    <option value="ssh">{t("build.gitAuthSsh")}</option>
                  </select>
                </FormBlock>
                {form.sourceAuth.type === "basic" && <>
                  <FormBlock label={t("build.gitUsername")}><input className="input mono" value={form.sourceAuth.username ?? ""} onChange={(event) => setSourceAuth({ username: event.target.value })} /></FormBlock>
                  <FormBlock label={t("build.gitPassword")} hint={pipeline && form.sourceAuth.credentialConfigured ? t("build.secretUnchanged") : undefined}><input className="input mono" type="password" value={form.sourceAuth.password ?? ""} onChange={(event) => setSourceAuth({ password: event.target.value })} /></FormBlock>
                </>}
                {form.sourceAuth.type === "ssh" && <>
                  <div className="build-form-wide"><FormBlock label={t("build.sshPublicKey")} hint={t("build.sshPublicKeyHint")}><textarea className="textarea mono" rows={3} readOnly value={form.sourceAuth.sshPublicKey ?? t("build.sshPublicKeyAfterSave")} /></FormBlock></div>
                  <div className="build-form-wide"><FormBlock label={t("build.sshKnownHosts")} hint={t("build.sshKnownHostsHint")}><textarea className="textarea mono" rows={3} value={form.sourceAuth.sshKnownHosts ?? ""} onChange={(event) => setSourceAuth({ sshKnownHosts: event.target.value })} placeholder="git.example.com ssh-ed25519 AAAA…" /></FormBlock></div>
                  {pipeline && <button className="btn btn-sm" type="button" disabled={busy} onClick={rotateSshKey}>{I.refresh({ size: 12 })}<span>{t("build.rotateSshKey")}</span></button>}
                </>}
              </div>
              {form.sourceAuth.type === "none" && <GitCredentialCard status={gitStatus} loading={gitStatusLoading} error={gitStatusError} disabled={!form.agentId} onInspect={inspectGitCredentials} />}
            </>
          )}
        </div>
      )}

      {section === "flow" && (
        <div className="build-editor-section">
          <div className="build-section-heading"><div><strong>{t("build.runnerAndStages")}</strong><span>{t("build.runnerAndStagesDesc")}</span></div><button className="btn btn-sm" onClick={addStage}>{I.plus({ size: 12 })}<span>{t("build.addStage")}</span></button></div>
          <div className="build-runner-row">
            <FormBlock label={t("build.runnerType")}><select className="select" value={form.runnerType} onChange={(event) => set("runnerType", event.target.value as "docker" | "host")}><option value="docker">Docker · {t("build.recommended")}</option><option value="host">Host · {t("build.optInRequired")}</option></select></FormBlock>
            {form.runnerType === "docker" && <FormBlock label={t("build.containerImage")}><input className="input mono" value={form.containerImage} onChange={(event) => set("containerImage", event.target.value)} placeholder="node:22-alpine" /></FormBlock>}
            <FormBlock label={t("build.totalTimeout")}><input className="input mono" type="number" min={30} max={86400} value={form.timeoutSeconds} onChange={(event) => set("timeoutSeconds", Number(event.target.value))} /></FormBlock>
          </div>
          <div className="build-stage-editor">
            {form.stages.map((stage, index) => (
              <div className="build-stage-edit" key={`${stage.id}-${index}`}>
                <div className="build-stage-toolbar">
                  <span className="build-stage-grip">{I.drag({ size: 14 })}</span><span className="mono build-stage-number">{String(index + 1).padStart(2, "0")}</span>
                  <input className="input" value={stage.name} onChange={(event) => updateStage(index, { name: event.target.value })} placeholder={t("build.stageName")} />
                  <input className="input mono" value={stage.id} onChange={(event) => updateStage(index, { id: event.target.value })} placeholder="stage-id" />
                  <button className="btn btn-sm btn-ghost btn-icon" title={t("common.moveUp")} aria-label={t("common.moveUp")} disabled={index === 0} onClick={() => moveStage(index, -1)}>{I.arrowUp({ size: 11 })}</button>
                  <button className="btn btn-sm btn-ghost btn-icon" title={t("common.moveDown")} aria-label={t("common.moveDown")} disabled={index === form.stages.length - 1} onClick={() => moveStage(index, 1)}>{I.arrowDown({ size: 11 })}</button>
                  <button className="btn btn-sm btn-ghost btn-icon" title={t("common.delete")} aria-label={t("common.delete")} disabled={form.stages.length === 1} onClick={() => removeStage(index)}><span style={{ color: "var(--crit)" }}>{I.trash({ size: 11 })}</span></button>
                </div>
                <textarea className="textarea mono" rows={3} value={stage.command} onChange={(event) => updateStage(index, { command: event.target.value })} placeholder="npm ci && npm test" />
                <div className="build-stage-options">
                  <span>{t("build.dependsOn")}</span>
                  <div className="build-need-chips">
                    {form.stages.filter((_, candidate) => candidate !== index).map((candidate) => {
                      const active = stage.needs.includes(candidate.id)
                      return <button key={candidate.id} className={active ? "active" : ""} onClick={() => updateStage(index, { needs: active ? stage.needs.filter((id) => id !== candidate.id) : [...stage.needs, candidate.id] })}>{candidate.id}</button>
                    })}
                    {form.stages.length === 1 && <span className="dim">{t("build.none")}</span>}
                  </div>
                  <label className="build-check"><input type="checkbox" checked={stage.allowFailure} onChange={(event) => updateStage(index, { allowFailure: event.target.checked })} />{t("build.allowFailure")}</label>
                  <label className="build-stage-timeout"><span>{t("build.stageTimeout")}</span><input className="input mono" type="number" min={0} max={86400} value={stage.timeoutSeconds} onChange={(event) => updateStage(index, { timeoutSeconds: Number(event.target.value) })} /></label>
                </div>
              </div>
            ))}
          </div>
          <div className="build-section-heading variable-heading"><div><strong>{t("build.variables")}</strong><span>{t("build.variablesDesc")}</span></div><button className="btn btn-sm" onClick={addVariable}>{I.plus({ size: 12 })}<span>{t("build.addVariable")}</span></button></div>
          <div className="build-variable-list">
            {form.variables.map((variable, index) => (
              <div key={index} className="build-variable-row">
                <input className="input mono" value={variable.name} onChange={(event) => set("variables", form.variables.map((item, i) => i === index ? { ...item, name: event.target.value } : item))} placeholder="BUILD_MODE" />
                <input className="input mono" type={variable.secret ? "password" : "text"} value={variable.value ?? ""} onChange={(event) => set("variables", form.variables.map((item, i) => i === index ? { ...item, value: event.target.value } : item))} placeholder={variable.secret && pipeline ? t("build.secretUnchanged") : t("build.variableValue")} />
                <label className="build-check"><input type="checkbox" checked={variable.secret} onChange={(event) => set("variables", form.variables.map((item, i) => i === index ? { ...item, secret: event.target.checked } : item))} />{t("build.secret")}</label>
                <label className="build-check"><input type="checkbox" checked={variable.required} onChange={(event) => set("variables", form.variables.map((item, i) => i === index ? { ...item, required: event.target.checked } : item))} />{t("build.required")}</label>
                <button className="btn btn-sm btn-ghost btn-icon" title={t("common.delete")} aria-label={t("common.delete")} onClick={() => set("variables", form.variables.filter((_, i) => i !== index))}>{I.x({ size: 11 })}</button>
              </div>
            ))}
            {form.variables.length === 0 && <div className="build-inline-empty">{t("build.noVariables")}</div>}
          </div>
        </div>
      )}

      {section === "delivery" && (
        <div className="build-editor-section">
          <div className="build-section-heading"><div><strong>{t("build.artifactAndAutomation")}</strong><span>{t("build.artifactAndAutomationDesc")}</span></div></div>
          <div className="build-form-grid">
            <FormBlock label={t("build.artifactPattern")} hint={t("build.oneArtifactOnly")}><input className="input mono" value={form.artifactPattern} onChange={(event) => set("artifactPattern", event.target.value)} placeholder="dist/*.tar.gz" /></FormBlock>
            <FormBlock label={t("build.artifactName")}><input className="input mono" value={form.artifactName} onChange={(event) => set("artifactName", event.target.value)} placeholder="app.tar.gz" /></FormBlock>
            <FormBlock label={t("build.keepArtifacts")} hint={t("build.keepArtifactsHint")}><input className="input mono" type="number" min={1} max={200} value={form.keepArtifacts} onChange={(event) => set("keepArtifacts", Number(event.target.value))} /></FormBlock>
            <FormBlock label={t("build.cronSchedule")} hint={t("build.serverLocalTime")}><input className="input mono" value={form.schedule} onChange={(event) => set("schedule", event.target.value)} placeholder="0 2 * * 1-5" /></FormBlock>
            <FormBlock label={t("build.publishTarget")} hint={t("build.publishTargetHint")}><select className="select" value={form.publishProjectId ?? ""} onChange={(event) => set("publishProjectId", event.target.value ? Number(event.target.value) : null)}><option value="">{t("build.artifactOnly")}</option>{deployments.map((project) => <option value={project.id} key={project.id}>{project.name} · {project.type}</option>)}</select></FormBlock>
          </div>
          <div className="build-delivery-preview">
            <div><span>{I.bolt({ size: 15 })}</span><strong>{t("build.triggerManual")}</strong><small>{t("build.triggerManualDesc")}</small></div>
            <div><span>{I.net({ size: 15 })}</span><strong>{t("build.triggerWebhook")}</strong><small>{t("build.triggerWebhookDesc")}</small></div>
            <div className={form.schedule ? "active" : ""}><span>{I.clock({ size: 15 })}</span><strong>{t("build.triggerSchedule")}</strong><small>{form.schedule || t("build.notConfigured")}</small></div>
            <div className={form.publishProjectId ? "active" : ""}><span>{I.arrowUp({ size: 15 })}</span><strong>{t("build.autoPublish")}</strong><small>{form.publishProjectId ? deployments.find((item) => item.id === form.publishProjectId)?.name : t("build.notConfigured")}</small></div>
          </div>
          <label className="build-enable-toggle"><input type="checkbox" checked={form.enabled} onChange={(event) => set("enabled", event.target.checked)} /><span><strong>{t("build.enablePipeline")}</strong><small>{t("build.enablePipelineDesc")}</small></span></label>
        </div>
      )}
      {error && <div className="build-modal-error">{error}</div>}
    </Modal>
  )
}

function GitCredentialCard({ status, loading, error, disabled, onInspect }: { status: GitCredentialStatus | null; loading: boolean; error: string | null; disabled: boolean; onInspect: () => void }) {
  const { t } = useTranslation()
  const [copied, setCopied] = useState<string | null>(null)
  const ready = !!status && (!!status.credentialHelper || status.sshAgent || status.publicKeys.length > 0)
  async function copyKey(name: string, key: string) {
    await navigator.clipboard.writeText(key)
    setCopied(name)
  }
  return (
    <section className="build-git-card" aria-live="polite">
      <div className="build-git-head">
        <div className="row gap-2"><span>{I.lock({ size: 14 })}</span><div className="col"><strong>{t("build.gitCredentials")}</strong><small>{t("build.gitCredentialsDesc")}</small></div></div>
        <button type="button" className="btn btn-sm" disabled={disabled || loading} onClick={onInspect}>{loading ? <span className="dot pulse ok" /> : I.refresh({ size: 12 })}<span>{t("build.inspectCredentials")}</span></button>
      </div>
      {error ? <div className="build-git-error" role="alert"><strong>{t("build.credentialCheckFailed")}</strong><span>{error}</span><small>{t("build.credentialCheckFix")}</small></div> : status ? (
        <div className="build-git-body">
          <div className="build-git-summary"><span className={`dot ${ready ? "ok" : "warn"}`} /><strong>{ready ? t("build.credentialsReady") : t("build.credentialsMissing")}</strong><span className="mono dim">{status.username || "—"} · {status.gitVersion || "git unavailable"}</span></div>
          <div className="build-git-methods">
            <span><small>{t("build.httpsCredentialHelper")}</small><strong className="mono">{status.credentialHelper || t("build.notConfigured")}</strong></span>
            <span><small>{t("build.sshAgent")}</small><strong>{status.sshAgent ? t("common.on") : t("common.off")}</strong></span>
            <span><small>{t("build.sshPublicKeys")}</small><strong className="mono">{status.publicKeys.length}</strong></span>
          </div>
          {status.publicKeys.length ? <div className="build-public-keys">{status.publicKeys.map((item) => <div key={item.name}><span className="mono">{item.name}</span><code title={item.key}>{item.key}</code><button type="button" className="btn btn-sm" onClick={() => copyKey(item.name, item.key)}>{copied === item.name ? I.check({ size: 11 }) : I.copy({ size: 11 })}<span>{copied === item.name ? t("common.copied") : t("build.copyPublicKey")}</span></button></div>)}</div> : <div className="build-git-empty">{t("build.noPublicKeyFix")}</div>}
        </div>
      ) : <div className="build-git-empty">{t("build.inspectCredentialsHint")}</div>}
    </section>
  )
}

function RunPipelineModal({ pipeline, onClose, onStarted }: { pipeline: BuildPipeline; onClose: () => void; onStarted: (run: BuildRun) => void }) {
  const { t } = useTranslation()
  const inputRef = useRef<HTMLInputElement>(null)
  const [version, setVersion] = useState(guessVersion())
  const [file, setFile] = useState<File | null>(null)
  const [dragging, setDragging] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  async function start() {
    setBusy(true); setError(null)
    try {
      const run = pipeline.sourceType === "upload" ? await buildsApi.uploadAndRun(pipeline.id, version, file!) : await buildsApi.run(pipeline.id, version)
      onStarted(run)
    } catch (reason) { setError(messageOf(reason)) } finally { setBusy(false) }
  }
  return (
    <Modal title={t("build.runPipeline")} subtitle={`${pipeline.name} · ${t("build.stageCount", { count: pipeline.stages.length })}`} onClose={onClose} width={620} footer={<><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-primary btn-sm" disabled={busy || !version || (pipeline.sourceType === "upload" && !file)} onClick={start}>{busy && <span className="dot pulse ok" />}{t("build.startBuild")}</button></>}>
      <div className="col gap-4">
        <FormBlock label={t("build.version")} hint={t("build.versionHint")}><input className="input mono" value={version} onChange={(event) => setVersion(event.target.value)} /></FormBlock>
        {pipeline.sourceType === "upload" && (
          <button className={`build-drop ${dragging ? "dragging" : ""}`} onClick={() => inputRef.current?.click()} onDragOver={(event) => { event.preventDefault(); setDragging(true) }} onDragLeave={() => setDragging(false)} onDrop={(event) => { event.preventDefault(); setDragging(false); setFile(event.dataTransfer.files[0] ?? null) }}>
            <input ref={inputRef} type="file" accept=".zip,.tar,.tar.gz,.tgz" hidden onChange={(event) => setFile(event.target.files?.[0] ?? null)} />
            <span className="build-drop-icon">{file ? I.check({ size: 20 }) : I.arrowUp({ size: 20 })}</span>
            <strong>{file ? file.name : t("build.dropSource")}</strong>
            <span>{file ? formatBytes(file.size) : t("build.dropSourceHint")}</span>
          </button>
        )}
        <div className="build-run-summary">
          <span>{sourceIcon(pipeline.sourceType)}</span><div><strong>{t("build.source")}</strong><small className="mono">{sourceLabel(t, pipeline)}</small></div>
          <span>{pipeline.runnerType === "docker" ? I.disk({ size: 14 }) : I.term({ size: 14 })}</span><div><strong>{t("build.runnerType")}</strong><small className="mono">{pipeline.runnerType === "docker" ? pipeline.containerImage : t("build.hostRunner")}</small></div>
        </div>
      </div>
      {error && <div className="build-modal-error">{error}</div>}
    </Modal>
  )
}

function SecretOnceModal({ token, onClose }: { token: string; onClose: () => void }) {
  const { t } = useTranslation()
  const [copied, setCopied] = useState(false)
  return (
    <Modal title={t("build.webhookTokenReady")} subtitle={t("build.webhookTokenOnce")} onClose={onClose} width={560} footer={<button className="btn btn-primary btn-sm" onClick={onClose}>{t("common.done")}</button>}>
      <div className="build-secret-once"><span>{I.lock({ size: 18 })}</span><code>{token}</code><button className="btn btn-sm" onClick={async () => { await navigator.clipboard.writeText(token); setCopied(true) }}>{copied ? I.check({ size: 12 }) : I.copy({ size: 12 })}<span>{copied ? t("common.copied") : t("common.copy")}</span></button></div>
    </Modal>
  )
}

function pipelineToInput(pipeline: BuildPipeline | undefined, agentId: string, t: (key: string) => string): BuildPipelineInput {
  return pipeline ? {
    name: pipeline.name, description: pipeline.description, agentId: pipeline.agentId,
    sourceType: pipeline.sourceType, sourceUrl: pipeline.sourceUrl, sourceRef: pipeline.sourceRef,
    sourceAuth: { ...pipeline.sourceAuth, password: "" },
    runnerType: pipeline.runnerType, containerImage: pipeline.containerImage,
    stages: pipeline.stages.map((stage) => ({ ...stage, needs: [...stage.needs] })), variables: pipeline.variables.map((variable) => ({ ...variable, value: "" })),
    artifactPattern: pipeline.artifactPattern, artifactName: pipeline.artifactName,
    keepArtifacts: pipeline.keepArtifacts ?? 20,
    publishProjectId: pipeline.publishProjectId ?? null, timeoutSeconds: pipeline.timeoutSeconds,
    schedule: pipeline.schedule, enabled: pipeline.enabled,
  } : {
    name: "", description: "", agentId, sourceType: "git", sourceUrl: "", sourceRef: "main",
    sourceAuth: { type: "none", username: "", password: "", sshKnownHosts: "" },
    runnerType: "docker", containerImage: "node:22-alpine",
    stages: nodePreset(t).stages, variables: [], artifactPattern: "app.tar.gz", artifactName: "app.tar.gz",
    keepArtifacts: 20,
    publishProjectId: null, timeoutSeconds: 1800, schedule: "", enabled: true,
  }
}

function smartPreset(name: string, sourceUrl: string, artifactName: string, t: (key: string) => string): Partial<BuildPipelineInput> {
  const hint = `${name} ${sourceUrl} ${artifactName}`.toLowerCase()
  if (/java|spring|maven|\.jar/.test(hint)) return mavenPreset(t)
  if (/golang|\bgo\b|go-/.test(hint)) return goPreset(t)
  if (/static|web|frontend|portal/.test(hint)) return staticPreset(t)
  return { ...nodePreset(t), description: t("build.suggestedDescription") }
}

function nodePreset(t: (key: string) => string) { return { containerImage: "node:22-alpine", artifactPattern: "app.tar.gz", artifactName: "app.tar.gz", stages: [stage("install", t("build.stageNames.install"), "npm ci"), stage("test", t("build.stageNames.test"), "npm test -- --run", ["install"]), stage("package", t("build.stageNames.package"), "npm run build && tar -czf app.tar.gz dist", ["test"])] } }
function mavenPreset(t: (key: string) => string) { return { containerImage: "maven:3.9-eclipse-temurin-21", artifactPattern: "target/*.jar", artifactName: "app.jar", stages: [stage("verify", t("build.stageNames.verify"), "mvn -B clean verify"), stage("package", t("build.stageNames.package"), "mvn -B -DskipTests package", ["verify"])] } }
function goPreset(t: (key: string) => string) { return { containerImage: "golang:1.24-alpine", artifactPattern: "app.tar.gz", artifactName: "app.tar.gz", stages: [stage("test", t("build.stageNames.test"), "go test ./..."), stage("build", t("build.stageNames.build"), "mkdir -p dist && CGO_ENABLED=0 go build -o dist/app ./...", ["test"]), stage("package", t("build.stageNames.package"), "tar -czf app.tar.gz -C dist app", ["build"])] } }
function staticPreset(t: (key: string) => string) { return { containerImage: "node:22-alpine", artifactPattern: "site.tar.gz", artifactName: "site.tar.gz", stages: [stage("install", t("build.stageNames.install"), "npm ci"), stage("quality", t("build.stageNames.quality"), "npm run lint && npm test -- --run", ["install"], true), stage("build", t("build.stageNames.build"), "npm run build", ["quality"]), stage("package", t("build.stageNames.package"), "tar -czf site.tar.gz dist", ["build"])] } }
function stage(id: string, name: string, command: string, needs: string[] = [], allowFailure = false): BuildStage { return { id, name, command, needs, allowFailure, timeoutSeconds: 0 } }

function uniqueStageId(stages: BuildStage[], base: string) { let id = base; let i = 2; while (stages.some((stage) => stage.id === id)) id = `${base}-${i++}`; return id }
function parseStageStates(output: string) { const states = new Map<string, "active" | "done" | "failed" | "warning">(); for (const line of output.split("\n")) { const match = line.match(/^\[stage:(start|done|failed|warning|canceled)\]\s+(\S+)/); if (match) states.set(match[2], match[1] === "start" ? "active" : match[1] === "canceled" ? "failed" : match[1] as "done" | "failed" | "warning") } return states }
function cleanRunOutput(output: string) { return output.split("\n").filter((line) => line.startsWith("[log]")).map((line) => line.replace(/^\[log\]\s?/, "")).join("\n") }
function sourceGlyph(type: BuildPipeline["sourceType"]) { return type === "git" ? "GIT" : type === "url" ? "URL" : "UP" }
function sourceIcon(type: BuildPipeline["sourceType"]) { return type === "git" ? I.group({ size: 14 }) : type === "url" ? I.globe({ size: 14 }) : I.arrowUp({ size: 14 }) }
function sourceLabel(t: (key: string, options?: Record<string, unknown>) => string, pipeline: Pick<BuildPipeline, "sourceType" | "sourceUrl" | "sourceRef">) { if (pipeline.sourceType === "upload") return t("build.sourceTypes.upload"); if (pipeline.sourceType === "url") return pipeline.sourceUrl; return `${pipeline.sourceUrl}${pipeline.sourceRef ? ` · ${pipeline.sourceRef}` : ""}` }
function triggerLabel(t: (key: string) => string, trigger: BuildRun["trigger"]) { return t(`build.triggers.${trigger}`) }
function statusTone(status: BuildRun["status"]) { return status === "success" ? "ok" : status === "failed" ? "crit" : "warn" }
function statusDot(status: BuildRun["status"]) { return status === "success" ? "ok" : status === "failed" ? "crit" : status === "canceled" ? "off" : "warn pulse" }
function durationOf(run: BuildRun) { if (!run.startedAt) return "—"; const end = run.finishedAt ? new Date(run.finishedAt).getTime() : Date.now(); const seconds = Math.max(0, Math.round((end - new Date(run.startedAt).getTime()) / 1000)); return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m ${seconds % 60}s` }
function formatDate(value: string) { return value ? new Date(value).toLocaleString(undefined, { month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—" }
function formatBytes(bytes: number) { if (bytes < 1024) return `${bytes} B`; const units = ["KB", "MB", "GB"]; let value = bytes / 1024; let i = 0; while (value >= 1024 && i < units.length - 1) { value /= 1024; i++ } return `${value.toFixed(value >= 10 ? 1 : 2)} ${units[i]}` }
function guessVersion() { const now = new Date(); return `${now.getFullYear()}.${String(now.getMonth() + 1).padStart(2, "0")}.${String(now.getDate()).padStart(2, "0")}-${String(now.getHours()).padStart(2, "0")}${String(now.getMinutes()).padStart(2, "0")}` }
function messageOf(error: unknown) { return (error as ApiError)?.error || (error instanceof Error ? error.message : String(error)) }
