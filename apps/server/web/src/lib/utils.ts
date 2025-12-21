import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatBytes(bytes: number | undefined): string {
  if (!bytes || bytes === 0) return "0 B"
  const k = 1024
  const sizes = ["B", "KB", "MB", "GB", "TB", "PB"]
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`
}

export function formatBytesPerSec(bytes: number | undefined): string {
  return `${formatBytes(bytes)}/s`
}

export function formatPercent(value: number | undefined): string {
  if (value === undefined || value === null) return "0%"
  return `${value.toFixed(1)}%`
}

export function formatUptime(seconds: number | undefined): string {
  if (!seconds) return "-"
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  
  if (days > 0) return `${days}d ${hours}h ${minutes}m`
  if (hours > 0) return `${hours}h ${minutes}m`
  return `${minutes}m`
}

export function formatTime(date: string | number | undefined): string {
  if (!date) return "-"
  return new Date(date).toLocaleTimeString()
}

export function formatDate(date: string | number | undefined): string {
  if (!date) return "-"
  return new Date(date).toLocaleDateString()
}

export function getStatusColor(value: number): string {
  if (value > 80) return "text-red-500"
  if (value > 50) return "text-yellow-500"
  return "text-green-500"
}

export function getProgressColor(value: number): string {
  if (value > 80) return "bg-red-500"
  if (value > 50) return "bg-yellow-500"
  return "bg-green-500"
}
