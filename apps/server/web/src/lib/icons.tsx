// icons.tsx — minimal stroke icons, 16x16 viewBox, currentColor.
// Ported from design/nanolink/icons.jsx.
import type { SVGProps, ReactNode } from "react"

export interface IconProps extends Omit<SVGProps<SVGSVGElement>, "d"> {
  size?: number
  sw?: number
  d?: string
  fill?: string
  children?: ReactNode
}

function Icon({ d, size = 16, fill, sw = 1.5, children, ...rest }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth={sw}
      strokeLinecap="round"
      strokeLinejoin="round"
      {...rest}
    >
      {d ? <path d={d} fill={fill || "none"} /> : children}
    </svg>
  )
}

type IconCmp = (p: IconProps) => ReactNode

export const I: Record<string, IconCmp> = {
  brand: ({ size = 18 }: IconProps) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none">
      <rect x="3" y="3" width="8" height="8" rx="1.5" fill="currentColor" />
      <rect x="13" y="3" width="8" height="8" rx="1.5" fill="currentColor" opacity="0.5" />
      <rect x="3" y="13" width="8" height="8" rx="1.5" fill="currentColor" opacity="0.5" />
      <rect x="13" y="13" width="8" height="8" rx="1.5" fill="currentColor" opacity="0.85" />
      <circle cx="17" cy="17" r="1.5" fill="var(--bg)" />
    </svg>
  ),
  dashboard: (p) => <Icon {...p}><rect x="2.5" y="2.5" width="4.5" height="4.5" rx=".5"/><rect x="9" y="2.5" width="4.5" height="4.5" rx=".5"/><rect x="2.5" y="9" width="4.5" height="4.5" rx=".5"/><rect x="9" y="9" width="4.5" height="4.5" rx=".5"/></Icon>,
  agents: (p) => <Icon {...p}><rect x="2" y="3" width="12" height="7" rx="1"/><path d="M5 13h6M8 10v3"/><circle cx="4.5" cy="6.5" r=".5" fill="currentColor"/></Icon>,
  token: (p) => <Icon {...p}><circle cx="6" cy="8" r="3"/><path d="M9 8h5M12 8v2M14 8v1.5"/></Icon>,
  device: (p) => <Icon {...p}><rect x="3" y="2" width="6" height="11" rx="1"/><circle cx="6" cy="11" r=".5" fill="currentColor"/><path d="M11 6l2 2-2 2"/></Icon>,
  users: (p) => <Icon {...p}><circle cx="6" cy="6" r="2.5"/><path d="M2 13c0-2.2 1.8-4 4-4s4 1.8 4 4"/><circle cx="11.5" cy="6.5" r="2"/><path d="M14 12c-.4-1.6-1.7-2.5-3-2.5"/></Icon>,
  group: (p) => <Icon {...p}><circle cx="8" cy="6" r="2.5"/><circle cx="3.5" cy="9" r="1.5"/><circle cx="12.5" cy="9" r="1.5"/><path d="M4 13c.5-1.5 2.1-2.5 4-2.5s3.5 1 4 2.5"/></Icon>,
  audit: (p) => <Icon {...p}><rect x="3" y="2" width="10" height="12" rx="1"/><path d="M5.5 5.5h5M5.5 8h5M5.5 10.5h3"/></Icon>,
  ai: (p) => <Icon {...p}><path d="M8 2v2M8 12v2M2 8h2M12 8h2M3.5 3.5l1.4 1.4M11.1 11.1l1.4 1.4M3.5 12.5l1.4-1.4M11.1 4.9l1.4-1.4"/><circle cx="8" cy="8" r="2.5" fill="currentColor"/></Icon>,
  settings: (p) => <Icon {...p}><circle cx="8" cy="8" r="2"/><path d="M8 1.5v1.5M8 13v1.5M14.5 8H13M3 8H1.5M12.6 3.4l-1 1M4.4 11.6l-1 1M12.6 12.6l-1-1M4.4 4.4l-1-1"/></Icon>,
  cpu: (p) => <Icon {...p}><rect x="4" y="4" width="8" height="8" rx="1"/><rect x="6.5" y="6.5" width="3" height="3" rx=".5" fill="currentColor"/><path d="M6 1.5v2M10 1.5v2M6 12.5v2M10 12.5v2M1.5 6h2M1.5 10h2M12.5 6h2M12.5 10h2"/></Icon>,
  mem: (p) => <Icon {...p}><rect x="2" y="5" width="12" height="6" rx=".5"/><path d="M4 5v6M6 5v6M8 5v6M10 5v6M12 5v6"/></Icon>,
  disk: (p) => <Icon {...p}><ellipse cx="8" cy="4" rx="5" ry="1.5"/><path d="M3 4v8c0 .8 2.2 1.5 5 1.5s5-.7 5-1.5V4M3 8c0 .8 2.2 1.5 5 1.5s5-.7 5-1.5"/></Icon>,
  net: (p) => <Icon {...p}><path d="M2 12c2-3 4-4.5 6-4.5s4 1.5 6 4.5"/><path d="M4 9.5c1.2-1.5 2.5-2.3 4-2.3s2.8.8 4 2.3"/><path d="M6 7c.7-.7 1.3-1 2-1s1.3.3 2 1"/><circle cx="8" cy="12.5" r=".7" fill="currentColor"/></Icon>,
  gpu: (p) => <Icon {...p}><rect x="2" y="5" width="11" height="6" rx=".5"/><circle cx="6" cy="8" r="1.3"/><circle cx="10" cy="8" r="1.3"/><path d="M13 7v2h1.5"/></Icon>,
  npu: (p) => <Icon {...p}><circle cx="8" cy="8" r="2"/><circle cx="8" cy="2.5" r=".7"/><circle cx="8" cy="13.5" r=".7"/><circle cx="2.5" cy="8" r=".7"/><circle cx="13.5" cy="8" r=".7"/><path d="M8 4v2M8 10v2M4 8h2M10 8h2"/></Icon>,
  term: (p) => <Icon {...p}><rect x="2" y="3" width="12" height="10" rx="1"/><path d="M4.5 6.5l2 1.5-2 1.5M8 10h3.5"/></Icon>,
  chart: (p) => <Icon {...p}><path d="M2 13V3M2 13h12"/><path d="M4.5 10.5l2-3 2 1.5 3-5"/></Icon>,
  clock: (p) => <Icon {...p}><circle cx="8" cy="8" r="5.5"/><path d="M8 4.5V8l2.5 1.5"/></Icon>,
  search: (p) => <Icon {...p}><circle cx="7" cy="7" r="4"/><path d="M10 10l3 3"/></Icon>,
  plus: (p) => <Icon {...p}><path d="M8 3v10M3 8h10"/></Icon>,
  x: (p) => <Icon {...p}><path d="M4 4l8 8M12 4l-8 8"/></Icon>,
  check: (p) => <Icon {...p}><path d="M3 8l3 3 7-7"/></Icon>,
  copy: (p) => <Icon {...p}><rect x="5" y="5" width="9" height="9" rx="1"/><path d="M3 11V3a1 1 0 011-1h8"/></Icon>,
  more: (p) => <Icon {...p}><circle cx="3.5" cy="8" r=".8" fill="currentColor"/><circle cx="8" cy="8" r=".8" fill="currentColor"/><circle cx="12.5" cy="8" r=".8" fill="currentColor"/></Icon>,
  chev: (p) => <Icon {...p}><path d="M6 4l4 4-4 4"/></Icon>,
  chevDown: (p) => <Icon {...p}><path d="M4 6l4 4 4-4"/></Icon>,
  back: (p) => <Icon {...p}><path d="M10 4l-4 4 4 4"/></Icon>,
  external: (p) => <Icon {...p}><path d="M9 3h4v4M13 3l-6 6M11 8v5H3V5h5"/></Icon>,
  warn: (p) => <Icon {...p}><path d="M8 2.5l6.5 11h-13L8 2.5z"/><path d="M8 6.5v3M8 11.5v.1"/></Icon>,
  info: (p) => <Icon {...p}><circle cx="8" cy="8" r="6"/><path d="M8 7v4M8 5v.1"/></Icon>,
  qr: (p) => <Icon {...p}><rect x="2" y="2" width="4.5" height="4.5"/><rect x="9.5" y="2" width="4.5" height="4.5"/><rect x="2" y="9.5" width="4.5" height="4.5"/><path d="M9.5 9.5h1.5v1.5M14 9.5v1.5M12.5 11v1.5M9.5 14h1.5M14 14v-1.5"/></Icon>,
  shield: (p) => <Icon {...p}><path d="M8 1.5L2.5 4v4c0 3.5 2.5 6 5.5 6.5 3-.5 5.5-3 5.5-6.5V4L8 1.5z"/><path d="M6 8l1.5 1.5L11 6"/></Icon>,
  bolt: (p) => <Icon {...p}><path d="M9 1.5L3 9h4l-1 5.5L13 7H9l.5-5.5z" fill="currentColor"/></Icon>,
  filter: (p) => <Icon {...p}><path d="M2 3h12M4 7.5h8M6.5 12h3"/></Icon>,
  refresh: (p) => <Icon {...p}><path d="M14 3v3.5h-3.5M2 13v-3.5h3.5"/><path d="M13.5 7c-1-2.5-3.5-4-6-3.5-2 .4-3.5 2-4 4M2.5 9c1 2.5 3.5 4 6 3.5 2-.4 3.5-2 4-4"/></Icon>,
  drag: (p) => <Icon {...p}><circle cx="6" cy="4" r=".8" fill="currentColor"/><circle cx="10" cy="4" r=".8" fill="currentColor"/><circle cx="6" cy="8" r=".8" fill="currentColor"/><circle cx="10" cy="8" r=".8" fill="currentColor"/><circle cx="6" cy="12" r=".8" fill="currentColor"/><circle cx="10" cy="12" r=".8" fill="currentColor"/></Icon>,
  edit: (p) => <Icon {...p}><path d="M3 13l1-3 7-7 2 2-7 7-3 1z"/><path d="M9.5 4.5l2 2"/></Icon>,
  trash: (p) => <Icon {...p}><path d="M2.5 4.5h11M5.5 4.5V3a1 1 0 011-1h3a1 1 0 011 1v1.5M4 4.5l.7 8.5a1 1 0 001 1h4.6a1 1 0 001-1l.7-8.5"/></Icon>,
  power: (p) => <Icon {...p}><path d="M8 2v6"/><path d="M4.5 4.5a5 5 0 107 0"/></Icon>,
  globe: (p) => <Icon {...p}><circle cx="8" cy="8" r="6"/><path d="M2 8h12M8 2c2 2 3 4 3 6s-1 4-3 6c-2-2-3-4-3-6s1-4 3-6z"/></Icon>,
  moon: (p) => <Icon {...p}><path d="M13 9.5A5.5 5.5 0 016.5 3a5.5 5.5 0 106.5 6.5z"/></Icon>,
  sun: (p) => <Icon {...p}><circle cx="8" cy="8" r="3"/><path d="M8 1.5v1.5M8 13v1.5M14.5 8H13M3 8H1.5M12.6 3.4l-1 1M4.4 11.6l-1 1M12.6 12.6l-1-1M4.4 4.4l-1-1"/></Icon>,
  linux: (p) => <Icon {...p}><path d="M5.5 12.5c-.5-1-1-3 0-5 .8-1.6 1.5-3 2.5-3s1.7 1.4 2.5 3c1 2 .5 4 0 5"/><path d="M5.5 12.5c0 1 .5 1.5 2.5 1.5s2.5-.5 2.5-1.5"/><circle cx="6.7" cy="7.5" r=".8" fill="currentColor" stroke="none"/><circle cx="9.3" cy="7.5" r=".8" fill="currentColor" stroke="none"/></Icon>,
  apple: (p) => <Icon {...p}><path d="M11.5 13c-1 0-1.7-.5-2.5-.5s-1.5.5-2.5.5c-2 0-3.5-3-3.5-5.5C3 5 5 4 6.5 4c.8 0 1.5.5 2 .5s1.2-.5 2-.5C12 4 13 5.5 13 7"/><path d="M8.5 4c0-1 1-2 2-2 0 1-1 2-2 2z" fill="currentColor"/></Icon>,
  windows: (p) => <Icon {...p}><rect x="2.5" y="3" width="5" height="5" fill="currentColor" stroke="none"/><rect x="8.5" y="3" width="5" height="5" fill="currentColor" stroke="none"/><rect x="2.5" y="9" width="5" height="5" fill="currentColor" stroke="none"/><rect x="8.5" y="9" width="5" height="5" fill="currentColor" stroke="none"/></Icon>,
  arrow: (p) => <Icon {...p}><path d="M3 8h10M9 4l4 4-4 4"/></Icon>,
  user: (p) => <Icon {...p}><circle cx="8" cy="5.5" r="2.5"/><path d="M2.5 14c0-2.5 2.5-4.5 5.5-4.5s5.5 2 5.5 4.5"/></Icon>,
  arrowUp: (p) => <Icon {...p}><path d="M8 13V3M4 7l4-4 4 4"/></Icon>,
  arrowDown: (p) => <Icon {...p}><path d="M8 3v10M4 9l4 4 4-4"/></Icon>,
  sparkle: (p) => <Icon {...p}><path d="M8 1l1.5 4 4 1.5-4 1.5L8 12l-1.5-4-4-1.5L6.5 5z" fill="currentColor"/></Icon>,
  expand: (p) => <Icon {...p}><path d="M3 6V3h3M13 6V3h-3M3 10v3h3M13 10v3h-3"/></Icon>,
  bell: (p) => <Icon {...p}><path d="M4 11V7a4 4 0 018 0v4l1.5 1.5h-11L4 11z"/><path d="M6.5 13.5a1.5 1.5 0 003 0"/></Icon>,
  history: (p) => <Icon {...p}><path d="M2 8V3M2 8h5"/><path d="M3.5 12c1.2 1 3 1.5 4.5 1.5 3.3 0 6-2.7 6-6s-2.7-6-6-6c-2 0-3.8 1-4.8 2.5"/><path d="M8 5v3.5l2.5 1.5"/></Icon>,
  lock: (p) => <Icon {...p}><rect x="3.5" y="7" width="9" height="7" rx="1"/><path d="M5.5 7V5a2.5 2.5 0 015 0v2"/></Icon>,
  download: (p) => <Icon {...p}><path d="M8 2v8M5 7l3 3 3-3"/><path d="M3 12v1a1 1 0 001 1h8a1 1 0 001-1v-1"/></Icon>,
}

export function osIcon(family?: string, size = 16) {
  if (family === "darwin") return I.apple({ size })
  if (family === "windows") return I.windows({ size })
  return I.linux({ size })
}
