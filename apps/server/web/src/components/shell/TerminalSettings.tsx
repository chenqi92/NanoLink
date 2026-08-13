import { useState, useEffect } from "react"
import { useTranslation } from "react-i18next"
import { Settings, X, Check, Monitor } from "lucide-react"
import { Button } from "@/components/ui/button"
import { terminalThemes, getThemeById } from "./TerminalThemes"

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
    <div className="scrim" onClick={onClose}>
      <div className="dialog terminal-settings-dialog" role="dialog" aria-modal="true" aria-label={t("terminalSettings.title")} onClick={(event) => event.stopPropagation()}>
        <div className="dialog-hd">
          <div className="terminal-settings-title">
            <Settings size={17} />
            <span>{t("terminalSettings.title")}</span>
          </div>
          <Button variant="ghost" size="icon" onClick={onClose} aria-label={t("common.close")} title={t("common.close")}>
            <X size={14} />
          </Button>
        </div>

        <div className="dialog-bd">
          <section className="terminal-settings-section">
            <h4>{t("terminalSettings.theme")}</h4>
            <div className="terminal-theme-grid">
              {terminalThemes.map((theme) => {
                const active = localSettings.themeId === theme.id
                return (
                  <button
                    key={theme.id}
                    type="button"
                    onClick={() => setLocalSettings({ ...localSettings, themeId: theme.id })}
                    className={`terminal-theme-option${active ? " is-active" : ""}`}
                    aria-pressed={active}
                  >
                    <div
                      className="terminal-theme-preview"
                      style={{ backgroundColor: theme.theme.background, color: theme.theme.foreground as string }}
                    >
                      $ ls -la
                    </div>
                    <div className="terminal-theme-name">{t(`terminalSettings.themes.${theme.id}`, { defaultValue: theme.name })}</div>
                    {active && <span className="terminal-theme-check"><Check size={12} /></span>}
                  </button>
                )
              })}
            </div>
          </section>

          <section className="terminal-settings-section">
            <h4>{t("terminalSettings.font")}</h4>
            <div className="terminal-settings-grid">
              <div className="terminal-settings-field">
                <label htmlFor="terminal-font-family">{t("terminalSettings.fontFamily")}</label>
                <select
                  id="terminal-font-family"
                  className="select"
                  value={localSettings.fontFamily}
                  onChange={(e) => setLocalSettings({ ...localSettings, fontFamily: e.target.value })}
                >
                  {fontFamilies.map((font) => <option key={font.id} value={font.id}>{font.name}</option>)}
                </select>
              </div>
              <div className="terminal-settings-field">
                <label htmlFor="terminal-font-size">{t("terminalSettings.fontSize")}</label>
                <div className="terminal-settings-range">
                  <input
                    id="terminal-font-size"
                    type="range"
                    min="10"
                    max="24"
                    value={localSettings.fontSize}
                    onChange={(e) => setLocalSettings({ ...localSettings, fontSize: Number(e.target.value) })}
                  />
                  <output htmlFor="terminal-font-size">{localSettings.fontSize}</output>
                </div>
              </div>
            </div>
          </section>

          <section className="terminal-settings-section">
            <h4>{t("terminalSettings.cursor")}</h4>
            <div className="terminal-settings-grid">
              <div className="terminal-settings-field">
                <label>{t("terminalSettings.cursorStyle")}</label>
                <div className="terminal-settings-options">
                  {(["block", "underline", "bar"] as const).map((style) => (
                    <Button
                      key={style}
                      variant={localSettings.cursorStyle === style ? "default" : "outline"}
                      size="sm"
                      onClick={() => setLocalSettings({ ...localSettings, cursorStyle: style })}
                    >
                      {t(`terminalSettings.cursor${style[0].toUpperCase()}${style.slice(1)}`)}
                    </Button>
                  ))}
                </div>
              </div>
              <div className="terminal-settings-field">
                <label>{t("terminalSettings.cursorBlink")}</label>
                <Button
                  variant={localSettings.cursorBlink ? "default" : "outline"}
                  size="sm"
                  onClick={() => setLocalSettings({ ...localSettings, cursorBlink: !localSettings.cursorBlink })}
                  aria-pressed={localSettings.cursorBlink}
                >
                  {localSettings.cursorBlink ? t("common.on") : t("common.off")}
                </Button>
              </div>
            </div>
          </section>

          <section className="terminal-settings-section">
            <h4 className="row gap-2"><Monitor size={14} />{t("terminalSettings.preview")}</h4>
            <div
              className="terminal-settings-preview"
              style={{
                backgroundColor: selectedTheme.theme.background,
                color: selectedTheme.theme.foreground as string,
                fontFamily: fontFamilies.find((font) => font.id === localSettings.fontFamily)?.fallback,
                fontSize: localSettings.fontSize,
              }}
            >
              <div>
                <span style={{ color: selectedTheme.theme.green as string }}>user@nanoops</span>
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
              <div style={{ color: selectedTheme.theme.red as string }}>{t("terminalSettings.previewError")}</div>
              <div style={{ color: selectedTheme.theme.yellow as string }}>{t("terminalSettings.previewWarning")}</div>
            </div>
          </section>
        </div>

        <div className="dialog-ft">
          <Button variant="outline" size="sm" onClick={onClose}>{t("common.cancel")}</Button>
          <Button size="sm" onClick={handleSave}>{t("terminalSettings.apply")}</Button>
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
