import { useTranslation } from "react-i18next"
import { X, Terminal as TerminalIcon, Maximize2, Minimize2 } from "lucide-react"
import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Terminal } from "./Terminal"
import { cn } from "@/lib/utils"

interface ShellDialogProps {
  agentId: string
  agentName: string
  onClose: () => void
}

export function ShellDialog({ agentId, agentName, onClose }: ShellDialogProps) {
  const { t } = useTranslation()
  const [isFullscreen, setIsFullscreen] = useState(false)

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
          isFullscreen 
            ? "fixed inset-4" 
            : "w-[90vw] max-w-4xl h-[80vh]"
        )}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-[var(--color-border)]">
          <div className="flex items-center gap-2">
            <TerminalIcon className="h-5 w-5 text-green-500" />
            <h2 className="font-semibold">{t("shell.title")}</h2>
            <span className="text-sm text-[var(--color-muted-foreground)]">— {agentName}</span>
          </div>
          <div className="flex items-center gap-2">
            <Button 
              variant="ghost" 
              size="icon"
              onClick={() => setIsFullscreen(!isFullscreen)}
            >
              {isFullscreen ? (
                <Minimize2 className="h-4 w-4" />
              ) : (
                <Maximize2 className="h-4 w-4" />
              )}
            </Button>
            <Button variant="ghost" size="icon" onClick={onClose}>
              <X className="h-4 w-4" />
            </Button>
          </div>
        </div>

        {/* Terminal */}
        <div className="flex-1 p-2 overflow-hidden">
          <Terminal agentId={agentId} />
        </div>
      </div>
    </div>
  )
}
