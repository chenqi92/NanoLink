import { useState, useEffect } from "react"
import { Plus, Trash2, QrCode, Smartphone, Monitor, Tablet, Check, X, Power, PowerOff, Edit2, Copy } from "lucide-react"
import { QRCodeSVG } from "qrcode.react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { api } from "@/lib/api"

interface DeviceToken {
  id: number
  deviceName: string
  deviceType: string
  deviceOs: string
  permissionLevel: number
  isActive: boolean
  lastUsedAt: string | null
  lastIp: string
  createdBy: number
  creatorName?: string
  createdAt: string
}

interface GenerateTokenResponse {
  qrData: string
  pairingCode: string
  device: DeviceToken
}

const PERMISSION_LEVELS = [
  { value: 0, label: "只读", color: "bg-blue-100 text-blue-700 dark:bg-blue-900/50 dark:text-blue-300" },
  { value: 1, label: "基本写入", color: "bg-green-100 text-green-700 dark:bg-green-900/50 dark:text-green-300" },
  { value: 2, label: "服务控制", color: "bg-orange-100 text-orange-700 dark:bg-orange-900/50 dark:text-orange-300" },
  { value: 3, label: "系统管理", color: "bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300" },
]

const DEVICE_ICONS: Record<string, typeof Smartphone> = {
  mobile: Smartphone,
  desktop: Monitor,
  tablet: Tablet,
}

