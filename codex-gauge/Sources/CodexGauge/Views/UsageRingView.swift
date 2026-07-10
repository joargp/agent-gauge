import SwiftUI

struct UsageRingView: View {
    let title: String
    let window: UsageWindow?
    let tint: Color

    private var progress: Double {
        window?.remainingFraction ?? 0
    }

    private var ringColor: Color {
        guard let remaining = window?.remainingPercent else { return .secondary }
        if remaining <= 10 { return .red }
        if remaining <= 25 { return .orange }
        return tint
    }

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(.tertiary, style: StrokeStyle(lineWidth: 10))

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.45), value: progress)

                VStack(spacing: -1) {
                    if let window {
                        Text("\(UsageFormatting.wholePercent(window.remainingPercent))%")
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                    }
                    Text("left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)

            Text(title)
                .font(.subheadline.weight(.semibold))

            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(UsageFormatting.resetDescription(
                    resetsAt: window?.resetsAt,
                    now: context.date
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let window else { return "Usage unavailable" }
        return "\(UsageFormatting.wholePercent(window.remainingPercent)) percent remaining. \(UsageFormatting.resetDescription(resetsAt: window.resetsAt))"
    }
}
