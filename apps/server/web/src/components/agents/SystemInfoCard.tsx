import { useTranslation } from "react-i18next"
import { Monitor, Server, Cpu, HardDrive, Clock, Globe } from "lucide-react"
import { formatUptime } from "@/lib/utils"
import type { SystemInfo, NetworkMetrics } from "@/lib/api"

interface SystemInfoCardProps {
  systemInfo: SystemInfo
  networks?: NetworkMetrics[]
}

export function SystemInfoCard({ systemInfo, networks }: SystemInfoCardProps) {
  const { t } = useTranslation()

  // Extract primary IP (first non-loopback IPv4 address)
  const primaryIp = (() => {
    if (!networks || networks.length === 0) return null
    for (const net of networks) {
      // Skip loopback and virtual interfaces
      if (net.interfaceType === "loopback" || net.interfaceType === "virtual") continue
      if (!net.isUp) continue
      if (!net.ipAddresses || net.ipAddresses.length === 0) continue
      // Find first IPv4 address (no colons)
      const ipv4 = net.ipAddresses.find(ip => !ip.includes(":"))
      if (ipv4) return ipv4
    }
    return null
  })()

  const items = [
    { icon: Monitor, label: t("system.osName"), value: `${systemInfo.osName} ${systemInfo.osVersion}` },
    { icon: Server, label: t("system.kernel"), value: systemInfo.kernelVersion },
    { icon: Clock, label: t("system.uptime"), value: formatUptime(systemInfo.uptimeSeconds) },
    { icon: HardDrive, label: t("system.motherboard"), value: `${systemInfo.motherboardVendor} ${systemInfo.motherboardModel}` },
    { icon: Cpu, label: t("system.bios"), value: systemInfo.biosVersion },
    { icon: Server, label: t("system.systemModel"), value: `${systemInfo.systemVendor} ${systemInfo.systemModel}` },
    primaryIp ? { icon: Globe, label: t("system.ipAddress", "IP 地址"), value: primaryIp } : null,
  ].filter((item): item is NonNullable<typeof item> => item !== null && !!item.value && item.value.trim() !== "")

  return (
    <div>
      <div className="text-sm font-medium mb-2">{t("system.info")}</div>
      <div className="rounded-lg bg-muted p-3">
        <div className="grid grid-cols-2 gap-2 text-xs">
          {items.map((item, index) => (
            <div key={index} className="flex items-start gap-2">
              <item.icon className="h-3 w-3 mt-0.5 text-muted-foreground" />
              <div>
                <div className="text-muted-foreground">{item.label}</div>
                <div className="font-medium break-words">{item.value}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