export function DeviceManagement() {
  const [devices, setDevices] = useState<DeviceToken[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  
  // QR Modal state
  const [showQrModal, setShowQrModal] = useState(false)
  const [qrData, setQrData] = useState("")
  const [pairingCode, setPairingCode] = useState("")
  
  // Edit modal state
  const [editDevice, setEditDevice] = useState<DeviceToken | null>(null)
  const [editForm, setEditForm] = useState({ deviceName: "", permission: 0, isActive: true })
  
  // Confirm dialog
  const [confirmDialog, setConfirmDialog] = useState<{ open: boolean, message: string, onConfirm: () => void }>({
    open: false, message: "", onConfirm: () => {}
  })
  
  const [copied, setCopied] = useState(false)

  const fetchDevices = async () => {
    try {
      setLoading(true)
      const data = await api.get<DeviceToken[]>("/devices")
      setDevices(data || [])
      setError(null)
    } catch (e) {
      setError("加载设备列表失败")
      console.error(e)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchDevices()
  }, [])

  const handleGenerateToken = async () => {
    try {
      const data = await api.post<GenerateTokenResponse>("/devices/token", { serverName: "NanoLink" })
      setQrData(data.qrData)
      setPairingCode(data.pairingCode)
      setShowQrModal(true)
      fetchDevices()
    } catch (e) {
      console.error(e)
      setError("生成配对码失败")
    }
  }

  const handleUpdateDevice = async () => {
    if (!editDevice) return
    try {
      await api.fetch(`/devices/${editDevice.id}`, {
        method: "PATCH",
        body: JSON.stringify({
          deviceName: editForm.deviceName,
          permissionLevel: editForm.permission,
          isActive: editForm.isActive
        })
      })
      setEditDevice(null)
      fetchDevices()
    } catch (e) {
      // Surface write failures to the user instead of only logging
      setError("更新设备失败")
      console.error(e)
    }
  }

  const handleDelete = (device: DeviceToken) => {
    setConfirmDialog({
      open: true,
      message: `确定要删除设备 "${device.deviceName}" 吗？该设备将无法再连接到服务器。`,
      onConfirm: async () => {
        try {
          await api.delete(`/devices/${device.id}`)
          fetchDevices()
        } catch (e) {
          // Surface write failures to the user instead of only logging
          setError("删除设备失败")
          console.error(e)
        }
        setConfirmDialog(prev => ({ ...prev, open: false }))
      }
    })
  }

  const openEditModal = (device: DeviceToken) => {
    setEditDevice(device)
    setEditForm({
      deviceName: device.deviceName,
      permission: device.permissionLevel,
      isActive: device.isActive
    })
  }

  const copyToClipboard = async (text: string) => {
    try {
      // navigator.clipboard is unavailable / rejects on non-secure (http) origins
      await navigator.clipboard.writeText(text)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch (e) {
      setError("复制失败，请手动复制（需要 HTTPS 安全上下文）")
      console.error(e)
    }
  }

  const formatTime = (timestamp: string | null) => {
    if (!timestamp) return "从未使用"
    return new Date(timestamp).toLocaleString("zh-CN")
  }

  const getDeviceIcon = (type: string) => {
    const Icon = DEVICE_ICONS[type] || Smartphone
    return <Icon className="h-5 w-5" />
  }

  return (
    <div className="space-y-6">
      {/* Confirm Dialog */}
      {confirmDialog.open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <Card className="w-full max-w-md mx-4">
            <CardHeader>
              <CardTitle>确认删除</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <p className="text-muted-foreground">{confirmDialog.message}</p>
              <div className="flex gap-2 justify-end">
                <Button variant="outline" onClick={() => setConfirmDialog(prev => ({ ...prev, open: false }))}>
                  取消
                </Button>
                <Button variant="destructive" onClick={confirmDialog.onConfirm}>
                  删除
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      {/* QR Code Modal */}
      {showQrModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <Card className="w-full max-w-md mx-4">
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between">
                <CardTitle className="flex items-center gap-2">
                  <QrCode className="h-5 w-5" />
                  扫码添加设备
                </CardTitle>
                <Button variant="ghost" size="icon" onClick={() => setShowQrModal(false)}>
                  <X className="h-4 w-4" />
                </Button>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex justify-center p-4 bg-white rounded-lg">
                {qrData ? (
                  <QRCodeSVG 
                    value={qrData} 
                    size={192}
                    level="M"
                    includeMargin={true}
                  />
                ) : (
                  <div className="w-48 h-48 flex items-center justify-center border-2 border-dashed border-gray-300 rounded">
                    <div className="text-center text-sm text-muted-foreground">
                      <QrCode className="h-16 w-16 mx-auto mb-2 text-gray-400" />
                      <p>生成中...</p>
                    </div>
                  </div>
                )}
              </div>
              
              <div className="text-center">
                <p className="text-sm text-muted-foreground mb-2">配对码（有效期60秒）</p>
                <div className="flex items-center justify-center gap-2">
                  <code className="text-2xl font-mono font-bold tracking-widest bg-muted px-4 py-2 rounded">
                    {pairingCode}
                  </code>
                  <Button size="icon" variant="outline" onClick={() => copyToClipboard(pairingCode)}>
                    {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                  </Button>
                </div>
              </div>
              
              <p className="text-xs text-center text-muted-foreground">
                在 NanoLink 移动端或桌面端应用中扫描二维码或输入配对码即可添加此服务器
              </p>
            </CardContent>
          </Card>
        </div>
      )}

      {/* Edit Modal */}
      {editDevice && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <Card className="w-full max-w-md mx-4">
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between">
                <CardTitle>编辑设备</CardTitle>
                <Button variant="ghost" size="icon" onClick={() => setEditDevice(null)}>
                  <X className="h-4 w-4" />
                </Button>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <label className="text-sm font-medium">设备名称</label>
                <Input 
                  value={editForm.deviceName}
                  onChange={(e) => setEditForm({ ...editForm, deviceName: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium">权限级别</label>
                <div className="grid grid-cols-2 gap-2">
                  {PERMISSION_LEVELS.map((level) => (
                    <button
                      key={level.value}
                      className={`p-2 rounded-lg border text-left transition-colors ${
                        editForm.permission === level.value
                          ? "border-blue-500 bg-blue-500/10"
                          : "border-border hover:bg-muted"
                      }`}
                      onClick={() => setEditForm({ ...editForm, permission: level.value })}
                    >
                      <span className="text-sm font-medium">{level.label}</span>
                    </button>
                  ))}
                </div>
              </div>
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium">启用状态</label>
                <Button
                  variant={editForm.isActive ? "default" : "outline"}
                  size="sm"
                  onClick={() => setEditForm({ ...editForm, isActive: !editForm.isActive })}
                >
                  {editForm.isActive ? <Power className="h-4 w-4 mr-2" /> : <PowerOff className="h-4 w-4 mr-2" />}
                  {editForm.isActive ? "已启用" : "已禁用"}
                </Button>
              </div>
              <div className="flex gap-2 pt-2">
                <Button variant="outline" onClick={() => setEditDevice(null)}>取消</Button>
                <Button onClick={handleUpdateDevice}>保存</Button>
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Smartphone className="h-6 w-6" />
            设备管理
          </h1>
          <p className="text-muted-foreground">管理已配对的移动端和桌面端设备</p>
        </div>
        <Button onClick={handleGenerateToken}>
          <Plus className="h-4 w-4 mr-2" />
          生成配对码
        </Button>
      </div>

      {/* Error */}
      {error && (
        <div className="bg-destructive/10 text-destructive rounded-lg p-4">
          {error}
        </div>
      )}

      {/* Device List */}
      {loading ? (
        <div className="text-center py-12 text-muted-foreground">加载中...</div>
      ) : devices.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-muted-foreground">
            <Smartphone className="h-12 w-12 mx-auto mb-4 opacity-50" />
            <p>暂无已配对设备</p>
            <p className="text-sm">点击"生成配对码"添加移动端或桌面端设备</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-3">
          {devices.map((device) => (
            <Card key={device.id} className={!device.isActive ? "opacity-60" : ""}>
              <CardContent className="py-4">
                <div className="flex items-center gap-4">
                  <div className={`p-2 rounded-full ${device.isActive ? "bg-green-100 text-green-600 dark:bg-green-900/50" : "bg-muted text-muted-foreground"}`}>
                    {getDeviceIcon(device.deviceType)}
                  </div>
                  
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-medium truncate">{device.deviceName}</span>
                      <span className={`px-1.5 py-0.5 rounded text-xs ${
                        PERMISSION_LEVELS.find(p => p.value === device.permissionLevel)?.color || "bg-muted"
                      }`}>
                        {PERMISSION_LEVELS.find(p => p.value === device.permissionLevel)?.label}
                      </span>
                      {!device.isActive && (
                        <span className="px-1.5 py-0.5 rounded text-xs bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300">
                          已禁用
                        </span>
                      )}
                    </div>
                    <div className="text-xs text-muted-foreground mt-0.5">
                      {device.deviceOs} • {device.lastIp || "未知IP"} • 最后使用: {formatTime(device.lastUsedAt)}
                    </div>
                  </div>
                  
                  <div className="flex gap-1 shrink-0">
                    <Button variant="ghost" size="sm" onClick={() => openEditModal(device)} title="编辑">
                      <Edit2 className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="sm" onClick={() => handleDelete(device)} title="删除">
                      <Trash2 className="h-4 w-4 text-destructive" />
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
