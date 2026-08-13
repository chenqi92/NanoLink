import { useState } from "react"
import { useTranslation } from "react-i18next"
import { I } from "@/lib/icons"
import { useAuth } from "@/contexts/AuthContext"
import { useSettings } from "@/store/settings"
import { FormBlock } from "@/components/shell/primitives"
import { useData } from "@/contexts/DataContext"
import { isOnline } from "@/lib/format"

function LoginVisual() {
  const dots: { x: number; y: number; opacity: number; delay: string }[] = []
  for (let y = 0; y < 11; y++) {
    for (let x = 0; x < 11; x++) {
      const cx = x * 26 + 20
      const cy = y * 26 + 20
      const dist = Math.hypot(x - 5, y - 5)
      const opacity = Math.max(0, 1 - dist / 6)
      const delay = (dist * 0.15).toFixed(2)
      dots.push({ x: cx, y: cy, opacity, delay })
    }
  }
  return (
    <svg width={310} height={310} viewBox="0 0 310 310">
      {dots.map((d, i) => (
        <rect key={i} x={d.x - 3} y={d.y - 3} width={6} height={6} rx={1} fill="var(--fg)" opacity={d.opacity * 0.4} style={{ animation: `dot-pulse 4s ease-in-out infinite ${d.delay}s` }} />
      ))}
      <g transform="translate(155 155)">
        <circle r="34" fill="none" stroke="var(--fg)" strokeWidth="1" opacity="0.3" style={{ animation: "ring 8s linear infinite" }} />
        <circle r="48" fill="none" stroke="var(--fg)" strokeWidth="1" opacity="0.18" strokeDasharray="4 6" />
        <circle r="64" fill="none" stroke="var(--fg)" strokeWidth="1" opacity="0.1" strokeDasharray="2 8" />
        <g>
          <rect x="-12" y="-12" width="24" height="24" rx="3" fill="var(--fg)" />
          <text x="0" y="4" textAnchor="middle" fontSize="11" fontFamily="var(--font-mono)" fill="var(--bg)" fontWeight="700">N</text>
        </g>
      </g>
      <style>{`
        @keyframes dot-pulse { 0%, 100% { opacity: 0.1; } 50% { opacity: 0.6; } }
        @keyframes ring { from { stroke-dashoffset: 0; } to { stroke-dashoffset: 100; } }
      `}</style>
    </svg>
  )
}

export function LoginScreen() {
  const { t } = useTranslation()
  const { login, register, error, sessionExpired, clearError } = useAuth()
  const { lang, setLang } = useSettings()
  const { agents } = useData()

  const [mode, setMode] = useState<"login" | "register">("login")
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [email, setEmail] = useState("")
  const [loading, setLoading] = useState(false)

  const online = agents.filter((a) => isOnline(a.lastHeartbeat)).length

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      if (mode === "login") await login(username, password)
      else await register(username, password, email || undefined)
    } catch {
      // error surfaced via context
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="login-screen">
      {/* visual side */}
      <div className="login-visual">
        <div className="row gap-3" style={{ alignItems: "center" }}>
          {I.brand({ size: 26 })}
          <div className="col" style={{ lineHeight: 1.1, gap: 0 }}>
            <div className="display" style={{ fontSize: 18, fontWeight: 500, letterSpacing: "-0.02em" }}>NanoOps</div>
            <div className="mono dim" style={{ fontSize: 10.5, letterSpacing: "0.04em" }}>{t("auth.brandTagline")}</div>
          </div>
        </div>
        <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <LoginVisual />
        </div>
        <div className="row gap-2" style={{ alignItems: "center", color: "var(--fg-4)", fontSize: 11 }}>
          <span className="dot pulse ok" />
          <span className="mono">{online} / {agents.length} {t("status.connected")}</span>
        </div>
      </div>

      {/* form side */}
      <div className="login-form-pane">
        <div style={{ position: "absolute", top: 20, right: 20, display: "flex", gap: 8 }}>
          <button className="btn btn-ghost btn-sm" onClick={() => setLang(lang === "zh" ? "en" : "zh")}>
            {I.globe({ size: 13 })} <span className="mono">{lang === "zh" ? "中" : "EN"}</span>
          </button>
        </div>
        <form className="login-form" onSubmit={submit}>
          <div className="col" style={{ gap: 24 }}>
            <div className="col" style={{ gap: 6 }}>
              <div className="upper" style={{ color: "var(--fg-4)" }}>{mode === "login" ? t("auth.signIn") : t("auth.signUp")}</div>
              <h1 className="display" style={{ margin: 0, fontSize: 26, fontWeight: 500, letterSpacing: "-0.02em" }}>
                {mode === "login" ? t("auth.welcomeBack") : t("auth.createAccountTitle")}
              </h1>
              <div className="muted" style={{ fontSize: 12 }}>{t("auth.continueMonitoring")}</div>
            </div>

            <FormBlock label={t("auth.username")}>
              <input className="input" value={username} onChange={(e) => { setUsername(e.target.value); clearError() }} autoFocus autoComplete="username" />
            </FormBlock>

            <FormBlock label={t("auth.password")}>
              <input className="input" value={password} onChange={(e) => { setPassword(e.target.value); clearError() }} type="password" autoComplete={mode === "login" ? "current-password" : "new-password"} />
            </FormBlock>

            {mode === "register" && (
              <FormBlock label={t("auth.emailOptional")}>
                <input className="input" value={email} onChange={(e) => setEmail(e.target.value)} type="email" autoComplete="email" />
              </FormBlock>
            )}

            {error && (
              <div className="badge crit" style={{ height: "auto", padding: "8px 10px", whiteSpace: "normal", lineHeight: 1.4 }}>{error}</div>
            )}

            {sessionExpired && !error && (
              <div className="row gap-2" style={{ alignItems: "flex-start", padding: "9px 10px", border: "1px solid var(--border-2)", borderRadius: "var(--radius)", background: "var(--panel-2)", color: "var(--fg-3)", fontSize: 11.5, lineHeight: 1.5 }} role="status">
                <span style={{ color: "var(--warn)", marginTop: 1 }}>{I.lock({ size: 13 })}</span>
                <span>{t("access.sessionNotice")}</span>
              </div>
            )}

            <button type="submit" className="btn btn-primary" style={{ height: 36, justifyContent: "center" }} disabled={loading || !username || !password}>
              {loading ? (
                <>
                  <span className="dot pulse ok" /> <span>{t("auth.signingIn")}</span>
                </>
              ) : (
                <>
                  <span>{mode === "login" ? t("auth.continue") : t("auth.signUp")}</span> {I.arrow({ size: 13 })}
                </>
              )}
            </button>

            <div className="row gap-2" style={{ justifyContent: "center", marginTop: -8 }}>
              <a className="lnk muted" style={{ fontSize: 11.5, cursor: "pointer" }} onClick={() => { setMode(mode === "login" ? "register" : "login"); clearError() }}>
                {mode === "login" ? t("auth.noAccount") : t("auth.hasAccount")}
              </a>
            </div>
          </div>
        </form>
      </div>
    </div>
  )
}
