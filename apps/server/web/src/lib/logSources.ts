export interface LogSourcePreset {
  label: string
  path: string
}

/**
 * Suggestions only: the Agent configuration remains the authority for which
 * paths are readable. An empty path asks the Agent to select the platform's
 * normal system log (messages on CentOS/RHEL, syslog elsewhere).
 */
export const LOG_SOURCE_PRESETS: LogSourcePreset[] = [
  { label: "系统日志（自动检测）", path: "" },
  { label: "Nginx · access", path: "/var/log/nginx/access.log" },
  { label: "Nginx · error", path: "/var/log/nginx/error.log" },
  { label: "Java · gateway", path: "/data/lyuav/apps/gateway/logs/uav-gateway.log" },
  { label: "Java · sdk", path: "/data/lyuav/apps/sdk/logs/uav-sdk.log" },
  { label: "Java · system", path: "/data/lyuav/apps/system/logs/uav-system.log" },
  { label: "Java · media", path: "/data/lyuav/apps/media/logs/uav-media.log" },
  { label: "Java · aicaller", path: "/data/lyuav/apps/aicaller/logs/uav-aicallers.log" },
  { label: "Java · gateway app.log", path: "/data/lyuav/apps/gateway/logs/app.log" },
  { label: "Java · sdk app.log", path: "/data/lyuav/apps/sdk/logs/app.log" },
  { label: "Java · system app.log", path: "/data/lyuav/apps/system/logs/app.log" },
  { label: "Java · media app.log", path: "/data/lyuav/apps/media/logs/app.log" },
  { label: "Java · aicaller app.log", path: "/data/lyuav/apps/aicaller/logs/app.log" },
]
