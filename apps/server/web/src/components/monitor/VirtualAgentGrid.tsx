import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react"
import { useVirtualizer } from "@tanstack/react-virtual"
import type { Agent, Metrics } from "@/lib/api"
import { AgentCard } from "@/components/monitor/AgentCard"

const MIN_COL = 320 // matches minmax(320px, 1fr)
const GAP = 12
const EST_ROW = 230 // estimated card height incl. gap; rows are measured at runtime

function columnsForWidth(width: number): number {
  if (width <= 0) return 1
  // Inverse of CSS grid repeat(auto-fill, minmax(MIN_COL, 1fr)) with column-gap GAP.
  return Math.max(1, Math.floor((width + GAP) / (MIN_COL + GAP)))
}

/**
 * Virtualized responsive agent grid.
 *
 * Mirrors the CSS `repeat(auto-fill, minmax(320px, 1fr))` layout but only mounts
 * the rows currently visible inside `scrollRef` (the existing overflow:auto
 * container). Column count is derived from the measured container width so the
 * responsive behaviour is preserved. Row heights are measured at runtime via the
 * virtualizer so variable-height cards (online vs offline) stay aligned.
 */
export function VirtualAgentGrid({
  agents,
  metrics,
  onOpen,
  scrollRef,
}: {
  agents: Agent[]
  metrics: Record<string, Metrics>
  onOpen: (id: string) => void
  scrollRef: React.RefObject<HTMLDivElement | null>
}) {
  const innerRef = useRef<HTMLDivElement>(null)
  const [width, setWidth] = useState(0)

  // Track the inner container width to compute the responsive column count.
  useLayoutEffect(() => {
    const el = innerRef.current
    if (!el) return
    setWidth(el.clientWidth)
    const ro = new ResizeObserver((entries) => {
      for (const entry of entries) setWidth(entry.contentRect.width)
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const cols = columnsForWidth(width)
  const rowCount = Math.ceil(agents.length / cols)

  const rowVirtualizer = useVirtualizer({
    count: rowCount,
    getScrollElement: () => scrollRef.current,
    estimateSize: () => EST_ROW + GAP,
    overscan: 4,
    measureElement: (el) => el.getBoundingClientRect().height,
  })

  // Column count changes invalidate every measured row height.
  useEffect(() => {
    rowVirtualizer.measure()
  }, [cols, rowVirtualizer])

  const virtualRows = rowVirtualizer.getVirtualItems()

  const rows = useMemo(() => {
    const out: Agent[][] = []
    for (let i = 0; i < agents.length; i += cols) out.push(agents.slice(i, i + cols))
    return out
  }, [agents, cols])

  return (
    <div ref={innerRef} style={{ position: "relative", width: "100%", height: rowVirtualizer.getTotalSize() }}>
      {virtualRows.map((vr) => {
        const row = rows[vr.index]
        if (!row) return null
        return (
          <div
            key={vr.key}
            data-index={vr.index}
            ref={rowVirtualizer.measureElement}
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              width: "100%",
              transform: `translateY(${vr.start}px)`,
              display: "grid",
              gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))`,
              gap: GAP,
              paddingBottom: GAP,
            }}
          >
            {row.map((a) => (
              <AgentCard key={a.id} agent={a} metrics={metrics[a.id]} onClick={onOpen} />
            ))}
          </div>
        )
      })}
    </div>
  )
}
