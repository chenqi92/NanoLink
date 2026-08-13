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
  const lineRef = useRef("")
  const historyRef = useRef<string[]>([])
  const historyIndexRef = useRef(0)
  const awaitingRef = useRef(false)
  
  const [settings] = useState<TerminalSettings>(() => propSettings || loadTerminalSettings())
  const theme = getThemeById(settings.themeId)

  const connect = useCallback(() => {
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
    const wsUrl = `${protocol}//${window.location.host}/ws/shell/${agentId}`

    const ws = new WebSocket(wsUrl)
    wsRef.current = ws

    ws.onopen = () => {
      xtermRef.current?.writeln(`\x1b[32m${t("shell.connectedToAgent")}\x1b[0m`)
      xtermRef.current?.write(`\r\n\x1b[90m${agentId.slice(0, 8)}\x1b[0m \x1b[32m$\x1b[0m `)
    }

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data)
        if (data.type === "output") {
          awaitingRef.current = false
          const output = String(data.data ?? "")
          if (output) xtermRef.current?.write(output)
          if (output && !output.endsWith("\n") && !output.endsWith("\r")) xtermRef.current?.write("\r\n")
          xtermRef.current?.write(`\x1b[90m${agentId.slice(0, 8)}\x1b[0m \x1b[32m$\x1b[0m `)
        } else if (data.type === "error") {
          awaitingRef.current = false
          xtermRef.current?.writeln(`\x1b[31m${t("shell.errorPrefix", { message: data.data })}\x1b[0m`)
          xtermRef.current?.write(`\x1b[90m${agentId.slice(0, 8)}\x1b[0m \x1b[32m$\x1b[0m `)
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

    const redrawLine = (next: string) => {
      term.write(`\r\x1b[2K\x1b[90m${agentId.slice(0, 8)}\x1b[0m \x1b[32m$\x1b[0m ${next}`)
      lineRef.current = next
    }

    const submitLine = () => {
      const command = lineRef.current
      term.write("\r\n")
      lineRef.current = ""
      if (!command.trim()) {
        term.write(`\x1b[90m${agentId.slice(0, 8)}\x1b[0m \x1b[32m$\x1b[0m `)
        return
      }
      historyRef.current = [...historyRef.current.filter((item) => item !== command), command].slice(-100)
      historyIndexRef.current = historyRef.current.length
      if (wsRef.current?.readyState === WebSocket.OPEN) {
        awaitingRef.current = true
        wsRef.current.send(JSON.stringify({ type: "input", data: command }))
      } else {
        term.writeln(`\x1b[31m${t("shell.connectionFailed")}\x1b[0m`)
        term.write(`\x1b[90m${agentId.slice(0, 8)}\x1b[0m \x1b[32m$\x1b[0m `)
      }
    }

    // The server executes one bounded command per message rather than exposing
    // a PTY. Buffer a complete line locally so each keystroke is not dispatched
    // as a separate shell command.
    term.onData((data) => {
      if (awaitingRef.current) return
      if (data === "\x1b[A" || data === "\x1b[B") {
        const history = historyRef.current
        if (!history.length) return
        historyIndexRef.current = data === "\x1b[A" ? Math.max(0, historyIndexRef.current - 1) : Math.min(history.length, historyIndexRef.current + 1)
        redrawLine(historyIndexRef.current < history.length ? history[historyIndexRef.current] : "")
        return
      }
      for (const char of data) {
        if (char === "\r" || char === "\n") {
          submitLine()
        } else if (char === "\x7f") {
          if (lineRef.current.length) {
            lineRef.current = lineRef.current.slice(0, -1)
            term.write("\b \b")
          }
        } else if (char === "\x03") {
          term.write("^C\r\n")
          redrawLine("")
        } else if (char === "\x0c") {
          term.clear()
          redrawLine(lineRef.current)
        } else if (char >= " " && lineRef.current.length < 16_000) {
          lineRef.current += char
          term.write(char)
        }
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
