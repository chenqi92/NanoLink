import SwiftUI

/// Full node detail with realtime metrics, historical charts and remote terminal.
struct AgentDetailScreen: View {
    let agent: Agent
    var initialTab: Int = 0
    /// Hidden when the detail is already the persistent pane of a split layout,
    /// where there is nothing to dismiss back to.
    var showsBackButton: Bool = true

    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Int
    @State private var showActions = false

    init(agent: Agent, initialTab: Int = 0, showsBackButton: Bool = true) {
        self.agent = agent
        self.initialTab = initialTab
        self.showsBackButton = showsBackButton
        _tab = State(initialValue: initialTab == 2 && agent.permissionLevel < 3 ? 0 : initialTab)
    }

    private var currentAgent: Agent { store.agentById(agent.id) ?? agent }

    var body: some View {
        VStack(spacing: 0) {
            header
            segmented.padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            Group {
                switch tab {
                case 1: AgentHistoryView(agent: currentAgent, metrics: store.metricsFor(agent.id))
                case 2: NanoTerminalView(agent: currentAgent)
                default: AgentRealtimeView(agent: currentAgent, metrics: store.metricsFor(agent.id))
                }
            }
        }
        .background(t.bg.ignoresSafeArea())
        .nanoNavigationBarHidden(!t.desktop)
        .navigationTitle(t.desktop ? currentAgent.hostname : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if t.desktop {
                ToolbarItem(placement: .primaryAction) {
                    Button { showActions = true } label: {
                        Label(tr("actions.title"), systemImage: "ellipsis.circle")
                    }
                    .help(tr("actions.title"))
                }
            }
        }
        .sheet(isPresented: $showActions) {
            AgentActionsSheet(agent: currentAgent) { tab = 2 }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            // The Mac window supplies back navigation and the actions menu in its
            // own chrome, so the in-content button row is touch-only.
            if !t.desktop {
                HStack {
                    if showsBackButton {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(t.accent)
                                .frame(width: 36, height: 36)
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button { showActions = true } label: {
                        Image(systemName: "ellipsis").font(.system(size: 20)).foregroundColor(t.accent).frame(width: 36, height: 36)
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                NanoIconBox(icon: osIcon(currentAgent.os), size: 44, iconSize: 22)
                VStack(alignment: .leading, spacing: 3) {
                    NanoMono(currentAgent.hostname, size: 19, color: t.fg, weight: .bold).lineLimit(1)
                    HStack(spacing: 7) {
                        NanoStatusLabel(status: currentAgent.isOnline ? "online" : "offline")
                        Text("·").foregroundColor(t.fg4)
                        Text("\(currentAgent.os) · \(currentAgent.arch)").font(.system(size: 11.5)).foregroundColor(t.fg3).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NanoPermPill(level: currentAgent.permissionLevel)
            }
            HStack(spacing: 8) {
                NanoMono(tr("agentDetail.agentVersion", ["version": currentAgent.version.isEmpty ? "—" : currentAgent.version]), size: 11, color: t.fg4)
                Text("·").font(.system(size: 11)).foregroundColor(t.fg4)
                NanoMono(tr("agentDetail.heartbeat", ["ago": currentAgent.lastHeartbeat.map(Fmt.ago) ?? "—"]), size: 11, color: t.fg4)
                Spacer()
            }
        }
        .padding(EdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 8))
    }

    private var segmented: some View {
        let titles = [tr("agentDetail.tabRealtime"), tr("agentDetail.tabHistory"), tr("agentDetail.tabTerminal")]
        return HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                let locked = index == 2 && currentAgent.permissionLevel < 3
                Button {
                    if !locked { tab = index }
                } label: {
                    Text(locked ? tr("agentDetail.tabTerminalLocked") : titles[index])
                        .font(.system(size: 13.5, weight: tab == index ? .semibold : .medium))
                        .foregroundColor(tab == index ? t.fg : (locked ? t.fg5 : t.fg2))
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(tab == index ? t.card : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .padding(3).background(t.card2).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct AgentRealtimeView: View {
    let agent: Agent
    let metrics: AgentMetrics?
    @Environment(\.nano) private var t
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Single column on phones; wide windows fit two or more headline cards.
    private var headlineColumns: [GridItem] {
        horizontalSizeClass == .compact
            ? [GridItem(.flexible(), spacing: 12, alignment: .top)]
            : [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)]
    }

    var body: some View {
        if !agent.isOnline || metrics == nil {
            VStack(spacing: 12) {
                Image(systemName: "icloud.slash").font(.system(size: 30)).foregroundColor(t.fg4)
                Text(tr("agentDetail.nodeOffline")).font(.system(size: 16, weight: .semibold)).foregroundColor(t.fg2)
                Text(tr("agentDetail.lastHeartbeat", ["ago": agent.lastHeartbeat.map(Fmt.ago) ?? "—"]))
                    .font(.system(size: 13)).foregroundColor(t.fg4)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let m = metrics {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    LazyVGrid(columns: headlineColumns, spacing: 12) {
                        cpuCard(m)
                        memoryCard(m)
                    }

                    if !m.disks.isEmpty {
                        NanoSectionLabel(tr("agentDetail.storage"))
                        NanoCard {
                            ForEach(Array(m.disks.enumerated()), id: \.element.id) { index, disk in
                                diskRow(disk, divider: index < m.disks.count - 1)
                            }
                        }
                    }
                    if !m.networks.isEmpty {
                        NanoSectionLabel(tr("agentDetail.networkInterfaces"))
                        NanoCard {
                            ForEach(Array(m.networks.enumerated()), id: \.element.id) { index, net in
                                networkRow(net, divider: index < m.networks.count - 1)
                            }
                        }
                    }
                    if !m.gpus.isEmpty {
                        NanoSectionLabel(tr("agentDetail.gpu")) {
                            NanoMono(tr("agentDetail.gpuCount", ["n": m.gpus.count]), size: 11, color: t.fg4)
                        }
                        ForEach(m.gpus) { gpu in gpuCard(gpu).padding(.bottom, 8) }
                    }
                    if !m.npus.isEmpty {
                        NanoSectionLabel(tr("agentDetail.aiAccelerator"))
                        NanoCard {
                            ForEach(Array(m.npus.enumerated()), id: \.element.id) { index, npu in
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        NanoMono(npu.name, size: 13.5, color: t.fg, weight: .semibold)
                                        Spacer()
                                        if let temp = npu.temperature { NanoMono("\(Int(temp))°C", size: 11, color: temp > 75 ? t.warn : t.fg4) }
                                    }
                                    metricBar(tr("agentDetail.utilization"), pct: npu.usagePercent,
                                              value: String(format: "%.0f%%", npu.usagePercent))
                                }
                                .padding(14)
                                .overlay(alignment: .bottom) { if index < m.npus.count - 1 { Rectangle().fill(t.sep2).frame(height: 0.5) } }
                            }
                        }
                    }
                    if !m.userSessions.isEmpty {
                        NanoSectionLabel(tr("agentDetail.loginSessions")) {
                            NanoMono("\(m.userSessions.count)", size: 11, color: t.fg4)
                        }
                        NanoCard {
                            ForEach(Array(m.userSessions.enumerated()), id: \.element.id) { index, session in
                                NanoListRow(divider: index < m.userSessions.count - 1) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        NanoMono(session.username, size: 13.5, color: t.fg, weight: .semibold)
                                        NanoMono("\(session.tty) · \(session.remoteHost)", size: 11, color: t.fg4)
                                    }
                                } trailing: { NanoBadge(text: session.sessionType) }
                            }
                        }
                    }
                    if let info = m.systemInfo {
                        NanoSectionLabel(tr("agentDetail.systemInfo"))
                        NanoCard { systemInfo(info) }
                    }
                }
                .padding(EdgeInsets(top: 4, leading: 16, bottom: 40, trailing: 16))
            }
        }
    }

    private func cpuCard(_ m: AgentMetrics) -> some View {
        let cpu = m.cpuPercent
        return NanoCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(tr("agentDetail.cpu"), systemImage: "cpu").font(.system(size: 12, weight: .medium)).foregroundColor(t.fg3)
                        Text(String(format: "%.0f%%", cpu)).font(.system(size: 32, weight: .semibold)).foregroundColor(t.usageColor(cpu)).monospacedDigit()
                        NanoMono(cpuMeta(m.cpu), size: 11, color: t.fg4).lineLimit(1)
                    }
                    Spacer()
                    NanoDonut(value: cpu, size: 72, thickness: 6, label: String(format: "%.0f%%", cpu), sub: "\(m.cpu.coreCount)c")
                }
                if !m.cpu.loadAverage.isEmpty {
                    HStack {
                        Text(tr("agentDetail.perCore")).font(.system(size: 11, weight: .medium)).foregroundColor(t.fg4)
                        Spacer()
                        NanoMono(tr("agentDetail.load", ["values": m.cpu.loadAverage.prefix(3).map { String(format: "%.2f", $0) }.joined(separator: " / ")]), size: 11, color: t.fg4)
                    }
                }
                if !m.cpu.perCoreUsage.isEmpty {
                    NanoCoreMatrix(cores: m.cpu.perCoreUsage, cols: min(max(m.cpu.perCoreUsage.count, 1), 16))
                }
            }
        }
    }

    private func cpuMeta(_ cpu: CpuMetrics) -> String {
        var parts: [String] = []
        if let ghz = cpu.frequencyGhz { parts.append(tr("agentDetail.ghz", ["value": String(format: "%.2f", ghz)])) }
        if !cpu.model.isEmpty { parts.append(cpu.model) }
        if let temp = cpu.temperature { parts.insert("\(Int(temp))°C", at: 0) }
        return parts.joined(separator: " · ")
    }

    private func memoryCard(_ m: AgentMetrics) -> some View {
        let mem = m.memoryPercent
        return NanoCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(tr("agentDetail.memory"), systemImage: "memorychip").font(.system(size: 12, weight: .medium)).foregroundColor(t.fg3)
                        Text(String(format: "%.0f%%", mem)).font(.system(size: 32, weight: .semibold)).foregroundColor(t.usageColor(mem)).monospacedDigit()
                        NanoMono("\(String(format: "%.1f", Fmt.gib(Double(m.memory.used)))) / \(String(format: "%.0f", Fmt.gib(Double(m.memory.total)))) GiB", size: 11, color: t.fg4)
                    }
                    Spacer()
                    NanoDonut(value: mem, size: 72, thickness: 6, label: String(format: "%.0f%%", mem), sub: "\(Int(Fmt.gib(Double(m.memory.total))))G")
                }
                keyValue(tr("agentDetail.memUsed"), "\(String(format: "%.1f", Fmt.gib(Double(m.memory.used)))) GiB")
                keyValue(tr("agentDetail.memAvailable"), "\(String(format: "%.1f", Fmt.gib(Double(m.memory.available)))) GiB")
                if m.memory.cached > 0 || m.memory.buffers > 0 {
                    keyValue(tr("agentDetail.cacheBuffers"), "\(String(format: "%.1f", Fmt.gib(Double(m.memory.cached)))) / \(String(format: "%.1f", Fmt.gib(Double(m.memory.buffers)))) GiB")
                }
                if m.memory.swapTotal > 0 {
                    keyValue(tr("agentDetail.swap"), "\(String(format: "%.1f", Fmt.gib(Double(m.memory.swapUsed)))) / \(String(format: "%.0f", Fmt.gib(Double(m.memory.swapTotal)))) GiB",
                             warn: Double(m.memory.swapUsed) / Double(m.memory.swapTotal) > 0.2)
                }
            }
        }
    }

    private func diskRow(_ disk: DiskMetrics, divider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    NanoMono(disk.mountPoint, size: 14, color: t.fg, weight: .semibold)
                    NanoMono([disk.device, disk.fsType, disk.diskType ?? ""].filter { !$0.isEmpty }.joined(separator: " · "), size: 11, color: t.fg4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.0f%%", disk.usagePercent)).font(.system(size: 15, weight: .semibold)).foregroundColor(t.usageColor(disk.usagePercent)).monospacedDigit()
                    NanoMono("\(Int(Fmt.gib(Double(disk.used))))/\(Int(Fmt.gib(Double(disk.total)))) GiB", size: 11, color: t.fg4)
                }
            }
            NanoMeter(value: disk.usagePercent / 100)
            HStack(spacing: 12) {
                NanoMono("R \(Fmt.rate(disk.readBytesPerSec))", size: 11, color: t.fg4)
                NanoMono("W \(Fmt.rate(disk.writeBytesPerSec))", size: 11, color: t.fg4)
                if let temp = disk.temperature { NanoMono("\(Int(temp))°C", size: 11, color: temp > 55 ? t.warn : t.fg4) }
                Spacer()
                if let health = disk.healthStatus { NanoBadge(text: health, color: healthColor(health)) }
            }
        }
        .padding(14)
        .overlay(alignment: .bottom) { if divider { Rectangle().fill(t.sep2).frame(height: 0.5) } }
    }

    private func networkRow(_ net: NetworkMetrics, divider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                NanoStatusDot(color: net.isUp ? t.ok : t.crit)
                NanoMono(net.interfaceName, size: 14, color: t.fg, weight: .semibold)
                if let type = net.interfaceType { NanoBadge(text: type) }
                Spacer()
                if let speed = net.speedMbps { NanoMono(String(format: "%.0f Gb/s", speed / 1000), size: 11, color: t.fg4) }
            }
            if !net.ipAddresses.isEmpty { NanoMono(net.ipAddresses.joined(separator: " · "), size: 11.5, color: t.fg3).lineLimit(1) }
            HStack(spacing: 14) {
                NanoMono("↓ \(Fmt.rate(net.rxBytesPerSec))", size: 12, color: t.fg2)
                NanoMono("↑ \(Fmt.rate(net.txBytesPerSec))", size: 12, color: t.fg2)
            }
        }
        .padding(14)
        .overlay(alignment: .bottom) { if divider { Rectangle().fill(t.sep2).frame(height: 0.5) } }
    }

    private func gpuCard(_ gpu: GpuMetrics) -> some View {
        NanoCard(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        NanoMono(gpu.name, size: 13.5, color: t.fg, weight: .semibold).lineLimit(1)
                        NanoMono([gpu.driverVersion ?? "", gpu.pcieGeneration ?? ""].filter { !$0.isEmpty }.joined(separator: " · "), size: 10.5, color: t.fg4)
                    }
                    Spacer()
                    if let temp = gpu.temperature { NanoMono("\(Int(temp))°C", size: 11, color: temp > 75 ? t.warn : t.fg3) }
                }
                metricBar(tr("agentDetail.utilization"), pct: gpu.usagePercent, value: String(format: "%.0f%%", gpu.usagePercent))
                if gpu.memoryTotal > 0 {
                    metricBar(tr("agentDetail.vram"), pct: gpu.vramPercent,
                              value: "\(String(format: "%.1f", Fmt.gib(Double(gpu.memoryUsed))))/\(String(format: "%.0f", Fmt.gib(Double(gpu.memoryTotal)))) GB")
                }
                if let power = gpu.powerWatts {
                    if let limit = gpu.powerLimitWatts, limit > 0 {
                        metricBar(tr("agentDetail.power"), pct: min(power / limit * 100, 100),
                                  value: tr("agentDetail.powerOf", ["used": String(format: "%.0f", power), "limit": String(format: "%.0f", limit)]))
                    } else { keyValue(tr("agentDetail.power"), String(format: "%.0fW", power)) }
                }
            }
        }
    }

    private func metricBar(_ label: String, pct: Double, value: String) -> some View {
        VStack(spacing: 3) {
            HStack { Text(label).font(.system(size: 11.5)).foregroundColor(t.fg4); Spacer(); NanoMono(value, size: 11.5, color: t.fg2) }
            NanoMeter(value: pct / 100)
        }
    }

    private func keyValue(_ key: String, _ value: String, warn: Bool = false) -> some View {
        HStack { Text(key).font(.system(size: 12.5)).foregroundColor(t.fg4); Spacer(); NanoMono(value, size: 12.5, color: warn ? t.warn : t.fg2) }.padding(.top, 4)
    }

    private func systemInfo(_ info: SystemInfo) -> some View {
        let board = [info.motherboardVendor ?? "", info.motherboardName ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        let system = [info.systemVendor ?? "", info.systemModel ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        let rows: [(String, String)] = [
            (tr("agentDetail.osLabel"), "\(info.osName) \(info.osVersion)"),
            (tr("agentDetail.kernel"), info.kernelVersion),
            (tr("agentDetail.uptime"), Fmt.uptime(info.uptimeSeconds)),
            (tr("agentDetail.motherboard"), board),
            (tr("agentDetail.systemModel"), system),
            (tr("agentDetail.chassis"), info.chassis ?? ""),
            (tr("agentDetail.bios"), info.biosVersion ?? ""),
            (tr("agentDetail.primaryIp"), info.primaryIp ?? ""),
        ].filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top) {
                    Text(row.0).font(.system(size: 14)).foregroundColor(t.fg3)
                    Spacer(minLength: 12)
                    Text(row.1).font(.system(size: 13.5)).foregroundColor(t.fg2).multilineTextAlignment(.trailing)
                }
                .padding(14)
                .overlay(alignment: .bottom) { if index < rows.count - 1 { Rectangle().fill(t.sep2).frame(height: 0.5) } }
            }
        }
    }

    private func healthColor(_ health: String) -> Color {
        let h = health.lowercased()
        if h.contains("fail") || h.contains("crit") || h.contains("bad") { return t.crit }
        if h.contains("warn") || h.contains("degrad") { return t.warn }
        return t.ok
    }
}

