import GaugeCore
import SwiftUI

/// A model's own weekly limit, shown under the rings.
struct SubLimitRowView: View {
    let subLimit: SubLimit
    let runsOutFirst: Bool
    let tint: Color
    let now: Date

    private var remaining: Double { subLimit.window.remainingPercent }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(subLimit.name)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(UsageFormatting.wholePercent(remaining))% left")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(GaugePalette.ringColor(remainingPercent: remaining, healthy: tint))
                        .frame(width: proxy.size.width * subLimit.window.remainingFraction)
                }
            }
            .frame(height: 6)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if runsOutFirst {
                Text("\(subLimit.name) runs out before your weekly limit. Other models keep working.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    static func caption(for window: UsageWindow, now: Date) -> String {
        let base = "Its own weekly limit"
        guard window.resetsAt != nil else { return base }
        let reset = UsageFormatting.resetDescription(resetsAt: window.resetsAt, now: now)
        return "\(base) · \(reset.prefix(1).lowercased())\(reset.dropFirst())"
    }

    private var caption: String {
        Self.caption(for: subLimit.window, now: now)
    }
}
