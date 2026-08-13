import { useEffect, useRef, useCallback, useState } from "react"
import { useTranslation } from "react-i18next"
import { Terminal as XTerm } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import "@xterm/xterm/css/xterm.css"
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
  const { t } = useTranslation()
  const terminalRef = useRef<HTMLDivElement>(null)
  const xtermRef = useRef<XTerm | null>(null)
  const wsRef = useRef<WebSocket | null>(null)
  const fitAddonRef = useRef<FitAddon | null>(null)
  
  const [settings] = useState<TerminalSettings>(() => propSettings || loadTerminalSettings())
  const theme = getThemeById(settings.themeId)

  const connect = useCallback(() => {
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
    const wsUrl = `${protocol}//${window.location.host}/ws/shell/${agentId}`

    const ws = new WebSocket(wsUrl)
    wsRef.current = ws

    ws.onopen = () => {
      xtermRef.current?.writeln(`\x1b[32m${t("shell.connectedToAgent")}\x1b[0m`)
      xtermRef.current?.writeln("")
    }

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data)
        if (data.type === "output") {
          xtermRef.current?.write(data.data)
        } else if (data.type === "error") {
          xtermRef.current?.writeln(`\x1b[31m${t("shell.errorPrefix", { message: data.data })}\x1b[0m`)
        }
      } catch {
        // Raw output
        xtermRef.current?.write(event.data)
      }
    }

    ws.onclose = () => {
      xtermRef.current?.writeln("")
      xtermRef.current?.writeln(`\x1b[33m${t("shell.disconnectedFromAgent")}\x1b[0m`)
      onDisconnect?.()
    }

    ws.onerror = () => {
      xtermRef.current?.writeln(`\x1b[31m${t("shell.connectionFailed")}\x1b[0m`)
    }
  }, [agentId, onDisconnect, t])

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
    term.writeln(`\x1b[36m${t("shell.webShell")}\x1b[0m`)
    term.writeln(`\x1b[90m${t("shell.connectingToAgent", { agentId })}\x1b[0m`)
    term.writeln("")
    connect()

    return () => {
      window.removeEventListener("resize", handleResize)
      resizeObserver.disconnect()
      wsRef.current?.close()
      term.dispose()
    }
  }, [agentId, settings, theme, connect, t])

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
      style={{
        height: "100%",
        width: "100%",
        padding: "8px",
        borderRadius: "var(--radius)",
        overflow: "hidden",
        border: "1px solid var(--border)",
        backgroundColor: theme.theme.background,
      }}
    />
  )
}