private struct AgentHistoryView: View {
    let agent: Agent
    let metrics: AgentMetrics?
    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var range = "1h"
    @State private var history: MetricsHistory?
    @State private var loading = false
    @State private var failed = false

    /// Charts need more width than the headline cards before splitting.
    private var chartColumns: [GridItem] {
        horizontalSizeClass == .compact
            ? [GridItem(.flexible(), spacing: 12, alignment: .top)]
            : [GridItem(.adaptive(minimum: 380), spacing: 12, alignment: .top)]
    }

    private struct RangeSpec { let seconds: TimeInterval; let interval: String; let labels: [String] }
    private let ranges = ["5m", "30m", "1h", "6h", "1d", "7d"]
    private func spec(_ value: String) -> RangeSpec {
        switch value {
        case "5m": return RangeSpec(seconds: 300, interval: "1m", labels: ["-5m", "-2m", "now"])
        case "30m": return RangeSpec(seconds: 1800, interval: "1m", labels: ["-30m", "-15m", "now"])
        case "6h": return RangeSpec(seconds: 21600, interval: "5m", labels: ["-6h", "-3h", "now"])
        case "1d": return RangeSpec(seconds: 86400, interval: "1h", labels: ["-24h", "-12h", "now"])
        case "7d": return RangeSpec(seconds: 604800, interval: "1h", labels: ["-7d", "-3d", "now"])
        default: return RangeSpec(seconds: 3600, interval: "auto", labels: ["-60m", "-30m", "now"])
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                rangePicker
                if loading { ProgressView().controlSize(.large).padding(.vertical, 48) }
                else if failed { hint("icloud.slash", tr("history.loadFailed"), tr("history.loadFailedSub")) }
                else if let history, !history.isEmpty { charts(history) }
                else { hint("chart.xyaxis.line", tr("history.noData"), tr("history.noDataSub")) }
            }
            .padding(EdgeInsets(top: 4, leading: 16, bottom: 40, trailing: 16))
        }
        .nanoPullToRefresh(enabled: !t.desktop) { await load() }
        .task(id: range) { await load() }
    }

    private var rangePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ranges, id: \.self) { item in
                    Button { range = item } label: {
                        NanoMono(item, size: 12.5, color: range == item ? t.accent : t.fg3, weight: range == item ? .semibold : .medium)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(range == item ? t.accent.opacity(0.16) : t.card2)
                            .overlay(Capsule().stroke(range == item ? t.accent.opacity(0.5) : t.sep2, lineWidth: 0.5))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func charts(_ h: MetricsHistory) -> some View {
        let cpuPeak = maxValue(h.hasMaxBands && !h.cpuMax.isEmpty ? h.cpuMax : h.cpu)
        let memPeak = maxValue(h.hasMaxBands && !h.memMax.isEmpty ? h.memMax : h.mem)
        return VStack(spacing: 12) {
            if cpuPeak > 90 || memPeak > 90 { anomaly(cpuPeak: cpuPeak, memPeak: memPeak) }
            LazyVGrid(columns: chartColumns, spacing: 12) {
                chartCard(tr("history.cpu"), stat: String(format: "%.0f%%", metrics?.cpuPercent ?? h.cpu.last ?? 0), peak: cpuPeak, unit: "%", yMax: 100,
                          series: [NanoSeries(data: h.cpu, color: t.accent, fill: true, band: h.hasMaxBands ? h.cpuMax : nil)],
                          thresholds: [NanoThreshold(value: 90, color: t.crit, label: "90%")], history: h)
                chartCard(tr("history.memory"), stat: String(format: "%.0f%%", metrics?.memoryPercent ?? h.mem.last ?? 0), peak: memPeak, unit: "%", yMax: 100,
                          series: [NanoSeries(data: h.mem, color: t.fg2, fill: true, band: h.hasMaxBands ? h.memMax : nil)],
                          thresholds: [NanoThreshold(value: 90, color: t.crit, label: "90%")], history: h)
                chartCard(tr("history.network"), stat: "↓\(last(h.netRx)) ↑\(last(h.netTx))", unit: " MB/s", yMax: nil,
                          series: [NanoSeries(data: h.netRx, color: t.accent, fill: true, label: tr("history.rx")), NanoSeries(data: h.netTx, color: t.warn, dashed: true, label: tr("history.tx"))], history: h)
                chartCard(tr("history.diskIo"), stat: "R \(last(h.diskRead)) · W \(last(h.diskWrite))", unit: " MB/s", yMax: nil,
                          series: [NanoSeries(data: h.diskRead, color: t.ok, fill: true, label: tr("history.read")), NanoSeries(data: h.diskWrite, color: t.warn, dashed: true, label: tr("history.write"))], history: h)
                if h.hasGpu {
                    chartCard(tr("history.gpu"), stat: "\(last(h.gpuUsage))%", unit: "%", yMax: 100,
                              series: [NanoSeries(data: h.gpuUsage, color: t.tertiary, fill: true, label: tr("history.utilization")), NanoSeries(data: h.gpuTemp, color: t.crit, dashed: true, label: tr("history.temperature"))].filter { !$0.data.isEmpty }, history: h)
                }
            }
        }
    }

    private func chartCard(_ title: String, stat: String, peak: Double? = nil, unit: String,
                           yMax: Double?, series: [NanoSeries], thresholds: [NanoThreshold] = [], history: MetricsHistory) -> some View {
        NanoCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(t.fg3)
                        NanoMono(stat, size: 16, color: t.fg, weight: .semibold)
                    }
                    Spacer()
                    if let peak { NanoBadge(text: tr("history.peak", ["value": String(format: "%.0f", peak), "unit": unit]), color: peak > 90 ? t.crit : t.fg3) }
                }
                NanoLineChart(series: series, height: 130, yMax: yMax, unit: unit, thresholds: thresholds,
                              xLabels: spec(range).labels, times: history.times)
            }
        }
    }

    private func anomaly(cpuPeak: Double, memPeak: Double) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundColor(t.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("history.anomaly")).font(.system(size: 13, weight: .medium)).foregroundColor(t.fg)
                if cpuPeak > 90 { Text(tr("history.anomalyCpu", ["value": String(format: "%.0f", cpuPeak)])).font(.system(size: 11.5)).foregroundColor(t.fg3) }
                if memPeak > 90 { Text(tr("history.anomalyMem", ["value": String(format: "%.0f", memPeak)])).font(.system(size: 11.5)).foregroundColor(t.fg3) }
            }
            Spacer()
        }.padding(12).background(t.warn.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func hint(_ icon: String, _ title: String, _ sub: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 30)).foregroundColor(t.fg4)
            Text(title).font(.system(size: 15, weight: .medium)).foregroundColor(t.fg2)
            Text(sub).font(.system(size: 12.5)).foregroundColor(t.fg4).multilineTextAlignment(.center)
            if failed { NanoButton(tr("common.retry"), icon: "arrow.clockwise", variant: .text) { Task { await load() } } }
        }.padding(.vertical, 48)
    }

    @MainActor private func load() async {
        loading = true; failed = false
        guard let service = store.serviceForAgent(agent.id) else { loading = false; failed = true; return }
        let s = spec(range)
        history = await service.fetchMetricsHistory(agent.id, window: s.seconds, interval: s.interval)
        failed = history == nil
        loading = false
    }

    private func maxValue(_ values: [Double]) -> Double { values.max() ?? 0 }
    private func last(_ values: [Double]) -> String { values.last.map { String(format: $0 >= 100 ? "%.0f" : "%.1f", $0) } ?? "0" }
}
