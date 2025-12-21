import { useTranslation } from "react-i18next"
import { Cpu, MemoryStick, HardDrive, Network, Gpu, Server } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { formatPercent, formatBytes, cn } from "@/lib/utils"

interface SummaryCardsProps {
  connectedAgents: number
  avgCpu: number
  memoryPercent: number
  totalMemory: number
  usedMemory: number
}

export function SummaryCards({ connectedAgents, avgCpu, memoryPercent, totalMemory, usedMemory }: SummaryCardsProps) {
  const { t } = useTranslation()

  const cards = [
    {
      title: t("dashboard.connectedAgents"),
      value: connectedAgents.toString(),
      icon: Server,
      color: "text-blue-500",
      bgColor: "bg-blue-500/10",
    },
    {
      title: t("dashboard.avgCpu"),
      value: formatPercent(avgCpu),
      icon: Cpu,
      color: avgCpu > 80 ? "text-red-500" : avgCpu > 50 ? "text-yellow-500" : "text-green-500",
      bgColor: avgCpu > 80 ? "bg-red-500/10" : avgCpu > 50 ? "bg-yellow-500/10" : "bg-green-500/10",
    },
    {
      title: t("dashboard.avgMemory"),
      value: formatPercent(memoryPercent),
      subtitle: `${formatBytes(usedMemory)} / ${formatBytes(totalMemory)}`,
      icon: MemoryStick,
      color: memoryPercent > 80 ? "text-red-500" : memoryPercent > 50 ? "text-yellow-500" : "text-green-500",
      bgColor: memoryPercent > 80 ? "bg-red-500/10" : memoryPercent > 50 ? "bg-yellow-500/10" : "bg-green-500/10",
    },
  ]

  return (
    <div className="grid gap-4 md:grid-cols-3">
      {cards.map((card) => (
        <Card key={card.title}>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-[var(--color-muted-foreground)]">
              {card.title}
            </CardTitle>
            <div className={cn("rounded-lg p-2", card.bgColor)}>
              <card.icon className={cn("h-4 w-4", card.color)} />
            </div>
          </CardHeader>
          <CardContent>
            <div className={cn("text-2xl font-bold", card.color)}>{card.value}</div>
            {card.subtitle && (
              <p className="text-xs text-[var(--color-muted-foreground)]">{card.subtitle}</p>
            )}
          </CardContent>
        </Card>
      ))}
    </div>
  )
}
