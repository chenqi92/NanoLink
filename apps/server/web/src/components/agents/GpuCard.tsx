import { useTranslation } from "react-i18next"
import { Thermometer, Zap, Gauge, Fan } from "lucide-react"
import { Progress } from "@/components/ui/progress"
import { formatBytes, formatPercent, getProgressColor, cn } from "@/lib/utils"
import type { GpuMetrics } from "@/lib/api"

interface GpuCardProps {
  gpus: GpuMetrics[]
}

export function GpuCard({ gpus }: GpuCardProps) {
  const { t } = useTranslation()

  return (
    <div>
      <div className="text-sm font-medium mb-2">{t("metrics.gpus")}</div>
      <div className="space-y-3">
        {gpus.map((gpu) => {
          const memUsage = gpu.memoryTotal > 0 
            ? (gpu.memoryUsed / gpu.memoryTotal) * 100 
            : 0

          return (
            <div key={gpu.index} className="rounded-lg bg-[var(--color-muted)] p-3">
              <div className="flex items-center justify-between mb-2">
                <div>
                  <span className="text-sm font-medium">{gpu.name}</span>
                  <span className="text-xs text-[var(--color-muted-foreground)] ml-2">
                    {gpu.vendor}
                  </span>
                </div>
                {gpu.driverVersion && (
                  <span className="text-xs text-[var(--color-muted-foreground)]">
                    Driver: {gpu.driverVersion}
                  </span>
                )}
              </div>

              {/* Usage */}
              <div className="mb-2">
                <div className="flex justify-between text-xs mb-1">
                  <span>{t("metrics.usage")}</span>
                  <span className={cn(gpu.usagePercent > 80 ? "text-red-500" : "")}>
                    {formatPercent(gpu.usagePercent)}
                  </span>
                </div>
                <Progress 
                  value={gpu.usagePercent} 
                  className="h-1.5" 
                  indicatorClassName={getProgressColor(gpu.usagePercent)} 
                />
              </div>

              {/* Memory */}
              <div className="mb-2">
                <div className="flex justify-between text-xs mb-1">
                  <span>VRAM</span>
                  <span>
                    {formatBytes(gpu.memoryUsed)} / {formatBytes(gpu.memoryTotal)}
                  </span>
                </div>
                <Progress 
                  value={memUsage} 
                  className="h-1.5" 
                  indicatorClassName={getProgressColor(memUsage)} 
                />
              </div>

              {/* Stats grid */}
              <div className="grid grid-cols-4 gap-2 text-xs">
                <div className="flex items-center gap-1">
                  <Thermometer className="h-3 w-3 text-orange-500" />
                  <span>{gpu.temperature}°C</span>
                </div>
                <div className="flex items-center gap-1">
                  <Zap className="h-3 w-3 text-yellow-500" />
                  <span>{gpu.powerWatts}W</span>
                </div>
                <div className="flex items-center gap-1">
                  <Gauge className="h-3 w-3 text-blue-500" />
                  <span>{gpu.clockCoreMhz}MHz</span>
                </div>
                <div className="flex items-center gap-1">
                  <Fan className="h-3 w-3 text-cyan-500" />
                  <span>{gpu.fanSpeedPercent}%</span>
                </div>
              </div>

              {/* Encoder/Decoder */}
              {(gpu.encoderUsage > 0 || gpu.decoderUsage > 0) && (
                <div className="flex gap-4 mt-2 text-xs text-[var(--color-muted-foreground)]">
                  <span>Enc: {formatPercent(gpu.encoderUsage)}</span>
                  <span>Dec: {formatPercent(gpu.decoderUsage)}</span>
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
