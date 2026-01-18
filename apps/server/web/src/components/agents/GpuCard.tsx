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
          
          // Check if this is an Apple GPU (unified memory architecture)
          const isAppleGpu = gpu.vendor === "Apple" || 
            gpu.name.toLowerCase().includes("apple") ||
            /^m[1-4]/i.test(gpu.name)
          
          // Check if VRAM is available (not 0)
          const hasVram = gpu.memoryTotal > 0

          return (
            <div key={gpu.index} className="rounded-lg bg-muted p-3">
              <div className="flex items-center justify-between mb-2">
                <div>
                  <span className="text-sm font-medium">{gpu.name}</span>
                  <span className="text-xs text-muted-foreground ml-2">
                    {gpu.vendor}
                  </span>
                </div>
                {gpu.driverVersion && (
                  <span className="text-xs text-muted-foreground">
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

              {/* Memory - show "Unified Memory" for Apple GPUs */}
              <div className="mb-2">
                <div className="flex justify-between text-xs mb-1">
                  <span>VRAM</span>
                  <span>
                    {hasVram 
                      ? `${formatBytes(gpu.memoryUsed)} / ${formatBytes(gpu.memoryTotal)}`
                      : isAppleGpu 
                        ? t("metrics.unifiedMemory", "统一内存")
                        : "N/A"
                    }
                  </span>
                </div>
                {hasVram && (
                  <Progress 
                    value={memUsage} 
                    className="h-1.5" 
                    indicatorClassName={getProgressColor(memUsage)} 
                  />
                )}
              </div>

              {/* Stats grid - only show items that have valid data */}
              <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs">
                {/* Temperature - only show if > 0 */}
                {gpu.temperature > 0 && (
                  <div className="flex items-center gap-1">
                    <Thermometer className="h-3 w-3 text-orange-500" />
                    <span>{gpu.temperature}°C</span>
                  </div>
                )}
                {/* Power - always show */}
                <div className="flex items-center gap-1">
                  <Zap className="h-3 w-3 text-yellow-500" />
                  <span>{gpu.powerWatts}W</span>
                </div>
                {/* Clock - always show */}
                <div className="flex items-center gap-1">
                  <Gauge className="h-3 w-3 text-blue-500" />
                  <span>{gpu.clockCoreMhz}MHz</span>
                </div>
                {/* Fan - only show if > 0 (Apple GPUs don't have dedicated GPU fans) */}
                {gpu.fanSpeedPercent > 0 && (
                  <div className="flex items-center gap-1">
                    <Fan className="h-3 w-3 text-cyan-500" />
                    <span>{gpu.fanSpeedPercent}%</span>
                  </div>
                )}
              </div>

              {/* Encoder/Decoder */}
              {(gpu.encoderUsage > 0 || gpu.decoderUsage > 0) && (
                <div className="flex gap-4 mt-2 text-xs text-muted-foreground">
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
