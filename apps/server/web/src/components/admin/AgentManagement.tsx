import { useState, useEffect, useRef, useMemo } from "react"
import { Plus, Trash2, Copy, RefreshCw, Check, Settings, Wifi, WifiOff, X, GripVertical, AlertTriangle } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { agentTokensApi, type AgentToken } from "@/lib/api"
import { useData } from "@/contexts/DataContext"

const PERMISSION_LEVELS = [
  { value: 0, label: "只读", description: "查看指标和日志" },
  { value: 1, label: "基本写入", description: "上传文件、清理缓存" },
  { value: 2, label: "服务控制", description: "重启服务、管理Docker" },
  { value: 3, label: "系统管理", description: "执行Shell、重启系统" },
]

interface ConfirmState {
  open: boolean
  title: string
  message: string
  onConfirm: () => void
}

export function AgentManagement() {
  // Get real-time agent status from WebSocket
  const { agents: liveAgents } = useData()
  
  const [tokens, setTokens] = useState<AgentToken[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  
  // Form states
  const [showCreateForm, setShowCreateForm] = useState(false)
  const [showTokenResult, setShowTokenResult] = useState(false)
  const [newToken, setNewToken] = useState("")
  const [createForm, setCreateForm] = useState({ name: "", permission: 3 })
  const [copied, setCopied] = useState(false)
  
  // Confirm dialog state
  const [confirmDialog, setConfirmDialog] = useState<ConfirmState>({ open: false, title: "", message: "", onConfirm: () => {} })
  
  // Drag state
  const [draggedIndex, setDraggedIndex] = useState<number | null>(null)
  const dragOverIndex = useRef<number | null>(null)

  // Create a set of online agent IDs from WebSocket data
  const onlineAgentIds = useMemo(() => {
    return new Set(liveAgents.map(a => a.id))
  }, [liveAgents])

  const fetchTokens = async () => {
    try {
      setLoading(true)
      const data = await agentTokensApi.list()
      setTokens(data)
      setError(null)
    } catch (e) {
      setError("加载代理列表失败")
      console.error(e)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchTokens()
    // No polling needed - online status comes from WebSocket via useData()
  }, [])

  const handleCreate = async () => {
    try {
      const result = await agentTokensApi.create(createForm)
      setNewToken(result.token)
      setShowCreateForm(false)
      setShowTokenResult(true)
      setCreateForm({ name: "", permission: 3 })
      fetchTokens()
    } catch (e) {
      console.error(e)
    }
  }

  const handleDelete = (id: number, name: string) => {
    setConfirmDialog({
      open: true,
      title: "删除代理",
      message: `确定要删除 "${name}" 吗？此操作不可撤销。`,
      onConfirm: async () => {
        try {
          await agentTokensApi.delete(id)
          fetchTokens()
        } catch (e) {
          console.error(e)
        }
        setConfirmDialog(prev => ({ ...prev, open: false }))
      }
    })
  }

  const handleRegenerate = (id: number, name: string) => {
    setConfirmDialog({
      open: true,
      title: "重新生成 Token",
      message: `重新生成 "${name}" 的Token后，原Token将立即失效。确定继续吗？`,
      onConfirm: async () => {
        try {
          const result = await agentTokensApi.regenerate(id)
          setNewToken(result.token)
          setShowTokenResult(true)
        } catch (e) {
          console.error(e)
        }
        setConfirmDialog(prev => ({ ...prev, open: false }))
      }
    })
  }

  const copyToClipboard = async (text: string) => {
    await navigator.clipboard.writeText(text)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const formatTime = (timestamp?: number) => {
    if (!timestamp) return "-"
    return new Date(timestamp).toLocaleString("zh-CN")
  }

  // Drag and drop handlers
  const handleDragStart = (index: number) => {
    setDraggedIndex(index)
  }

  const handleDragOver = (e: React.DragEvent, index: number) => {
    e.preventDefault()
    dragOverIndex.current = index
  }

  const handleDragEnd = async () => {
    if (draggedIndex !== null && dragOverIndex.current !== null && draggedIndex !== dragOverIndex.current) {
      const newTokens = [...tokens]
      const [draggedItem] = newTokens.splice(draggedIndex, 1)
      newTokens.splice(dragOverIndex.current, 0, draggedItem)
      setTokens(newTokens)
      
      try {
        await agentTokensApi.reorder(newTokens.map(t => t.id))
      } catch (e) {
        console.error("Failed to save order:", e)
        fetchTokens()
      }
    }
    setDraggedIndex(null)
    dragOverIndex.current = null
  }

  // Check if an agent is online using WebSocket data
  const isAgentOnline = (token: AgentToken): boolean => {
    // Use WebSocket-based live agent data for online detection
    if (token.agentId) {
      return onlineAgentIds.has(token.agentId)
    }
    return false
  }

  return (
    <div className="space-y-6">
      {/* Confirm Dialog */}
      {confirmDialog.open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <Card className="w-full max-w-md mx-4">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <AlertTriangle className="h-5 w-5 text-orange-500" />
                {confirmDialog.title}
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <p className="text-muted-foreground">{confirmDialog.message}</p>
              <div className="flex gap-2 justify-end">
                <Button variant="outline" onClick={() => setConfirmDialog(prev => ({ ...prev, open: false }))}>
                  取消
                </Button>
                <Button variant="destructive" onClick={confirmDialog.onConfirm}>
                  确定
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Settings className="h-6 w-6" />
            代理管理
          </h1>
          <p className="text-muted-foreground">管理代理配置，拖拽调整显示顺序</p>
        </div>
        <Button onClick={() => setShowCreateForm(true)}>
          <Plus className="h-4 w-4 mr-2" />
          添加代理
        </Button>
      </div>

      {/* Error */}
      {error && (
        <div className="bg-destructive/10 text-destructive rounded-lg p-4">
          {error}
        </div>
      )}

      {/* Create Form */}
      {showCreateForm && (
        <Card>
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between">
              <CardTitle>添加代理</CardTitle>
              <Button variant="ghost" size="icon" onClick={() => setShowCreateForm(false)}>
                <X className="h-4 w-4" />
              </Button>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <label className="text-sm font-medium">代理名称</label>
              <Input 
                placeholder="例如：生产服务器、开发机"
                value={createForm.name}
                onChange={(e) => setCreateForm({ ...createForm, name: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <label className="text-sm font-medium">权限级别</label>
              <div className="grid grid-cols-2 gap-2">
                {PERMISSION_LEVELS.map((level) => (
                  <button
                    key={level.value}
                    className={`p-3 rounded-lg border text-left transition-colors ${
                      createForm.permission === level.value
                        ? "border-blue-500 bg-blue-500/10"
                        : "border-border hover:bg-muted"
                    }`}
                    onClick={() => setCreateForm({ ...createForm, permission: level.value })}
                  >
                    <div className="font-medium">{level.label}</div>
                    <div className="text-xs text-muted-foreground">{level.description}</div>
                  </button>
                ))}
              </div>
            </div>
            <div className="flex gap-2 pt-2">
              <Button variant="outline" onClick={() => setShowCreateForm(false)}>取消</Button>
              <Button onClick={handleCreate} disabled={!createForm.name.trim()}>创建</Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Token Result */}
      {showTokenResult && (
        <Card className="border-green-500">
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between">
              <CardTitle className="text-green-600">Token已生成</CardTitle>
              <Button variant="ghost" size="icon" onClick={() => setShowTokenResult(false)}>
                <X className="h-4 w-4" />
              </Button>
            </div>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-muted-foreground mb-3">
              请复制并保存此Token，它只会显示一次。
            </p>
            <div className="flex items-center gap-2">
              <code className="flex-1 p-3 bg-muted rounded text-sm font-mono break-all">
                {newToken}
              </code>
              <Button size="icon" variant="outline" onClick={() => copyToClipboard(newToken)}>
                {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
              </Button>
            </div>
            <p className="text-xs text-muted-foreground mt-3">
              在代理配置文件中设置: <code className="bg-muted px-1 rounded">token = "{newToken}"</code>
            </p>
          </CardContent>
        </Card>
      )}

      {/* Agent List */}
      {loading ? (
        <div className="text-center py-12 text-muted-foreground">加载中...</div>
      ) : tokens.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-muted-foreground">
            暂无代理配置。点击"添加代理"创建连接Token。
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-2">
          {tokens.map((token, index) => {
            const online = isAgentOnline(token)
            return (
              <Card 
                key={token.id} 
                className={`${online ? "border-green-500/50" : ""} ${draggedIndex === index ? "opacity-50" : ""}`}
                draggable
                onDragStart={() => handleDragStart(index)}
                onDragOver={(e) => handleDragOver(e, index)}
                onDragEnd={handleDragEnd}
              >
                <CardContent className="py-3">
                  <div className="flex items-center gap-3">
                    <div className="cursor-grab text-muted-foreground hover:text-foreground">
                      <GripVertical className="h-5 w-5" />
                    </div>
                    
                    {online ? (
                      <Wifi className="h-5 w-5 text-green-500 shrink-0" />
                    ) : (
                      <WifiOff className="h-5 w-5 text-muted-foreground shrink-0" />
                    )}
                    
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-medium truncate">{token.name || token.hostname || `代理 #${token.id}`}</span>
                        <span className={`px-1.5 py-0.5 rounded text-xs ${
                          online ? "bg-green-100 text-green-700 dark:bg-green-900/50 dark:text-green-300" 
                                 : token.firstSeenAt ? "bg-muted text-muted-foreground"
                                 : "bg-orange-100 text-orange-700 dark:bg-orange-900/50 dark:text-orange-300"
                        }`}>
                          {online ? "在线" : token.firstSeenAt ? "离线" : "未连接"}
                        </span>
                        <span className="px-1.5 py-0.5 rounded text-xs bg-muted text-muted-foreground">
                          {PERMISSION_LEVELS.find(p => p.value === token.permission)?.label}
                        </span>
                      </div>
                      <div className="text-xs text-muted-foreground mt-0.5">
                        {token.agentId || "等待Agent连接"} 
                        {token.os && ` • ${token.os}`}
                        {token.lastSeenAt && ` • 最后: ${formatTime(token.lastSeenAt)}`}
                      </div>
                    </div>
                    
                    <div className="flex gap-1 shrink-0">
                      <Button variant="ghost" size="sm" onClick={() => handleRegenerate(token.id, token.name || `代理#${token.id}`)} title="重置Token">
                        <RefreshCw className="h-4 w-4" />
                      </Button>
                      <Button variant="ghost" size="sm" onClick={() => handleDelete(token.id, token.name || `代理#${token.id}`)} title="删除">
                        <Trash2 className="h-4 w-4 text-destructive" />
                      </Button>
                    </div>
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}
