import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react"
import { assistantApi, mcpApi, type AssistantStatus, type ChatMessage, type ChatResponse, type FindingDTO, type LLMProfile, type McpOverview } from "@/lib/api"
import { useAuth } from "@/contexts/AuthContext"
import i18n from "@/i18n"

export type AssistantMessage = ChatMessage & {
  id: string
  state: "complete" | "pending" | "failed" | "cancelled"
  model?: ChatResponse["model"]
}

export type LoadState<T> = {
  data: T
  loading: boolean
  error: string | null
}

type AssistantContextValue = {
  messages: AssistantMessage[]
  input: string
  setInput: (value: string) => void
  selectedProfileId?: number
  setSelectedProfileId: (id?: number) => void
  status: LoadState<AssistantStatus | null>
  profiles: LoadState<LLMProfile[]>
  findings: LoadState<FindingDTO[]>
  mcp: LoadState<McpOverview | null>
  sending: boolean
  chatError: string | null
  trimmedContext: boolean
  send: (text?: string) => Promise<void>
  retry: () => Promise<void>
  cancel: () => void
  newChat: () => void
  refresh: () => void
  refreshMcp: () => void
}

const AssistantContext = createContext<AssistantContextValue | undefined>(undefined)
let nextMessageId = 0

function messageId() {
  nextMessageId += 1
  return `assistant-message-${nextMessageId}`
}

function errorMessage(error: unknown) {
  if (typeof error === "object" && error !== null && "error" in error) return String((error as { error: unknown }).error)
  return i18n.t("assistant.requestFailed")
}

export function buildAssistantContext(messages: AssistantMessage[], maxMessages = 20, maxBytes = 20 * 1024) {
  const complete = messages.filter((message) => message.state === "complete" && message.content.trim())
  const selected: ChatMessage[] = []
  let bytes = 0
  for (let i = complete.length - 1; i >= 0 && selected.length < maxMessages; i -= 1) {
    const message = complete[i]
    const messageBytes = new TextEncoder().encode(message.content.trim()).byteLength
    if (messageBytes > 4 * 1024 || bytes + messageBytes > maxBytes) break
    selected.unshift({ role: message.role, content: message.content.trim() })
    bytes += messageBytes
  }
  return { messages: selected, trimmed: selected.length < complete.length }
}

