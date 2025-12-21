import { useTranslation } from "react-i18next"
import { X, Terminal as TerminalIcon, Maximize2, Minimize2, Settings } from "lucide-react"
import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Terminal } from "./Terminal"
import { TerminalSettingsDialog, loadTerminalSettings, type TerminalSettings } from "./TerminalSettings"
import { cn } from "@/lib/utils"

interface ShellDialogProps {
  agentId: string
  agentName: string
  onClose: () => void
}

export function ShellDialog({ agentId, agentName, onClose }: ShellDialogProps) {
  const { t } = useTranslation()
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [showSettings, setShowSettings] = useState(false)
  const [settings, setSettings] = useState<TerminalSettings>(loadTerminalSettings)
  // Key to force terminal re-render when settings change
  const [terminalKey, setTerminalKey] = useState(0)

  const handleSettingsChange = (newSettings: TerminalSettings) => {
    setSettings(newSettings)
    setTerminalKey((k) => k + 1) // Force terminal re-render
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
        onClick={onClose}
      />

      {/* Dialog */}
      <div
        className={cn(
          "relative bg-[var(--color-background)] rounded-lg shadow-xl border border-[var(--color-border)] flex flex-col",
          isFullscreen ? "fixed inset-4" : "w-[90vw] max-w-4xl h-[80vh]"
        )}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-[var(--color-border)]">
          <div className="flex items-center gap-2">
            <TerminalIcon className="h-5 w-5 text-green-500" />
            <h2 className="font-semibold">{t("shell.title")}</h2>
            <span className="text-sm text-[var(--color-muted-foreground)]">
              — {agentName}
            </span>
          </div>
          <div className="flex items-center gap-1">
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setShowSettings(true)}
              title="Terminal Settings"
            >
              <Settings className="h-4 w-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setIsFullscreen(!isFullscreen)}
              title={isFullscreen ? "Minimize" : "Maximize"}
            >
              {isFullscreen ? (
                <Minimize2 className="h-4 w-4" />
              ) : (
                <Maximize2 className="h-4 w-4" />
              )}
            </Button>
            <Button variant="ghost" size="icon" onClick={onClose} title="Close">
              <X className="h-4 w-4" />
            </Button>
          </div>
        </div>

        {/* Terminal */}
        <div className="flex-1 p-2 overflow-hidden">
          <Terminal key={terminalKey} agentId={agentId} settings={settings} />
        </div>
      </div>

      {/* Settings Dialog */}
      <TerminalSettingsDialog
        open={showSettings}
        onClose={() => setShowSettings(false)}
        settings={settings}
        onSettingsChange={handleSettingsChange}
      />
    </div>
  )
}
