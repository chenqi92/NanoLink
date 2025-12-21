import { useState } from "react"
import { useTranslation } from "react-i18next"
import { Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from "@/components/ui/card"
import { useAuth } from "@/hooks/use-auth"

interface LoginFormProps {
  onSuccess: () => void
}

export function LoginForm({ onSuccess }: LoginFormProps) {
  const { t } = useTranslation()
  const { login, register } = useAuth()
  const [mode, setMode] = useState<"login" | "register">("login")
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [email, setEmail] = useState("")
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setLoading(true)

    try {
      if (mode === "login") {
        await login(username, password)
      } else {
        await register(username, password, email || undefined)
      }
      onSuccess()
    } catch (err) {
      setError(err instanceof Error ? err.message : t(mode === "login" ? "auth.loginFailed" : "auth.registerFailed"))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-[var(--color-background)] p-4">
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <div className="flex items-center justify-center gap-3 mb-4">
            <svg
              className="h-12 w-12 text-blue-500"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"
              />
            </svg>
            <h1 className="text-3xl font-bold">NanoLink</h1>
          </div>
          <p className="text-[var(--color-muted-foreground)]">Server Monitoring Dashboard</p>
        </div>

        <Card>
          <CardHeader className="text-center">
            <CardTitle>{mode === "login" ? t("auth.login") : t("auth.register")}</CardTitle>
            <CardDescription>
              {mode === "login" ? t("auth.noAccount") : t("auth.hasAccount")}
            </CardDescription>
          </CardHeader>
          <form onSubmit={handleSubmit}>
            <CardContent className="space-y-4">
              {error && (
                <div className="rounded-lg bg-red-500/10 border border-red-500/50 p-3 text-sm text-red-500">
                  {error}
                </div>
              )}

              <div className="space-y-2">
                <label className="text-sm font-medium">{t("auth.username")}</label>
                <Input
                  type="text"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder={t("auth.username")}
                  required
                  minLength={3}
                  maxLength={50}
                  autoComplete="username"
                />
              </div>

              {mode === "register" && (
                <div className="space-y-2">
                  <label className="text-sm font-medium">{t("auth.emailOptional")}</label>
                  <Input
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder={t("auth.email")}
                    autoComplete="email"
                  />
                </div>
              )}

              <div className="space-y-2">
                <label className="text-sm font-medium">{t("auth.password")}</label>
                <Input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder={t("auth.password")}
                  required
                  minLength={4}
                  autoComplete={mode === "login" ? "current-password" : "new-password"}
                />
              </div>
            </CardContent>
            <CardFooter className="flex flex-col gap-4">
              <Button type="submit" className="w-full" disabled={loading}>
                {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {mode === "login" ? t("auth.signIn") : t("auth.signUp")}
              </Button>
              <Button
                type="button"
                variant="link"
                onClick={() => {
                  setMode(mode === "login" ? "register" : "login")
                  setError(null)
                }}
              >
                {mode === "login" ? t("auth.signUp") : t("auth.signIn")}
              </Button>
            </CardFooter>
          </form>
        </Card>

        <p className="mt-8 text-center text-sm text-[var(--color-muted-foreground)]">
          NanoLink Server Monitoring © 2025
        </p>
      </div>
    </div>
  )
}