export function AssistantProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth()
  const [messages, setMessages] = useState<AssistantMessage[]>([])
  const [input, setInput] = useState("")
  const [selectedProfileId, setSelectedProfileId] = useState<number | undefined>(undefined)
  const [sending, setSending] = useState(false)
  const [chatError, setChatError] = useState<string | null>(null)
  const [status, setStatus] = useState<LoadState<AssistantStatus | null>>({ data: null, loading: true, error: null })
  const [profiles, setProfiles] = useState<LoadState<LLMProfile[]>>({ data: [], loading: true, error: null })
  const [findings, setFindings] = useState<LoadState<FindingDTO[]>>({ data: [], loading: true, error: null })
  const [mcp, setMcp] = useState<LoadState<McpOverview | null>>({ data: null, loading: true, error: null })
  const [trimmedContext, setTrimmedContext] = useState(false)
  const requestRef = useRef<AbortController | null>(null)
  const lastTextRef = useRef<string | null>(null)

  const refresh = useCallback(() => {
    setStatus((current) => ({ ...current, loading: true, error: null }))
    assistantApi.status().then((data) => setStatus({ data, loading: false, error: null })).catch((error) => setStatus((current) => ({ ...current, loading: false, error: errorMessage(error) })))
    setProfiles((current) => ({ ...current, loading: true, error: null }))
    assistantApi.profiles().then((data) => setProfiles({ data, loading: false, error: null })).catch((error) => setProfiles((current) => ({ ...current, loading: false, error: errorMessage(error) })))
    setFindings((current) => ({ ...current, loading: true, error: null }))
    assistantApi.findings().then((data) => setFindings({ data, loading: false, error: null })).catch((error) => setFindings((current) => ({ ...current, loading: false, error: errorMessage(error) })))
  }, [])

  const refreshMcp = useCallback(() => {
    setMcp((current) => ({ ...current, loading: true, error: null }))
    mcpApi.overview().then((data) => setMcp({ data, loading: false, error: null })).catch((error) => setMcp((current) => ({ ...current, loading: false, error: errorMessage(error) })))
  }, [])

  useEffect(() => {
    if (!user) return
    refresh()
    refreshMcp()
    const interval = window.setInterval(refresh, 30000)
    return () => window.clearInterval(interval)
  }, [refresh, refreshMcp, user])

  useEffect(() => {
    requestRef.current?.abort()
    setMessages([])
    setInput("")
    setSelectedProfileId(undefined)
    setChatError(null)
    setSending(false)
  }, [user?.id])

  const cancel = useCallback(() => {
    requestRef.current?.abort()
    requestRef.current = null
    setSending(false)
    setMessages((current) => current.map((message) => message.state === "pending" ? { ...message, state: "cancelled" } : message))
  }, [])

  const newChat = useCallback(() => {
    cancel()
    setMessages([])
    setInput("")
    setChatError(null)
    setTrimmedContext(false)
    lastTextRef.current = null
  }, [cancel])

  const send = useCallback(async (text = input, retryExisting = false) => {
    const content = text.trim()
    if (!content || sending || new TextEncoder().encode(content).byteLength > 4096) return
    const userMessage: AssistantMessage = { id: messageId(), role: "user", content, state: "complete" }
    const pending: AssistantMessage = { id: messageId(), role: "assistant", content: "", state: "pending" }
    let next = [...messages, userMessage]
    if (retryExisting) {
      let failedIndex = -1
      for (let i = messages.length - 1; i >= 0; i -= 1) {
        if (messages[i].role === "assistant" && messages[i].state === "failed") {
          failedIndex = i
          break
        }
      }
      if (failedIndex >= 0 && messages[failedIndex - 1]?.role === "user" && messages[failedIndex - 1].content === content) {
        next = messages.slice(0, failedIndex)
      }
    }
    const context = buildAssistantContext(next, 19)
    setMessages([...next, pending])
    setInput("")
    setChatError(null)
    setTrimmedContext(context.trimmed)
    setSending(true)
    lastTextRef.current = content
    const controller = new AbortController()
    requestRef.current = controller
    try {
      const response = await assistantApi.chat(context.messages, selectedProfileId, controller.signal)
      setMessages((current) => current.map((message) => message.id === pending.id ? { ...message, content: response.reply, state: "complete", model: response.model } : message))
    } catch (error) {
      if (controller.signal.aborted) return
      const message = errorMessage(error)
      setChatError(message)
      setMessages((current) => current.map((item) => item.id === pending.id ? { ...item, content: message, state: "failed" } : item))
    } finally {
      if (requestRef.current === controller) requestRef.current = null
      setSending(false)
    }
  }, [input, messages, selectedProfileId, sending])

  const retry = useCallback(() => lastTextRef.current ? send(lastTextRef.current, true) : Promise.resolve(), [send])

  const value = useMemo<AssistantContextValue>(() => ({
    messages, input, setInput, selectedProfileId, setSelectedProfileId, status, profiles, findings, mcp,
    sending, chatError, trimmedContext, send, retry, cancel, newChat, refresh, refreshMcp,
  }), [cancel, chatError, findings, input, mcp, messages, newChat, profiles, refresh, refreshMcp, retry, selectedProfileId, send, sending, status, trimmedContext])

  return <AssistantContext.Provider value={value}>{children}</AssistantContext.Provider>
}

export function useAssistant() {
  const context = useContext(AssistantContext)
  if (!context) throw new Error("useAssistant must be used within AssistantProvider")
  return context
}
