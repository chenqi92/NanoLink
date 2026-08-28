import SwiftUI

// MARK: - Sparkline

/// Tiny sparkline used inside KPI tiles. Ports `NanoSparkline`.
struct NanoSparkline: View {
    let data: [Double]
    let color: Color
    var width: CGFloat = 56
    var height: CGFloat = 18
    var fill: Bool = false

    var body: some View {
        Canvas { ctx, size in
            guard !data.isEmpty else { return }
            let lo = data.min() ?? 0
            let hi = data.max() ?? 1
            let range = (hi - lo) == 0 ? 1 : (hi - lo)
            let step = size.width / CGFloat(max(data.count - 1, 1))
            var path = Path()
            for i in 0..<data.count {
                let x = CGFloat(i) * step
                let y = size.height - CGFloat((data[i] - lo) / range) * (size.height - 2) - 1
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            if fill {
                var area = path
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .color(color.opacity(0.12)))
            }
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Line chart

/// One data series for `NanoLineChart`.
struct NanoSeries {
    let data: [Double]
    let color: Color
    var fill: Bool = false
    var dashed: Bool = false
    var label: String? = nil
    /// Optional per-sample peak values; shaded as a faint envelope band.
    var band: [Double]? = nil
}

struct NanoThreshold {
    let value: Double
    let color: Color
    var label: String? = nil
}

/// Touch-tuned line chart (history graphs). Ports `NanoLineChart` / `MLineChart`.
struct NanoLineChart: View {
    let series: [NanoSeries]
    var height: CGFloat = 140
    var yMax: Double? = nil
    var yMin: Double = 0
    var unit: String = "%"
    var thresholds: [NanoThreshold] = []
    var grid: Bool = true
    var xLabels: [String] = ["-60m", "-30m", "now"]
    var times: [Date] = []
    @Environment(\.nano) private var t

    private static let padL: CGFloat = 30, padR: CGFloat = 6, padT: CGFloat = 6, padB: CGFloat = 18

    /// Derive three tick labels (start / middle / now) from real timestamps.
    static func labelsFromTimes(_ times: [Date]) -> [String] {
        guard times.count >= 2 else { return ["", "", "now"] }
        let first = times.first!
        let last = times.last!
        let mid = times[times.count / 2]
        func rel(_ d: Date) -> String {
            let s = Int(last.timeIntervalSince(d))
            if s <= 30 { return "now" }
            if s < 3600 { return "-\(Int((Double(s) / 60).rounded()))m" }
            if s < 86400 { return "-\(Int((Double(s) / 3600).rounded()))h" }
            return "-\(Int((Double(s) / 86400).rounded()))d"
        }
        return [rel(first), rel(mid), rel(last)]
    }

    var body: some View {
        let labels = times.count >= 2 ? Self.labelsFromTimes(times) : xLabels
        let gridColor = t.sep2
        let axisText = t.fg4
        Canvas { ctx, size in
            let padL = Self.padL, padR = Self.padR, padT = Self.padT, padB = Self.padB
            let allVals = series.flatMap { $0.data }
            let dataMax = allVals.max() ?? 1
            let ymax = yMax ?? max(dataMax * 1.1, 1)
            let ymin = yMin
            let len = series.reduce(0) { max($0, $1.data.count) }
            let innerW = size.width - padL - padR
            let innerH = size.height - padT - padB
            func xFor(_ i: Int) -> CGFloat { padL + CGFloat(i) / CGFloat(max(len - 1, 1)) * innerW }
            func yFor(_ v: Double) -> CGFloat {
                let denom = (ymax - ymin) == 0 ? 1 : (ymax - ymin)
                return padT + (1 - CGFloat((v - ymin) / denom)) * innerH
            }

            func text(_ s: String, at p: CGPoint, color: Color, align: HorizontalAlignment = .leading) {
                let resolved = ctx.resolve(Text(s).font(NanoFont.mono(9)).foregroundColor(color))
                let sz = resolved.measure(in: CGSize(width: 200, height: 20))
                var dx = p.x
                if align == .trailing { dx -= sz.width }
                if align == .center { dx -= sz.width / 2 }
                ctx.draw(resolved, at: CGPoint(x: dx + sz.width / 2, y: p.y))
            }

            // grid + y labels
            if grid {
                for i in 0...3 {
                    let tv = ymin + (ymax - ymin) * Double(i) / 3
                    let y = yFor(tv)
                    var line = Path()
                    line.move(to: CGPoint(x: padL, y: y))
                    line.addLine(to: CGPoint(x: size.width - padR, y: y))
                    if i == 0 || i == 3 {
                        ctx.stroke(line, with: .color(gridColor), lineWidth: 1)
                    } else {
                        ctx.stroke(line, with: .color(gridColor),
                                   style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                    text("\(Int(tv.rounded()))\(unit)", at: CGPoint(x: padL - 4, y: y),
                         color: axisText, align: .trailing)
                }
            }

            // thresholds
            for th in thresholds {
                let y = yFor(th.value)
                var line = Path()
                line.move(to: CGPoint(x: padL, y: y))
                line.addLine(to: CGPoint(x: size.width - padR, y: y))
                ctx.stroke(line, with: .color(th.color.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                if let label = th.label {
                    text(label, at: CGPoint(x: size.width - padR - 2, y: y - 6),
                         color: th.color, align: .trailing)
                }
            }

            // max-envelope bands
            for s in series {
                guard let band = s.band, !band.isEmpty, !s.data.isEmpty else { continue }
                let n = min(band.count, s.data.count)
                if n < 2 { continue }
                var area = Path()
                for i in 0..<n {
                    let x = xFor(i)
                    let y = yFor(max(band[i], s.data[i]))
                    if i == 0 { area.move(to: CGPoint(x: x, y: y)) }
                    else { area.addLine(to: CGPoint(x: x, y: y)) }
                }
                for i in stride(from: n - 1, through: 0, by: -1) {
                    area.addLine(to: CGPoint(x: xFor(i), y: yFor(s.data[i])))
                }
                area.closeSubpath()
                ctx.fill(area, with: .color(s.color.opacity(0.10)))
            }

            // series
            for s in series {
                guard !s.data.isEmpty else { continue }
                var path = Path()
                for i in 0..<s.data.count {
                    let x = xFor(i), y = yFor(s.data[i])
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                if s.fill {
                    var area = path
                    area.addLine(to: CGPoint(x: xFor(s.data.count - 1), y: yFor(ymin)))
                    area.addLine(to: CGPoint(x: xFor(0), y: yFor(ymin)))
                    area.closeSubpath()
                    ctx.fill(area, with: .color(s.color.opacity(0.15)))
                }
                let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round,
                                        dash: s.dashed ? [4, 3] : [])
                ctx.stroke(path, with: .color(s.color), style: style)
            }

            // x labels
            let xl = labels.count >= 3 ? labels : ["", "", "now"]
            for i in 0..<3 {
                let x = padL + CGFloat(i) / 2 * innerW
                let align: HorizontalAlignment = i == 0 ? .leading : (i == 2 ? .trailing : .center)
                text(xl[i], at: CGPoint(x: x, y: size.height - 8), color: axisText, align: align)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Donut

/// Circular gauge (CPU/MEM donuts). Ports `NanoDonut`.
struct NanoDonut: View {
    let value: Double
    var max: Double = 100
    var size: CGFloat = 64
    var thickness: CGFloat = 5
    let label: String
    var sub: String? = nil
    var tone: Color? = nil
    @Environment(\.nano) private var t

    var body: some View {
        let pct = min(Swift.max(value / max, 0), 1)
        let color = tone ?? (pct > 0.9 ? t.crit : (pct > 0.75 ? t.warn : t.fg))
        ZStack {
            Circle()
                .stroke(t.card3, lineWidth: thickness)
                .padding(thickness)
            Circle()
                .trim(from: 0, to: CGFloat(pct))
                .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(thickness)
            VStack(spacing: 0) {
                Text(label)
                    .font(.system(size: size > 70 ? 16 : 13, weight: .semibold))
                    .foregroundColor(t.fg)
                    .monospacedDigit()
                if let sub {
                    Text(sub).font(NanoFont.mono(9)).foregroundColor(t.fg4)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Core matrix

/// Per-core utilization matrix (vertical bars in a grid). Ports `NanoCoreMatrix`.
struct NanoCoreMatrix: View {
    let cores: [Double]
    var cols: Int = 8
    @Environment(\.nano) private var t

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: cols)
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, v in
                let tone: Color = v > 90 ? t.crit : (v > 70 ? t.warn : (v > 30 ? t.fg2 : t.fg4))
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(t.card3)
                        Rectangle()
                            .fill(tone.opacity(0.85))
                            .frame(height: geo.size.height * CGFloat(min(Swift.max(v / 100, 0), 1)))
                    }
                }
                .aspectRatio(1.6, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
        }
    }
}
