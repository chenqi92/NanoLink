import { useTranslation } from "react-i18next"
import { Thermometer, Zap, Cpu } from "lucide-react"
import { Progress } from "@/components/ui/progress"
import { formatBytes, formatPercent, getProgressColor, cn } from "@/lib/utils"
import type { NpuMetrics } from "@/lib/api"

interface NpuCardProps {
  npus: NpuMetrics[]
}

export function NpuCard({ npus }: NpuCardProps) {
  const { t } = useTranslation()

  return (
    <div>
      <div className="text-sm font-medium mb-2">{t("metrics.npus")}</div>
      <div className="space-y-3">
        {npus.map((npu) => {
          const memUsage = npu.memoryTotal > 0 
            ? (npu.memoryUsed / npu.memoryTotal) * 100 
            : 0

          return (
            <div key={npu.index} className="rounded-lg bg-[var(--color-muted)] p-3">
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <Cpu className="h-4 w-4 text-purple-500" />
                  <span className="text-sm font-medium">{npu.name}</span>
                  <span className="text-xs text-[var(--color-muted-foreground)]">
                    {npu.vendor}
                  </span>
                </div>
                {npu.driverVersion && (
                  <span className="text-xs text-[var(--color-muted-foreground)]">
                    Driver: {npu.driverVersion}
                  </span>
                )}
              </div>

              {/* Usage */}
              <div className="mb-2">
                <div className="flex justify-between text-xs mb-1">
                  <span>{t("metrics.usage")}</span>
                  <span className={cn(npu.usagePercent > 80 ? "text-red-500" : "")}>
                    {formatPercent(npu.usagePercent)}
                  </span>
                </div>
                <Progress 
                  value={npu.usagePercent} 
                  className="h-1.5" 
                  indicatorClassName={getProgressColor(npu.usagePercent)} 
                />
              </div>

              {/* Memory */}
              <div className="mb-2">
                <div className="flex justify-between text-xs mb-1">
                  <span>{t("metrics.memory")}</span>
                  <span>
                    {formatBytes(npu.memoryUsed)} / {formatBytes(npu.memoryTotal)}
                  </span>
                </div>
                <Progress 
                  value={memUsage} 
                  className="h-1.5" 
                  indicatorClassName={getProgressColor(memUsage)} 
                />
              </div>

              {/* Stats */}
              <div className="flex gap-4 text-xs">
                <div className="flex items-center gap-1">
                  <Thermometer className="h-3 w-3 text-orange-500" />
                  <span>{npu.temperature}°C</span>
                </div>
                <div className="flex items-center gap-1">
                  <Zap className="h-3 w-3 text-yellow-500" />
                  <span>{npu.powerWatts}W</span>
                </div>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
