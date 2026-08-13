import SwiftUI

/// KPI summary tile used on the dashboard (label, big value, sub, optional spark).
/// Ports `NanoKpiTile`.
struct NanoKpiTile<Value: View>: View {
    let label: String
    let value: Value
    let sub: String
    let icon: String
    /// `warn` | `crit` | nil
    var tone: String? = nil
    var spark: [Double]? = nil
    var background: Color? = nil
    @Environment(\.nano) private var t

    init(label: String, sub: String, icon: String, tone: String? = nil,
         spark: [Double]? = nil, background: Color? = nil,
         @ViewBuilder value: () -> Value) {
        self.label = label
        self.sub = sub
        self.icon = icon
        self.tone = tone
        self.spark = spark
        self.background = background
        self.value = value()
    }

    var body: some View {
        let toneColor = tone == "crit" ? t.crit : (tone == "warn" ? t.warn : t.accent)
        let valueColor = tone == "crit" ? t.crit : (tone == "warn" ? t.warn : t.fg)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 14)).foregroundColor(t.fg3)
                Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(t.fg3)
            }
            Spacer().frame(height: 4)
            value
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.3)
                .foregroundColor(valueColor)
                .monospacedDigit()
            Spacer().frame(height: 2)
            HStack(alignment: .bottom) {
                Text(sub)
                    .font(NanoFont.mono(10.5))
                    .foregroundColor(t.fg4)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let spark {
                    NanoSparkline(data: spark, color: toneColor)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background ?? t.card)
        .clipShape(RoundedRectangle(cornerRadius: t.cardRadius, style: .continuous))
    }
}

/// Row: leading icon + short label + meter + right-aligned value/sub.
/// Ports `NanoMetricRow`.
struct NanoMetricRow: View {
    let icon: String
    let label: String
    let value: String
    var sub: String? = nil
    var pct: Double? = nil
    var tone: String? = nil
    @Environment(\.nano) private var t

    var body: some View {
        let toneColor = tone == "crit" ? t.crit : (tone == "warn" ? t.warn : t.fg)
        HStack(spacing: 0) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(t.fg4)
                .frame(width: 16, alignment: .leading)
            Spacer().frame(width: 10)
            Text(label).font(NanoFont.mono(11)).foregroundColor(t.fg3)
                .frame(width: 28, alignment: .leading)
            Spacer().frame(width: 10)
            if let pct {
                NanoMeter(value: pct / 100, color: tone == nil ? nil : toneColor)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }
            Spacer().frame(width: 10)
            VStack(alignment: .trailing, spacing: 0) {
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(toneColor)
                    .monospacedDigit()
                if let sub {
                    Text(sub).font(NanoFont.mono(10)).foregroundColor(t.fg4)
                }
            }
            .frame(minWidth: 60, alignment: .trailing)
        }
    }
}
