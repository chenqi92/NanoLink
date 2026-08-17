import { useEffect } from "react"
import { useData } from "@/contexts/DataContext"
import { agentStatus } from "@/lib/format"
import { reconcileAgentSelection } from "@/lib/fleet"

/** Dropdown to pick an agent (online first); auto-selects the first online one. */
export function AgentPicker({ value, onChange }: { value: string; onChange: (id: string) => void }) {
  const { agents } = useData()
  const sorted = [...agents].sort((a, b) => Number(agentStatus(b.lastHeartbeat) === "online") - Number(agentStatus(a.lastHeartbeat) === "online"))

  useEffect(() => {
    const nextValue = reconcileAgentSelection(value, sorted)
    if (nextValue !== value) onChange(nextValue)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, agents])

  return (
    <select className="select" style={{ width: "auto", minWidth: 200 }} value={value} onChange={(e) => onChange(e.target.value)}>
      {sorted.length === 0 && <option value="">—</option>}
      {sorted.map((a) => (
        <option key={a.id} value={a.id}>
          {agentStatus(a.lastHeartbeat) === "online" ? "● " : "○ "}
          {a.hostname}
        </option>
      ))}
    </select>
  )
}
