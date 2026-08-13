import { useEffect, useMemo, useRef, useState } from "react"
import { useTranslation } from "react-i18next"
import type { Agent } from "@/lib/api"
import { Modal } from "@/components/shell/Dialog"
import { Perm, Status } from "@/components/shell/primitives"
import { I } from "@/lib/icons"
import { eligibleFleetShellAgents } from "@/lib/fleet"
import "./fleet-shell.css"

type ResultStatus = "idle" | "connecting" | "running" | "success" | "failed"
interface FleetResult { status: ResultStatus; output: string; error?: string }

export function FleetShell({ agents, onClose }: { agents: Agent[]; onClose: () => void }) {
  const { t } = useTranslation()
  const eligible = useMemo(() => eligibleFleetShellAgents(agents), [agents])
  const [selected, setSelected] = useState(() => new Set(eligible.map((agent) => agent.id)))
  const [command, setCommand] = useState("")
  const [running, setRunning] = useState(false)
  const [results, setResults] = useState<Record<string, FleetResult>>({})
  const sockets = useRef(new Set<WebSocket>())

  useEffect(() => () => {
    for (const socket of sockets.current) socket.close(1000, "Batch shell closed")
    sockets.current.clear()
  }, [])

  function toggle(id: string) {
    setSelected((current) => {
      const next = new Set(current)
      if (next.has(id)) next.delete(id); else next.add(id)
      return next
    })
  }

  function update(id: string, result: FleetResult) {
    setResults((current) => ({ ...current, [id]: result }))
  }

  function executeOn(agent: Agent, value: string): Promise<void> {
    return new Promise((resolve) => {
      const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
      const socket = new WebSocket(`${protocol}//${window.location.host}/ws/shell/${agent.id}`)
      sockets.current.add(socket)
      const timeout = window.setTimeout(() => finish({ status: "failed", output: "", error: t("fleetShell.timeoutFix") }), 60_000)
      let done = false
      function finish(result: FleetResult) {
        if (done) return
        done = true
        window.clearTimeout(timeout)
        update(agent.id, result)
        sockets.current.delete(socket)
        socket.close(1000, "Batch command finished")
        resolve()
      }
      update(agent.id, { status: "connecting", output: "" })
      socket.onopen = () => {
        update(agent.id, { status: "running", output: "" })
        socket.send(JSON.stringify({ type: "input", data: value }))
      }
      socket.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data) as { type?: string; data?: string; success?: boolean }
          if (message.type === "output") finish({ status: message.success === false ? "failed" : "success", output: message.data ?? "", error: message.success === false ? t("fleetShell.commandFailedFix") : undefined })
          if (message.type === "error") finish({ status: "failed", output: "", error: message.data || t("fleetShell.connectionFailedFix") })
        } catch {
          finish({ status: "success", output: String(event.data) })
        }
      }
      socket.onerror = () => finish({ status: "failed", output: "", error: t("fleetShell.connectionFailedFix") })
      socket.onclose = () => { if (!done) finish({ status: "failed", output: "", error: t("fleetShell.closedFix") }) }
    })
  }

  async function run(event: React.FormEvent) {
    event.preventDefault()
    const value = command.trim()
    const targets = eligible.filter((agent) => selected.has(agent.id))
    if (!value || !targets.length || running) return
    setRunning(true)
    setResults(Object.fromEntries(targets.map((agent) => [agent.id, { status: "idle", output: "" }])))
    await Promise.all(targets.map((agent) => executeOn(agent, value)))
    setRunning(false)
  }

  const targets = eligible.filter((agent) => selected.has(agent.id))
  return (
    <Modal title={t("fleetShell.title")} subtitle={t("fleetShell.subtitle")} onClose={onClose} width={940} footer={<><span className="fleet-shell-footnote">{I.shield({ size: 12 })}{t("fleetShell.l3Only")}</span><button className="btn btn-sm" onClick={onClose}>{t("common.close")}</button></>}>
      {eligible.length === 0 ? <div className="fleet-shell-empty"><span>{I.term({ size: 26 })}</span><strong>{t("fleetShell.noAgents")}</strong><p>{t("fleetShell.noAgentsFix")}</p></div> : (
        <form className="fleet-shell" onSubmit={run}>
          <div className="fleet-shell-targets">
            <div className="fleet-shell-section-head"><span>{t("fleetShell.targets")}</span><span className="mono">{selected.size}/{eligible.length}</span></div>
            <div className="fleet-shell-select-actions"><button type="button" className="btn btn-sm btn-ghost" onClick={() => setSelected(new Set(eligible.map((agent) => agent.id)))}>{t("fleetShell.selectAll")}</button><button type="button" className="btn btn-sm btn-ghost" onClick={() => setSelected(new Set())}>{t("fleetShell.clear")}</button></div>
            <div className="fleet-shell-agent-list">{eligible.map((agent) => <label key={agent.id} className={selected.has(agent.id) ? "selected" : ""}><input type="checkbox" checked={selected.has(agent.id)} onChange={() => toggle(agent.id)} /><span className="dot ok" /><span className="col flex-1"><strong className="mono">{agent.hostname}</strong><small className="mono">{agent.id.slice(0, 12)}</small></span><Perm level={agent.permissionLevel} /></label>)}</div>
          </div>
          <div className="fleet-shell-workspace">
            <div className="fleet-shell-command">
              <label htmlFor="fleet-shell-command">{t("fleetShell.command")}</label>
              <div><span className="mono">$</span><input id="fleet-shell-command" className="input mono" value={command} onChange={(event) => setCommand(event.target.value)} placeholder={t("fleetShell.commandPlaceholder")} autoFocus autoComplete="off" /><button className="btn btn-primary" disabled={running || !command.trim() || targets.length === 0}>{running ? <span className="dot pulse ok" /> : I.term({ size: 13 })}<span>{t("fleetShell.execute")}</span></button></div>
              <small>{t("fleetShell.commandHint", { count: targets.length })}</small>
            </div>
            <div className="fleet-shell-results">
              {targets.length === 0 ? <div className="fleet-shell-result-empty">{t("fleetShell.selectFix")}</div> : targets.map((agent) => {
                const result = results[agent.id] ?? { status: "idle", output: "" }
                return <section key={agent.id} className={`fleet-shell-result ${result.status}`}><header><div className="row gap-2"><Status status={result.status === "success" ? "online" : result.status === "failed" ? "offline" : "connecting"} /><strong className="mono">{agent.hostname}</strong><Perm level={agent.permissionLevel} /></div><span className="badge">{t(`fleetShell.status.${result.status}`)}</span></header><pre>{result.output || (result.status === "idle" ? t("fleetShell.waiting") : result.status === "running" || result.status === "connecting" ? t("fleetShell.executing") : t("fleetShell.noOutput"))}</pre>{result.error && <div role="alert">{result.error}</div>}</section>
              })}
            </div>
          </div>
        </form>
      )}
    </Modal>
  )
}
