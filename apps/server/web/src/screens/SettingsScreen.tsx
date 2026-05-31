import { useEffect, useState, type ReactNode } from "react"
import { useTranslation } from "react-i18next"
import { serverApi, authApi, type ServerInfo } from "@/lib/api"
import { useAuth } from "@/contexts/AuthContext"
import { useSettings, type Tweaks } from "@/store/settings"
import { PageHeader, FormBlock, KVRow } from "@/components/shell/primitives"
import { I } from "@/lib/icons"

function Segmented<T extends string>({ value, options, onChange }: { value: T; options: { v: T; label: ReactNode }[]; onChange: (v: T) => void }) {
  return (
    <div className="row gap-1" style={{ background: "var(--panel-2)", border: "1px solid var(--border)", borderRadius: 6, padding: 3, alignSelf: "flex-start" }}>
      {options.map((o) => (
        <button key={o.v} className="btn btn-sm" onClick={() => onChange(o.v)}
          style={{ height: 24, padding: "0 12px", background: value === o.v ? "var(--panel)" : "transparent", border: value === o.v ? "1px solid var(--border-2)" : "1px solid transparent", color: value === o.v ? "var(--fg)" : "var(--fg-4)" }}>
          {o.label}
        </button>
      ))}
    </div>
  )
}

function Section({ title, icon, children }: { title: ReactNode; icon: ReactNode; children: ReactNode }) {
  return (
    <div className="card" style={{ padding: 0, maxWidth: 760 }}>
      <div className="row gap-2" style={{ padding: "12px 16px", borderBottom: "1px solid var(--border)", alignItems: "center", color: "var(--fg-2)" }}>
        <span style={{ color: "var(--fg-4)" }}>{icon}</span>
        <span style={{ fontSize: 12.5, fontWeight: 500 }}>{title}</span>
      </div>
      <div className="col" style={{ padding: 16, gap: 18 }}>{children}</div>
    </div>
  )
}

const ACCENTS = ["", "#22c55e", "#3b82f6", "#a78bfa", "#f97316", "#ef4444"]

export function SettingsScreen() {
  const { t } = useTranslation()
  const { tweaks, setTweak, lang, setLang } = useSettings()
  const { user } = useAuth()
  const [info, setInfo] = useState<ServerInfo | null>(null)
  const [pwd, setPwd] = useState("")
  const [pwdStatus, setPwdStatus] = useState<"idle" | "busy" | "done" | "error">("idle")

  useEffect(() => { serverApi.info().then(setInfo).catch(() => {}) }, [])

  async function updatePassword() {
    if (pwd.length < 8) return
    setPwdStatus("busy")
    try {
      await authApi.changePassword(pwd)
      setPwd("")
      setPwdStatus("done")
    } catch {
      setPwdStatus("error")
    }
  }

  const set = (k: keyof Tweaks, v: string) => setTweak(k, v as never)

  return (
    <div className="col" style={{ flex: 1, overflow: "hidden" }}>
      <PageHeader title={t("nav.settings")} subtitle={t("plat.settingsSubtitle")} />
      <div className="col" style={{ padding: "0 24px 24px", overflow: "auto", flex: 1, gap: 16 }}>
        <Section title={t("plat.appearance")} icon={I.settings({ size: 13 })}>
          <FormBlock label={t("plat.theme")}>
            <Segmented value={tweaks.theme} onChange={(v) => set("theme", v)} options={[{ v: "dark", label: t("plat.dark") }, { v: "light", label: t("plat.light") }]} />
          </FormBlock>
          <FormBlock label={t("plat.density")}>
            <Segmented value={tweaks.density} onChange={(v) => set("density", v)} options={[{ v: "compact", label: t("plat.compact") }, { v: "regular", label: t("plat.regular") }, { v: "comfy", label: t("plat.comfy") }]} />
          </FormBlock>
          <FormBlock label={t("plat.font")}>
            <Segmented value={tweaks.font} onChange={(v) => set("font", v)} options={[{ v: "sans", label: t("plat.sans") }, { v: "mono", label: t("plat.mono") }]} />
          </FormBlock>
          <FormBlock label={t("plat.cardStyle")}>
            <Segmented value={tweaks.card} onChange={(v) => set("card", v)} options={[{ v: "elevated", label: t("plat.elevated") }, { v: "outlined", label: t("plat.outlined") }, { v: "flat", label: t("plat.flat") }]} />
          </FormBlock>
          <FormBlock label={t("plat.accent")}>
            <div className="row gap-2">
              {ACCENTS.map((a) => (
                <button key={a || "default"} onClick={() => setTweak("accent", a)} title={a || t("plat.accentDefault")}
                  style={{ width: 26, height: 26, borderRadius: 6, cursor: "pointer", background: a || "linear-gradient(135deg,var(--fg),var(--fg-4))", border: tweaks.accent === a ? "2px solid var(--fg)" : "1px solid var(--border-2)" }} />
              ))}
            </div>
          </FormBlock>
          <FormBlock label={t("plat.language")}>
            <Segmented value={lang} onChange={(v) => setLang(v)} options={[{ v: "en", label: "EN" }, { v: "zh", label: "中文" }]} />
          </FormBlock>
        </Section>

        <Section title={t("plat.server")} icon={I.dashboard({ size: 13 })}>
          <KVRow label={t("plat.version")} value={info?.version ? `v${info.version}` : "—"} />
          {info?.serverUrl && <KVRow label="URL" value={info.serverUrl} />}
          {info?.grpcPort && <KVRow label="gRPC" value={String(info.grpcPort)} />}
        </Section>

        <Section title={t("plat.account")} icon={I.user({ size: 13 })}>
          <KVRow label={t("acc.user")} value={user?.username || "—"} mono />
          <KVRow label={t("acc.role")} value={user?.isSuperAdmin ? "SuperAdmin" : "User"} />
          <FormBlock label={t("plat.changePassword")}>
            <div className="row gap-2">
              <input className="input" type="password" autoComplete="new-password" value={pwd} onChange={(e) => { setPwd(e.target.value); setPwdStatus("idle") }} placeholder={t("plat.newPassword")} />
              <button className="btn btn-sm" onClick={updatePassword} disabled={pwd.length < 8 || pwdStatus === "busy"}>{pwdStatus === "busy" && <span className="dot pulse ok" />}{t("plat.updatePassword")}</button>
            </div>
            {pwdStatus === "done" && <span className="badge ok" style={{ marginTop: 6 }}>{t("plat.passwordUpdated")}</span>}
            {pwdStatus === "error" && <span className="badge crit" style={{ marginTop: 6 }}>{t("common.error")}</span>}
          </FormBlock>
        </Section>
      </div>
    </div>
  )
}
