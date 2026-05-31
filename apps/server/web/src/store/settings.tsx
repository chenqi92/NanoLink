// settings.tsx — UI tweaks (theme / density / font / card / accent) + language.
// Applies data-* attributes and CSS vars to <html>, persists to localStorage,
// and keeps i18next language in sync.
import React, { createContext, useContext, useCallback, useEffect, useState } from "react"
import i18n, { setLanguage } from "@/i18n"

export type Theme = "dark" | "light"
export type Density = "compact" | "regular" | "comfy"
export type Font = "sans" | "mono"
export type CardStyle = "elevated" | "outlined" | "flat"
export type Lang = "en" | "zh"

export interface Tweaks {
  theme: Theme
  density: Density
  font: Font
  card: CardStyle
  accent: string // "" = theme default (monochrome)
}

const DEFAULTS: Tweaks = {
  theme: "dark",
  density: "regular",
  font: "sans",
  card: "elevated",
  accent: "",
}

const STORAGE_KEY = "nanolink_tweaks"

function loadTweaks(): Tweaks {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) return { ...DEFAULTS, ...JSON.parse(raw) }
  } catch {
    // ignore
  }
  return { ...DEFAULTS }
}

function isLight(hex: string): boolean {
  const c = hex.replace("#", "")
  if (c.length < 6) return false
  const r = parseInt(c.slice(0, 2), 16)
  const g = parseInt(c.slice(2, 4), 16)
  const b = parseInt(c.slice(4, 6), 16)
  return (r * 299 + g * 587 + b * 114) / 1000 > 160
}

interface SettingsContextValue {
  tweaks: Tweaks
  setTweak: <K extends keyof Tweaks>(key: K, value: Tweaks[K]) => void
  lang: Lang
  setLang: (lang: Lang) => void
  toggleTheme: () => void
}

const SettingsContext = createContext<SettingsContextValue | undefined>(undefined)

export function SettingsProvider({ children }: { children: React.ReactNode }) {
  const [tweaks, setTweaks] = useState<Tweaks>(loadTweaks)
  const [lang, setLangState] = useState<Lang>((i18n.language as Lang) === "zh" ? "zh" : "en")

  // Apply theme / density / font / card to <html>
  useEffect(() => {
    const root = document.documentElement
    root.setAttribute("data-theme", tweaks.theme)
    root.setAttribute("data-density", tweaks.density)
    root.setAttribute("data-font", tweaks.font)
    root.setAttribute("data-card", tweaks.card)
  }, [tweaks.theme, tweaks.density, tweaks.font, tweaks.card])

  // Apply accent override (or clear it to use the theme default)
  useEffect(() => {
    const root = document.documentElement
    if (tweaks.accent) {
      root.style.setProperty("--accent", tweaks.accent)
      root.style.setProperty("--accent-fg", isLight(tweaks.accent) ? "#0a0a0a" : "#fafafa")
    } else {
      root.style.removeProperty("--accent")
      root.style.removeProperty("--accent-fg")
    }
  }, [tweaks.accent])

  // Persist
  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(tweaks))
    } catch {
      // ignore
    }
  }, [tweaks])

  const setTweak = useCallback(<K extends keyof Tweaks>(key: K, value: Tweaks[K]) => {
    setTweaks((prev) => ({ ...prev, [key]: value }))
  }, [])

  const toggleTheme = useCallback(() => {
    setTweaks((prev) => ({ ...prev, theme: prev.theme === "dark" ? "light" : "dark" }))
  }, [])

  const setLang = useCallback((next: Lang) => {
    setLangState(next)
    setLanguage(next)
  }, [])

  return (
    <SettingsContext.Provider value={{ tweaks, setTweak, lang, setLang, toggleTheme }}>
      {children}
    </SettingsContext.Provider>
  )
}

export function useSettings() {
  const ctx = useContext(SettingsContext)
  if (!ctx) throw new Error("useSettings must be used within SettingsProvider")
  return ctx
}
