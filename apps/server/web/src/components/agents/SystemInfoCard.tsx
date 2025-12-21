import { useTranslation } from "react-i18next"
import { Monitor, Server, Cpu, HardDrive, Clock } from "lucide-react"
import { formatUptime, formatDate } from "@/lib/utils"
import type { SystemInfo } from "@/lib/api"

interface SystemInfoCardProps {
  systemInfo: SystemInfo
}

export function SystemInfoCard({ systemInfo }: SystemInfoCardProps) {
  const { t } = useTranslation()

  const items = [
    { icon: Monitor, label: t("system.osName"), value: `${systemInfo.osName} ${systemInfo.osVersion}` },
    { icon: Server, label: t("system.kernel"), value: systemInfo.kernelVersion },
    { icon: Clock, label: t("system.uptime"), value: formatUptime(systemInfo.uptimeSeconds) },
    { icon: HardDrive, label: t("system.motherboard"), value: `${systemInfo.motherboardVendor} ${systemInfo.motherboardModel}` },
    { icon: Cpu, label: t("system.bios"), value: systemInfo.biosVersion },
    { icon: Server, label: t("system.systemModel"), value: `${systemInfo.systemVendor} ${systemInfo.systemModel}` },
  ].filter(item => item.value && item.value.trim() !== "")

  return (
    <div>
      <div className="text-sm font-medium mb-2">{t("system.info")}</div>
      <div className="rounded-lg bg-[var(--color-muted)] p-3">
        <div className="grid grid-cols-2 gap-2 text-xs">
          {items.map((item, index) => (
            <div key={index} className="flex items-start gap-2">
              <item.icon className="h-3 w-3 mt-0.5 text-[var(--color-muted-foreground)]" />
              <div>
                <div className="text-[var(--color-muted-foreground)]">{item.label}</div>
                <div className="font-medium truncate max-w-[140px]">{item.value}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
