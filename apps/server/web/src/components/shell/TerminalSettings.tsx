import { useState, useEffect } from "react"
import { useTranslation } from "react-i18next"
import { Settings, X, Check, Monitor } from "lucide-react"
import { Button } from "@/components/ui/button"
import { terminalThemes, getThemeById, type TerminalTheme } from "./TerminalThemes"

export interface TerminalSettings {
  themeId: string
  fontSize: number
  fontFamily: string
  cursorStyle: "block" | "underline" | "bar"
  cursorBlink: boolean
}

export const defaultSettings: TerminalSettings = {
  themeId: "modern-dark",
  fontSize: 14,
  fontFamily: "JetBrains Mono",
  cursorStyle: "block",
  cursorBlink: true,
}

const fontFamilies = [
  { id: "JetBrains Mono", name: "JetBrains Mono", fallback: '"JetBrains Mono", ui-monospace, monospace' },
  { id: "Fira Code", name: "Fira Code", fallback: '"Fira Code", ui-monospace, monospace' },
  { id: "Source Code Pro", name: "Source Code Pro", fallback: '"Source Code Pro", ui-monospace, monospace' },
  { id: "Consolas", name: "Consolas", fallback: 'Consolas, ui-monospace, monospace' },
  { id: "Monaco", name: "Monaco", fallback: 'Monaco, ui-monospace, monospace' },
  { id: "System", name: "System Mono", fallback: 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace' },
]

interface TerminalSettingsDialogProps {
  open: boolean
  onClose: () => void
  settings: TerminalSettings
  onSettingsChange: (settings: TerminalSettings) => void
}

export function TerminalSettingsDialog({
  open,
  onClose,
  settings,
  onSettingsChange,
}: TerminalSettingsDialogProps) {
  const { t } = useTranslation()
  const [localSettings, setLocalSettings] = useState(settings)

  useEffect(() => {
    setLocalSettings(settings)
  }, [settings])

  const handleSave = () => {
    onSettingsChange(localSettings)
    localStorage.setItem("terminalSettings", JSON.stringify(localSettings))
    onClose()
  }

  const selectedTheme = getThemeById(localSettings.themeId)

  if (!open) return null

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-[var(--color-card)] rounded-lg p-6 w-full max-w-2xl mx-4 max-h-[85vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Settings className="h-5 w-5" />
            Terminal Settings
          </h3>
          <Button variant="ghost" size="sm" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>

        {/* Theme Selection */}
        <div className="mb-6">
          <h4 className="text-sm font-medium mb-3">Theme</h4>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            {terminalThemes.map((theme) => (
              <button
                key={theme.id}
                onClick={() => setLocalSettings({ ...localSettings, themeId: theme.id })}
                className={`relative p-3 rounded-lg border-2 transition-all ${
                  localSettings.themeId === theme.id
                    ? "border-blue-500"
                    : "border-[var(--color-border)] hover:border-[var(--color-muted-foreground)]"
                }`}
              >
                {/* Theme preview */}
                <div
                  className="h-16 rounded mb-2 flex items-center justify-center font-mono text-xs"
                  style={{
                    backgroundColor: theme.theme.background,
                    color: theme.theme.foreground as string,
                  }}
                >
                  $ ls -la
                </div>
                <div className="text-xs font-medium truncate">{theme.name}</div>
                {localSettings.themeId === theme.id && (
                  <div className="absolute top-1 right-1 w-5 h-5 bg-blue-500 rounded-full flex items-center justify-center">
                    <Check className="h-3 w-3 text-white" />
                  </div>
                )}
              </button>
            ))}
          </div>
        </div>

        {/* Font Settings */}
        <div className="mb-6">
          <h4 className="text-sm font-medium mb-3">Font</h4>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs text-[var(--color-muted-foreground)] mb-1">
                Font Family
              </label>
              <select
                value={localSettings.fontFamily}
                onChange={(e) => setLocalSettings({ ...localSettings, fontFamily: e.target.value })}
                className="w-full px-3 py-2 border border-[var(--color-border)] rounded bg-[var(--color-background)]"
              >
                {fontFamilies.map((font) => (
                  <option key={font.id} value={font.id}>
                    {font.name}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs text-[var(--color-muted-foreground)] mb-1">
                Font Size
              </label>
              <div className="flex items-center gap-2">
                <input
                  type="range"
                  min="10"
                  max="24"
                  value={localSettings.fontSize}
                  onChange={(e) =>
                    setLocalSettings({ ...localSettings, fontSize: parseInt(e.target.value) })
                  }
                  className="flex-1"
                />
                <span className="text-sm w-8 text-center">{localSettings.fontSize}</span>
              </div>
            </div>
          </div>
        </div>

        {/* Cursor Settings */}
        <div className="mb-6">
          <h4 className="text-sm font-medium mb-3">Cursor</h4>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs text-[var(--color-muted-foreground)] mb-1">
                Cursor Style
              </label>
              <div className="flex gap-2">
                {(["block", "underline", "bar"] as const).map((style) => (
                  <button
                    key={style}
                    onClick={() => setLocalSettings({ ...localSettings, cursorStyle: style })}
                    className={`flex-1 px-3 py-2 border rounded capitalize transition-all ${
                      localSettings.cursorStyle === style
                        ? "border-blue-500 bg-blue-500/10"
                        : "border-[var(--color-border)] hover:border-[var(--color-muted-foreground)]"
                    }`}
                  >
                    {style}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label className="block text-xs text-[var(--color-muted-foreground)] mb-1">
                Cursor Blink
              </label>
              <button
                onClick={() =>
                  setLocalSettings({ ...localSettings, cursorBlink: !localSettings.cursorBlink })
                }
                className={`w-full px-3 py-2 border rounded transition-all ${
                  localSettings.cursorBlink
                    ? "border-blue-500 bg-blue-500/10"
                    : "border-[var(--color-border)]"
                }`}
              >
                {localSettings.cursorBlink ? "On" : "Off"}
              </button>
            </div>
          </div>
        </div>

        {/* Preview */}
        <div className="mb-6">
          <h4 className="text-sm font-medium mb-3 flex items-center gap-2">
            <Monitor className="h-4 w-4" />
            Preview
          </h4>
          <div
            className="rounded-lg p-4 font-mono text-sm leading-relaxed"
            style={{
              backgroundColor: selectedTheme.theme.background,
              color: selectedTheme.theme.foreground as string,
              fontFamily: fontFamilies.find((f) => f.id === localSettings.fontFamily)?.fallback,
              fontSize: localSettings.fontSize,
            }}
          >
            <div>
              <span style={{ color: selectedTheme.theme.green as string }}>user@nanolink</span>
              <span style={{ color: selectedTheme.theme.white as string }}>:</span>
              <span style={{ color: selectedTheme.theme.blue as string }}>~</span>
              <span style={{ color: selectedTheme.theme.white as string }}>$ </span>
              ls -la
            </div>
            <div>
              <span style={{ color: selectedTheme.theme.blue as string }}>drwxr-xr-x</span>
              <span> 5 user user 4096 Dec 21 </span>
              <span style={{ color: selectedTheme.theme.cyan as string }}>Documents</span>
            </div>
            <div style={{ color: selectedTheme.theme.red as string }}>
              error: permission denied
            </div>
            <div style={{ color: selectedTheme.theme.yellow as string }}>
              warning: file not found
            </div>
          </div>
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={handleSave}>Apply Settings</Button>
        </div>
      </div>
    </div>
  )
}

export function loadTerminalSettings(): TerminalSettings {
  try {
    const saved = localStorage.getItem("terminalSettings")
    if (saved) {
      return { ...defaultSettings, ...JSON.parse(saved) }
    }
  } catch {
    // Ignore
  }
  return defaultSettings
}
