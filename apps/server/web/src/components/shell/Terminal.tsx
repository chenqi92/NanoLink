import { useEffect, useRef, useCallback, useState } from "react"
import { Terminal as XTerm } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import "@xterm/xterm/css/xterm.css"
import { api } from "@/lib/api"
import { getThemeById } from "./TerminalThemes"
import { loadTerminalSettings, type TerminalSettings } from "./TerminalSettings"

interface TerminalProps {
  agentId: string
  settings?: TerminalSettings
  onDisconnect?: () => void
}

const fontFamilies: Record<string, string> = {
  "JetBrains Mono": '"JetBrains Mono", ui-monospace, monospace',
  "Fira Code": '"Fira Code", ui-monospace, monospace',
  "Source Code Pro": '"Source Code Pro", ui-monospace, monospace',
  Consolas: "Consolas, ui-monospace, monospace",
  Monaco: "Monaco, ui-monospace, monospace",
  System: 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace',
}

export function Terminal({ agentId, settings: propSettings, onDisconnect }: TerminalProps) {
  const terminalRef = useRef<HTMLDivElement>(null)
  const xtermRef = useRef<XTerm | null>(null)
  const wsRef = useRef<WebSocket | null>(null)
  const fitAddonRef = useRef<FitAddon | null>(null)
  
  const [settings] = useState<TerminalSettings>(() => propSettings || loadTerminalSettings())
  const theme = getThemeById(settings.themeId)

  const connect = useCallback(() => {
    const token = api.getToken()
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
    const wsUrl = `${protocol}//${window.location.host}/ws/shell/${agentId}?token=${token}`

    const ws = new WebSocket(wsUrl)
    wsRef.current = ws

    ws.onopen = () => {
      xtermRef.current?.writeln("\x1b[32mConnected to agent shell\x1b[0m")
      xtermRef.current?.writeln("")
    }

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data)
        if (data.type === "output") {
          xtermRef.current?.write(data.data)
        } else if (data.type === "error") {
          xtermRef.current?.writeln(`\x1b[31mError: ${data.data}\x1b[0m`)
        }
      } catch {
        // Raw output
        xtermRef.current?.write(event.data)
      }
    }

    ws.onclose = () => {
      xtermRef.current?.writeln("")
      xtermRef.current?.writeln("\x1b[33mDisconnected from agent shell\x1b[0m")
      onDisconnect?.()
    }

    ws.onerror = () => {
      xtermRef.current?.writeln("\x1b[31mConnection error\x1b[0m")
    }
  }, [agentId, onDisconnect])

  useEffect(() => {
    if (!terminalRef.current) return

    const term = new XTerm({
      cursorBlink: settings.cursorBlink,
      cursorStyle: settings.cursorStyle,
      fontFamily: fontFamilies[settings.fontFamily] || fontFamilies.System,
      fontSize: settings.fontSize,
      lineHeight: 1.2,
      theme: theme.theme,
    })

    const fitAddon = new FitAddon()
    const webLinksAddon = new WebLinksAddon()

    term.loadAddon(fitAddon)
    term.loadAddon(webLinksAddon)

    term.open(terminalRef.current)
    fitAddon.fit()

    xtermRef.current = term
    fitAddonRef.current = fitAddon

    // Handle terminal input
    term.onData((data) => {
      if (wsRef.current?.readyState === WebSocket.OPEN) {
        wsRef.current.send(JSON.stringify({ type: "input", data }))
      }
    })

    // Handle resize
    const handleResize = () => {
      fitAddon.fit()
      if (wsRef.current?.readyState === WebSocket.OPEN) {
        wsRef.current.send(
          JSON.stringify({
            type: "resize",
            cols: term.cols,
            rows: term.rows,
          })
        )
      }
    }

    window.addEventListener("resize", handleResize)
    const resizeObserver = new ResizeObserver(handleResize)
    resizeObserver.observe(terminalRef.current)

    // Connect to shell
    term.writeln("\x1b[36mNanoLink Web Shell\x1b[0m")
    term.writeln(`\x1b[90mConnecting to agent: ${agentId}\x1b[0m`)
    term.writeln("")
    connect()

    return () => {
      window.removeEventListener("resize", handleResize)
      resizeObserver.disconnect()
      wsRef.current?.close()
      term.dispose()
    }
  }, [agentId, settings, theme, connect])

  // Update terminal options when settings change
  useEffect(() => {
    if (!xtermRef.current) return

    xtermRef.current.options.theme = theme.theme
    xtermRef.current.options.cursorBlink = settings.cursorBlink
    xtermRef.current.options.cursorStyle = settings.cursorStyle
    xtermRef.current.options.fontSize = settings.fontSize
    xtermRef.current.options.fontFamily =
      fontFamilies[settings.fontFamily] || fontFamilies.System

    fitAddonRef.current?.fit()
  }, [settings, theme])

  return (
    <div
      ref={terminalRef}
      className="h-full w-full rounded-lg overflow-hidden border border-[var(--color-border)]"
      style={{
        padding: "8px",
        backgroundColor: theme.theme.background,
      }}
    />
  )
}
