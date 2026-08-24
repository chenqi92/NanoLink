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
  const cursorRef = useRef(0)
  const historyRef = useRef<string[]>([])
  const historyIndexRef = useRef(0)
  const awaitingRef = useRef(false)
  const cwdRef = useRef("/")

  const [settings] = useState<TerminalSettings>(() => propSettings || loadTerminalSettings())
  const theme = getThemeById(settings.themeId)

  const writePrompt = useCallback(() => {
    const cwd = cwdRef.current || "/"
    xtermRef.current?.write(`\x1b[90m${agentId.slice(0, 8)}:${cwd}\x1b[0m \x1b[32m$\x1b[0m `)
  }, [agentId])

  const connect = useCallback(() => {
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
    const wsUrl = `${protocol}//${window.location.host}/ws/shell/${agentId}`

    const ws = new WebSocket(wsUrl)
    wsRef.current = ws

    ws.onopen = () => {
      xtermRef.current?.writeln(`\x1b[32m${t("shell.connectedToAgent")}\x1b[0m`)
      xtermRef.current?.write("\r\n")
      writePrompt()
      const term = xtermRef.current
      if (term) ws.send(JSON.stringify({ type: "resize", cols: term.cols, rows: term.rows }))
    }

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data)
        if (data.type === "output") {
          awaitingRef.current = false
          if (typeof data.cwd === "string" && data.cwd.startsWith("/")) cwdRef.current = data.cwd
          const output = String(data.data ?? "")
          if (output) xtermRef.current?.write(output)
          if (output && !output.endsWith("\n") && !output.endsWith("\r")) xtermRef.current?.write("\r\n")
          writePrompt()
        } else if (data.type === "error") {
          awaitingRef.current = false
          xtermRef.current?.writeln(`\x1b[31m${t("shell.errorPrefix", { message: data.data })}\x1b[0m`)
          writePrompt()
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
  }, [agentId, onDisconnect, t, writePrompt])

  useEffect(() => {
    if (!terminalRef.current) return

    const term = new XTerm({
      cursorBlink: settings.cursorBlink,
      cursorStyle: settings.cursorStyle,
      fontFamily: fontFamilies[settings.fontFamily] || fontFamilies.System,
      fontSize: settings.fontSize,
      lineHeight: 1.2,
      convertEol: true,
      scrollback: 10_000,
      theme: theme.theme,
    })

    const fitAddon = new FitAddon()
    const webLinksAddon = new WebLinksAddon()

    term.loadAddon(fitAddon)
    term.loadAddon(webLinksAddon)

    term.open(terminalRef.current)
    requestAnimationFrame(() => fitAddon.fit())

    xtermRef.current = term
    fitAddonRef.current = fitAddon

    const redrawLine = (next: string, cursor = next.length) => {
      term.write(`\r\x1b[2K\x1b[90m${agentId.slice(0, 8)}:${cwdRef.current}\x1b[0m \x1b[32m$\x1b[0m ${next}`)
      lineRef.current = next
      cursorRef.current = Math.max(0, Math.min(next.length, cursor))
      const moveLeft = next.length - cursorRef.current
      if (moveLeft > 0) term.write(`\x1b[${moveLeft}D`)
    }

    const submitLine = () => {
      const command = lineRef.current
      term.write("\r\n")
      lineRef.current = ""
      cursorRef.current = 0
      if (!command.trim()) {
        writePrompt()
        return
      }
      if (command.trim() === "clear") {
        term.clear()
        writePrompt()
        return
      }
      if (command.trim() === "history") {
        historyRef.current.forEach((item, index) => term.writeln(`${String(index + 1).padStart(4)}  ${item}`))
        writePrompt()
        return
      }
      if (command.trim() === "help") {
        term.writeln("NanoOps read-only terminal: ls, cat <file>, head/tail, grep, find, ps, df, free, ss/ip, systemctl/journalctl, rpm/yum, cd, pwd")
        term.writeln("Validated pipelines support grep/head/tail/sort/uniq/wc/cut. Shell chaining, redirects, substitutions and interpreters are blocked.")
        writePrompt()
        return
      }
      historyRef.current = [...historyRef.current.filter((item) => item !== command), command].slice(-100)
      historyIndexRef.current = historyRef.current.length
      if (wsRef.current?.readyState === WebSocket.OPEN) {
        awaitingRef.current = true
        wsRef.current.send(JSON.stringify({ type: "input", data: command }))
      } else {
        term.writeln(`\x1b[31m${t("shell.connectionFailed")}\x1b[0m`)
        writePrompt()
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
      if (data === "\x1b[D" || data === "\x1b[C") {
        const next = data === "\x1b[D" ? Math.max(0, cursorRef.current - 1) : Math.min(lineRef.current.length, cursorRef.current + 1)
        if (next !== cursorRef.current) term.write(data)
        cursorRef.current = next
        return
      }
      if (data === "\x1b[H" || data === "\x01") {
        redrawLine(lineRef.current, 0)
        return
      }
      if (data === "\x1b[F" || data === "\x05") {
        redrawLine(lineRef.current, lineRef.current.length)
        return
      }
      if (data === "\x1b[3~") {
        if (cursorRef.current < lineRef.current.length) {
          const next = lineRef.current.slice(0, cursorRef.current) + lineRef.current.slice(cursorRef.current + 1)
          redrawLine(next, cursorRef.current)
        }
        return
      }
      for (const char of data) {
        if (char === "\r" || char === "\n") {
          submitLine()
        } else if (char === "\x7f") {
          if (cursorRef.current > 0) {
            const next = lineRef.current.slice(0, cursorRef.current - 1) + lineRef.current.slice(cursorRef.current)
            redrawLine(next, cursorRef.current - 1)
          }
        } else if (char === "\x03") {
          term.write("^C\r\n")
          redrawLine("")
        } else if (char === "\x15") {
          const next = lineRef.current.slice(cursorRef.current)
          redrawLine(next, 0)
        } else if (char === "\x17") {
          const before = lineRef.current.slice(0, cursorRef.current)
          const cut = before.replace(/\s*\S+\s*$/, "")
          const next = cut + lineRef.current.slice(cursorRef.current)
          redrawLine(next, cut.length)
        } else if (char === "\x0c") {
          term.clear()
          redrawLine(lineRef.current, cursorRef.current)
        } else if (char >= " " && lineRef.current.length < 16_000) {
          const next = lineRef.current.slice(0, cursorRef.current) + char + lineRef.current.slice(cursorRef.current)
          redrawLine(next, cursorRef.current + char.length)
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
  }, [agentId, settings, theme, connect, t, writePrompt])

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
