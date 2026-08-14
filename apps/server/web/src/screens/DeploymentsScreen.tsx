import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useTranslation } from "react-i18next"
import { agentsApi, deploymentsApi, type Agent, type ApiError, type DeploymentProject, type DeploymentProjectDetail, type DeploymentProjectInput, type DeploymentRelease, type DeploymentTask } from "@/lib/api"
import { I } from "@/lib/icons"
import { ConfirmDialog, Modal } from "@/components/shell/Dialog"
import { EmptyState, FormBlock, PageHeader } from "@/components/shell/primitives"
import "./deployments.css"
import { completedDeploymentSteps, DEPLOYMENT_STEPS } from "@/lib/fleet"
import { findReconciledDeploymentTask } from "@/lib/deployment"

const terminal = (status?: string) => status === "success" || status === "failed"

export function DeploymentsScreen() {
  const { t } = useTranslation()
  const [projects, setProjects] = useState<DeploymentProject[]>([])
  const [agents, setAgents] = useState<Agent[]>([])
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [detail, setDetail] = useState<DeploymentProjectDetail | null>(null)
  const [liveTask, setLiveTask] = useState<DeploymentTask | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [projectModal, setProjectModal] = useState<DeploymentProject | null | "new">(null)
  const [uploadOpen, setUploadOpen] = useState(false)
  const [confirm, setConfirm] = useState<{ release: DeploymentRelease; action: "deploy" | "rollback" } | null>(null)
  const [busy, setBusy] = useState(false)

  const loadProjects = useCallback(async () => {
    setLoading(true)
    try {
      const [projectRows, agentRows] = await Promise.all([deploymentsApi.projects(), agentsApi.list()])
      setProjects(projectRows)
      setAgents(agentRows)
      setSelectedId((current) => current ?? projectRows[0]?.id ?? null)
      setError(null)
    } catch (e) {
      setError(messageOf(e))
    } finally {
      setLoading(false)
    }
  }, [])

  const loadDetail = useCallback(async (id: number) => {
    try {
      const data = await deploymentsApi.project(id)
      setDetail(data)
      const running = data.deployments.find((d) => !terminal(d.status))
      setLiveTask(running ?? data.deployments[0] ?? null)
      setError(null)
    } catch (e) {
      setError(messageOf(e))
    }
  }, [])

  useEffect(() => { loadProjects() }, [loadProjects])
  useEffect(() => {
    if (selectedId) loadDetail(selectedId)
    else setDetail(null)
  }, [selectedId, loadDetail])

  const liveTaskId = liveTask?.id
  const liveTaskStatus = liveTask?.status
  useEffect(() => {
    if (!liveTaskId || terminal(liveTaskStatus)) return
    const timer = window.setInterval(async () => {
      try {
        const next = await deploymentsApi.task(liveTaskId)
        setLiveTask(next)
        if (terminal(next.status) && selectedId) {
          window.clearInterval(timer)
          await Promise.all([loadDetail(selectedId), loadProjects()])
        }
      } catch (e) {
        setError(messageOf(e))
      }
    }, 1600)
    return () => window.clearInterval(timer)
  }, [liveTaskId, liveTaskStatus, selectedId, loadDetail, loadProjects])

  const hostname = useMemo(() => new Map(agents.map((a) => [a.id, a.hostname])), [agents])
  const currentRelease = detail?.releases.find((r) => r.id === detail.currentReleaseId)
  const currentExtract = currentRelease?.extract ?? detail?.extractArchive ?? true

  async function runRelease() {
    if (!detail || !confirm) return
    const requestedProject = detail
    const requestedRelease = confirm.release
    const requestedAction = confirm.action
    const knownTaskIds = new Set(detail.deployments.map((task) => task.id))
    setBusy(true)
    try {
      const task = requestedAction === "deploy"
        ? await deploymentsApi.deploy(requestedProject.id, requestedRelease.id)
        : await deploymentsApi.rollback(requestedProject.id, requestedRelease.id)
      setLiveTask(task)
      setDetail({ ...requestedProject, deployments: [task, ...requestedProject.deployments] })
      setConfirm(null)
      setError(null)
    } catch (e) {
      let reconciled: { project: DeploymentProjectDetail; task: DeploymentTask } | null = null
      for (const delay of [0, 350, 900, 1800]) {
        if (delay) await new Promise((resolve) => window.setTimeout(resolve, delay))
        try {
          const project = await deploymentsApi.project(requestedProject.id)
          const task = findReconciledDeploymentTask(
            project.deployments,
            knownTaskIds,
            requestedRelease.id,
            requestedAction,
          )
          if (task) {
            reconciled = { project, task }
            break
          }
        } catch {
          // Preserve the original dispatch error if state reconciliation also fails.
        }
      }
      if (reconciled) {
        setDetail(reconciled.project)
        setLiveTask(reconciled.task)
        setError(null)
      } else {
        setError(messageOf(e))
      }
      setConfirm(null)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="col deploy-page">
      <PageHeader
        eyebrow={t("deploy.eyebrow")}
        title={t("deploy.title")}
        subtitle={t("deploy.subtitle")}
        actions={
          <>
            <button className="btn" onClick={loadProjects}>{I.refresh({ size: 13 })}<span>{t("common.refresh")}</span></button>
            <button className="btn btn-primary" onClick={() => setProjectModal("new")}>{I.plus({ size: 13 })}<span>{t("deploy.newProject")}</span></button>
          </>
        }
      />

      {error && <div className="deploy-alert"><span>{I.warn({ size: 14 })}</span><span>{error}</span><button onClick={() => setError(null)}>{I.x({ size: 12 })}</button></div>}

      <div className="deploy-grid">
        <aside className="card deploy-projects">
          <div className="deploy-panel-head">
            <span>{t("deploy.projects")}</span>
            <span className="mono dim">{projects.length}</span>
          </div>
          <div className="deploy-project-list">
            {projects.map((project) => {
              const active = project.id === selectedId
              return (
                <button key={project.id} className={`deploy-project ${active ? "active" : ""}`} onClick={() => setSelectedId(project.id)}>
                  <span className={`deploy-project-mark ${project.type}`}>{project.type === "java" ? "J" : "S"}</span>
                  <span className="col flex-1" style={{ gap: 2, minWidth: 0 }}>
                    <span className="truncate" style={{ fontWeight: 500 }}>{project.name}</span>
                    <span className="mono truncate dim" style={{ fontSize: 10.5 }}>{hostname.get(project.agentId) ?? project.agentId}</span>
                  </span>
                  <span className={`dot ${project.currentReleaseId ? "ok" : "off"}`} />
                </button>
              )
            })}
            {!loading && projects.length === 0 && <div className="deploy-list-empty">{t("deploy.noProjectsShort")}</div>}
          </div>
        </aside>

        <main className="deploy-main">
          {loading && !detail ? (
            <div className="card deploy-loading"><span className="dot pulse ok" /> {t("common.loading")}</div>
          ) : !detail ? (
            <EmptyState
              icon={I.bolt({ size: 34 })}
              title={t("deploy.noProjects")}
              desc={t("deploy.noProjectsDesc")}
              action={<button className="btn btn-primary" onClick={() => setProjectModal("new")}>{t("deploy.createFirst")}</button>}
            />
          ) : (
            <>
              <section className="card deploy-identity">
                <div className="deploy-identity-main">
                  <div className={`deploy-project-mark large ${detail.type}`}>{detail.type === "java" ? "JVM" : "WEB"}</div>
                  <div className="col flex-1" style={{ gap: 4 }}>
                    <div className="row gap-2" style={{ flexWrap: "wrap" }}>
                      <h2>{detail.name}</h2>
                      <span className="badge">{detail.type === "java" ? t("deploy.typeJava") : t("deploy.typeStatic")}</span>
                      <span className={`badge ${currentRelease ? "ok" : "warn"}`}>{currentRelease ? `v${currentRelease.version}` : t("deploy.notDeployed")}</span>
                    </div>
                    <div className="deploy-meta mono">
                      <span>{I.agents({ size: 12 })} {hostname.get(detail.agentId) ?? detail.agentId}</span>
                      <span>{I.disk({ size: 12 })} {detail.deployPath}</span>
                      {detail.type === "static" && <span>{currentExtract ? I.expand({ size: 12 }) : I.disk({ size: 12 })} {t(currentExtract ? "deploy.extractEnabled" : "deploy.extractDisabled")}</span>}
                      {detail.serviceName && <span>{I.power({ size: 12 })} {detail.serviceName}</span>}
                    </div>
                  </div>
                  <div className="row gap-2 deploy-identity-actions">
                    <button className="btn" onClick={() => setProjectModal(detail)}>{I.settings({ size: 13 })}<span>{t("common.edit")}</span></button>
                    <button className="btn btn-primary" onClick={() => setUploadOpen(true)}>{I.arrowUp({ size: 13 })}<span>{t("deploy.uploadRelease")}</span></button>
                  </div>
                </div>
              </section>

              <DeploymentRail task={liveTask} />

              <section className="card deploy-releases">
                <div className="deploy-panel-head">
                  <div className="row gap-2"><span>{t("deploy.releases")}</span><span className="mono dim">{detail.releases.length}</span></div>
                  <span className="hint">{t("deploy.releaseHint")}</span>
                </div>
                {detail.releases.length === 0 ? (
                  <div className="deploy-empty-release">
                    <span>{I.arrowUp({ size: 24 })}</span>
                    <strong>{t("deploy.noReleases")}</strong>
                    <span>{t("deploy.noReleasesDesc")}</span>
                    <button className="btn btn-primary btn-sm" onClick={() => setUploadOpen(true)}>{t("deploy.uploadRelease")}</button>
                  </div>
                ) : (
                  <div style={{ overflow: "auto" }}>
                    <table className="tbl deploy-release-table">
                      <thead><tr><th>{t("deploy.version")}</th><th>{t("deploy.artifact")}</th><th>{t("deploy.digest")}</th><th>{t("deploy.created")}</th><th>{t("deploy.notes")}</th><th /></tr></thead>
                      <tbody>
                        {detail.releases.map((release) => {
                          const isCurrent = release.id === detail.currentReleaseId
                          const wasDeployed = detail.deployments.some((d) => d.releaseId === release.id && d.status === "success")
                          const action: "deploy" | "rollback" = wasDeployed ? "rollback" : "deploy"
                          return (
                            <tr key={release.id}>
                              <td><div className="row gap-2"><span className={`dot ${isCurrent ? "ok" : "off"}`} /><strong className="mono">{release.version}</strong>{isCurrent && <span className="badge ok">{t("deploy.currentRelease")}</span>}</div></td>
                              <td><div className="col" style={{ gap: 2 }}><span className="mono">{release.artifactName}</span><span className="dim mono" style={{ fontSize: 10 }}>{formatBytes(release.artifactSize)}</span></div></td>
                              <td><span className="mono dim" title={release.sha256}>{release.sha256.slice(0, 10)}…</span></td>
                              <td><span className="mono dim">{formatDate(release.createdAt)}</span></td>
                              <td><span className="muted deploy-note">{release.notes || "—"}</span></td>
                              <td style={{ textAlign: "right" }}>
                                <button className="btn btn-sm" disabled={isCurrent || (!!liveTask && !terminal(liveTask.status))} onClick={() => setConfirm({ release, action })}>
                                  {action === "rollback" ? I.history({ size: 12 }) : I.bolt({ size: 12 })}
                                  <span>{action === "rollback" ? t("deploy.rollback") : t("deploy.deployNow")}</span>
                                </button>
                              </td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>

              <DeploymentHistory tasks={detail.deployments} onSelect={setLiveTask} />
            </>
          )}
        </main>
      </div>

      {projectModal && <ProjectModal agents={agents} project={projectModal === "new" ? undefined : projectModal} onClose={() => setProjectModal(null)} onSaved={async (project) => { setProjectModal(null); await loadProjects(); setSelectedId(project.id); await loadDetail(project.id) }} />}
      {uploadOpen && detail && <UploadReleaseModal project={detail} onClose={() => setUploadOpen(false)} onUploaded={async () => { setUploadOpen(false); await loadDetail(detail.id) }} />}
      {confirm && <ConfirmDialog title={confirm.action === "deploy" ? t("deploy.confirmDeploy") : t("deploy.confirmRollback")} message={t(confirm.action === "deploy" ? "deploy.confirmDeployDesc" : "deploy.confirmRollbackDesc", { version: confirm.release.version, project: detail?.name })} confirmLabel={confirm.action === "deploy" ? t("deploy.deployNow") : t("deploy.rollback")} danger={confirm.action === "rollback"} busy={busy} onConfirm={runRelease} onClose={() => setConfirm(null)} />}
    </div>
  )
}

function DeploymentRail({ task }: { task: DeploymentTask | null }) {
  const { t } = useTranslation()
  const steps = [...DEPLOYMENT_STEPS]
  const completed = completedDeploymentSteps(task?.output ?? "", task?.status === "success")
  return (
    <section className="card deploy-rail-card">
      <div className="deploy-panel-head">
        <div className="row gap-2"><span>{t("deploy.pipeline")}</span>{task && <span className={`badge ${statusTone(task.status)}`}>{t(`deploy.status.${task.status}`)}</span>}</div>
        <span className="mono dim">{task ? `${task.action} · ${task.release?.version ?? task.releaseId.slice(0, 8)}` : t("deploy.noTask")}</span>
      </div>
      <div className="release-rail">
        {steps.map((step, index) => {
          const done = completed.has(step)
          const isNext = !done && steps.slice(0, index).every((s) => completed.has(s))
          const active = task?.status === "running" && isNext
          const failed = task?.status === "failed" && isNext
          return (
            <div className={`release-step ${done ? "done" : ""} ${active ? "active" : ""} ${failed ? "failed" : ""}`} key={step}>
              <span className="release-node">{done ? I.check({ size: 11 }) : failed ? I.x({ size: 10 }) : <span className="mono">{index + 1}</span>}</span>
              <span>{t(`deploy.steps.${step}`)}</span>
            </div>
          )
        })}
      </div>
      {task?.output && <pre className="deploy-output">{task.output}</pre>}
      {task?.error && task.error !== task.output && <div className="deploy-task-error">{task.error}</div>}
    </section>
  )
}

function DeploymentHistory({ tasks, onSelect }: { tasks: DeploymentTask[]; onSelect: (task: DeploymentTask) => void }) {
  const { t } = useTranslation()
  return (
    <section className="card deploy-history">
      <div className="deploy-panel-head"><span>{t("deploy.history")}</span><span className="mono dim">{tasks.length}</span></div>
      {tasks.length === 0 ? <div className="deploy-list-empty">{t("deploy.noHistory")}</div> : (
        <div className="deploy-history-list">
          {tasks.slice(0, 12).map((task) => (
            <button key={task.id} onClick={() => onSelect(task)}>
              <span className={`dot ${task.status === "success" ? "ok" : task.status === "failed" ? "crit" : "warn"}`} />
              <span className="mono">{task.release?.version ?? task.releaseId.slice(0, 8)}</span>
              <span className="badge">{task.action}</span>
              <span className="muted flex-1 truncate">{task.createdByName}</span>
              <span className="mono dim">{formatDate(task.createdAt)}</span>
              {I.chev({ size: 12 })}
            </button>
          ))}
        </div>
      )}
    </section>
  )
}

function ProjectModal({ agents, project, onClose, onSaved }: { agents: Agent[]; project?: DeploymentProject; onClose: () => void; onSaved: (project: DeploymentProject) => void }) {
  const { t } = useTranslation()
  const [form, setForm] = useState<DeploymentProjectInput>({
    name: project?.name ?? "",
    type: project?.type ?? "java",
    agentId: project?.agentId ?? agents[0]?.id ?? "",
    deployPath: project?.deployPath ?? "/opt/nanolink/apps/",
    extractArchive: project?.extractArchive ?? true,
    serviceName: project?.serviceName ?? "",
    healthUrl: project?.healthUrl ?? "",
    keepReleases: project?.keepReleases ?? 5,
  })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  function set<K extends keyof DeploymentProjectInput>(key: K, value: DeploymentProjectInput[K]) { setForm({ ...form, [key]: value }) }
  async function save() {
    setBusy(true)
    try {
      const saved = project ? await deploymentsApi.updateProject(project.id, form) : await deploymentsApi.createProject(form)
      onSaved(saved)
    } catch (e) {
      setError(messageOf(e))
    } finally {
      setBusy(false)
    }
  }
  return (
    <Modal title={project ? t("deploy.editProject") : t("deploy.newProject")} subtitle={t("deploy.projectFormDesc")} onClose={onClose} width={660} footer={<><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-primary btn-sm" disabled={busy || !form.name || !form.agentId || !form.deployPath} onClick={save}>{busy && <span className="dot pulse ok" />}{t("common.save")}</button></>}>
      <div className="deploy-form-grid">
        <FormBlock label={t("deploy.projectName")}><input className="input" value={form.name} onChange={(e) => set("name", e.target.value)} placeholder="orders-api" /></FormBlock>
        <FormBlock label={t("deploy.projectType")}><select className="select" value={form.type} onChange={(e) => { const type = e.target.value as "java" | "static"; setForm({ ...form, type, serviceName: type === "static" && !form.serviceName ? "nginx" : form.serviceName }) }}><option value="java">{t("deploy.typeJava")}</option><option value="static">{t("deploy.typeStatic")}</option></select></FormBlock>
        <FormBlock label={t("deploy.targetAgent")}><select className="select" value={form.agentId} onChange={(e) => set("agentId", e.target.value)}>{agents.map((a) => <option key={a.id} value={a.id}>{a.hostname} · {a.id.slice(0, 8)}</option>)}</select></FormBlock>
        <FormBlock label={t("deploy.keepReleases")}><input className="input" type="number" min={2} max={50} value={form.keepReleases} onChange={(e) => set("keepReleases", Number(e.target.value))} /></FormBlock>
        <div className="deploy-form-wide"><FormBlock label={t("deploy.deployPath")} hint={t("deploy.deployPathHint")}><input className="input mono" value={form.deployPath} onChange={(e) => set("deployPath", e.target.value)} placeholder={form.type === "java" ? "/opt/nanolink/apps/orders" : "/var/www/nanolink/portal"} /></FormBlock></div>
        {form.type === "static" && <div className="deploy-form-wide"><label className="deploy-toggle"><input type="checkbox" checked={form.extractArchive} onChange={(e) => set("extractArchive", e.target.checked)} /><span><strong>{t("deploy.extractArchive")}</strong><small>{t("deploy.extractArchiveHint")}</small></span></label></div>}
        <FormBlock label={t("deploy.serviceName")} hint={form.type === "static" ? t("deploy.staticServiceHint") : undefined}><input className="input mono" value={form.serviceName} onChange={(e) => set("serviceName", e.target.value)} placeholder={form.type === "java" ? "orders.service" : "nginx"} /></FormBlock>
        <FormBlock label={t("deploy.healthUrl")}><input className="input mono" value={form.healthUrl} onChange={(e) => set("healthUrl", e.target.value)} placeholder="http://127.0.0.1:8080/actuator/health" /></FormBlock>
      </div>
      {error && <div className="deploy-modal-error">{error}</div>}
    </Modal>
  )
}

function UploadReleaseModal({ project, onClose, onUploaded }: { project: DeploymentProjectDetail; onClose: () => void; onUploaded: () => void }) {
  const { t } = useTranslation()
  const inputRef = useRef<HTMLInputElement>(null)
  const [file, setFile] = useState<File | null>(null)
  const [directoryFiles, setDirectoryFiles] = useState<File[]>([])
  const [uploadKind, setUploadKind] = useState<"artifact" | "directory">("artifact")
  const [extract, setExtract] = useState(project.type === "static" && project.extractArchive)
  const [stripTopLevel, setStripTopLevel] = useState(false)
  const [version, setVersion] = useState(guessVersion())
  const [notes, setNotes] = useState("")
  const [busy, setBusy] = useState(false)
  const [uploadProgress, setUploadProgress] = useState<number | null>(null)
  const [dragging, setDragging] = useState(false)
  const [error, setError] = useState<string | null>(null)
  async function upload() {
    if ((!file && uploadKind === "artifact") || (directoryFiles.length === 0 && uploadKind === "directory") || !version) return
    setBusy(true)
    try {
      if (uploadKind === "directory") await deploymentsApi.uploadDirectory(project.id, version, notes, directoryFiles)
      else await deploymentsApi.uploadRelease(project.id, version, notes, file!, extract, stripTopLevel, (uploaded, total) => setUploadProgress(total > 0 ? Math.round(uploaded * 100 / total) : 0))
      onUploaded()
    } catch (e) {
      setError(messageOf(e))
    } finally {
      setBusy(false)
      setUploadProgress(null)
    }
  }
  const accept = project.type === "java" ? ".jar" : ".zip,.tar,.tar.gz,.tgz"
  const ready = uploadKind === "directory" ? directoryFiles.length > 0 : !!file
  const directorySize = directoryFiles.reduce((sum, item) => sum + item.size, 0)
  return (
    <Modal title={t("deploy.uploadRelease")} subtitle={`${project.name} · ${project.type === "java" ? "JAR" : "ZIP / TAR / DIST"}`} onClose={onClose} width={620} footer={<><button className="btn btn-sm" onClick={onClose}>{t("common.cancel")}</button><button className="btn btn-primary btn-sm" disabled={!ready || !version || busy} onClick={upload}>{busy && <span className="dot pulse ok" />}{t("deploy.upload")}{uploadProgress !== null ? ` ${uploadProgress}%` : ""}</button></>}>
      <div className="col gap-4">
        {project.type === "static" && <div className="tabs"><button className={`tab ${uploadKind === "artifact" ? "active" : ""}`} onClick={() => { setUploadKind("artifact"); setDirectoryFiles([]) }}>{t("deploy.archiveUpload")}</button><button className={`tab ${uploadKind === "directory" ? "active" : ""}`} onClick={() => { setUploadKind("directory"); setFile(null); setExtract(true); setStripTopLevel(false) }}>{t("deploy.directoryUpload")}</button></div>}
        <button className={`deploy-drop ${dragging ? "dragging" : ""}`} onClick={() => inputRef.current?.click()} onDragOver={(e) => { e.preventDefault(); setDragging(true) }} onDragLeave={() => setDragging(false)} onDrop={(e) => { e.preventDefault(); setDragging(false); if (uploadKind === "artifact") setFile(e.dataTransfer.files[0] ?? null) }}>
          {uploadKind === "directory" ? <input ref={inputRef} type="file" hidden multiple {...({ webkitdirectory: "", directory: "" } as Record<string, string>)} onChange={(e) => setDirectoryFiles(Array.from(e.target.files ?? []))} /> : <input ref={inputRef} type="file" accept={accept} hidden onChange={(e) => setFile(e.target.files?.[0] ?? null)} />}
          <span className="deploy-drop-icon">{ready ? I.check({ size: 20 }) : I.arrowUp({ size: 20 })}</span>
          <strong>{uploadKind === "directory" ? (directoryFiles[0]?.webkitRelativePath.split("/")[0] || t("deploy.selectDirectory")) : (file?.name ?? t("deploy.dropArtifact"))}</strong>
          <span>{uploadKind === "directory" ? (directoryFiles.length ? t("deploy.directorySummary", { count: directoryFiles.length, size: formatBytes(directorySize) }) : t("deploy.directoryHint")) : (file ? formatBytes(file.size) : t("deploy.dropArtifactHint", { type: accept }))}</span>
        </button>
        <div className="deploy-form-grid">
          <FormBlock label={t("deploy.version")} hint={t("deploy.versionHint")}><input className="input mono" value={version} onChange={(e) => setVersion(e.target.value)} /></FormBlock>
          {project.type === "static" && uploadKind === "artifact" && <FormBlock label={t("deploy.publishMode")}><label className="build-check"><input type="checkbox" checked={extract} onChange={(e) => { setExtract(e.target.checked); if (!e.target.checked) setStripTopLevel(false) }} />{t("deploy.extractArtifact")}</label>{extract && <label className="build-check"><input type="checkbox" checked={stripTopLevel} onChange={(e) => setStripTopLevel(e.target.checked)} />{t("deploy.stripTopLevel")}</label>}</FormBlock>}
          <div className="deploy-form-wide"><FormBlock label={t("deploy.notes")}><textarea className="textarea" rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder={t("deploy.notesPlaceholder")} /></FormBlock></div>
        </div>
      </div>
      {error && <div className="deploy-modal-error">{error}</div>}
    </Modal>
  )
}

function statusTone(status: string) { return status === "success" ? "ok" : status === "failed" ? "crit" : "warn" }
function messageOf(error: unknown) { return (error as ApiError)?.error || (error instanceof Error ? error.message : String(error)) }
function formatBytes(bytes: number) { if (bytes < 1024) return `${bytes} B`; const units = ["KB", "MB", "GB"]; let value = bytes / 1024; let i = 0; while (value >= 1024 && i < units.length - 1) { value /= 1024; i++ } return `${value.toFixed(value >= 10 ? 1 : 2)} ${units[i]}` }
function formatDate(value: string) { return value ? new Date(value).toLocaleString(undefined, { month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—" }
function guessVersion() { const now = new Date(); return `${now.getFullYear()}.${String(now.getMonth() + 1).padStart(2, "0")}.${String(now.getDate()).padStart(2, "0")}-${String(now.getHours()).padStart(2, "0")}${String(now.getMinutes()).padStart(2, "0")}` }
