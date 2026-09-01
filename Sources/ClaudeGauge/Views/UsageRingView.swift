import SwiftUI
import ClaudeGaugeCore

struct UsageRingView: View {
    private static let centerRadius = 52.0
    private static let lineWidth = 10.0

    let title: String
    let state: WindowDisplayState
    let tint: Color

    private var rawProgress: Double {
        if case let .present(window) = state {
            return window.remainingFraction
        }
        return 0
    }

    private var progress: Double {
        RingGeometry.trimProgress(
            for: rawProgress,
            centerRadius: Self.centerRadius,
            lineWidth: Self.lineWidth
        )
    }

    private var lineCap: CGLineCap {
        RingGeometry.usesRoundedCaps(
            for: rawProgress,
            centerRadius: Self.centerRadius,
            lineWidth: Self.lineWidth
        ) ? .round : .butt
    }

    private var ringColor: Color {
        let remainingPercent: Double?
        if case let .present(window) = state {
            remainingPercent = window.remainingPercent
        } else {
            remainingPercent = nil
        }
        return GaugePalette.ringColor(
            remainingPercent: remainingPercent,
            healthy: tint
        )
    }

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(.tertiary, style: StrokeStyle(lineWidth: Self.lineWidth))

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: lineCap)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.45), value: progress)

                VStack(spacing: -1) {
                    if case let .present(window) = state {
                        Text("\(UsageFormatting.wholePercent(window.remainingPercent))%")
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .monospacedDigit()

                        Text("left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 104, height: 104)

            Text(title)
                .font(.subheadline.weight(.semibold))

            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(spacing: 2) {
                    Text(captionText(now: context.date))
                        .foregroundStyle(.secondary)

                    if let detail = captionDetail(now: context.date) {
                        Text(detail)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private func captionText(now: Date) -> String {
        switch state {
        case let .present(window):
            UsageFormatting.resetDescription(resetsAt: window.resetsAt, now: now)
        case .rolledOver:
            "No recent data"
        case .awaitingCapture:
            "Awaiting first capture"
        }
    }

    private func captionDetail(now: Date) -> String? {
        switch state {
        case let .present(window):
            UsageFormatting.resetDateDescription(resetsAt: window.resetsAt, now: now)
        case .rolledOver, .awaitingCapture:
            "Start Claude Code to refresh"
        }
    }

    private var accessibilityValue: String {
        switch state {
        case let .present(window):
            let relativeReset = UsageFormatting.resetDescription(resetsAt: window.resetsAt)
            let resetDate = UsageFormatting.resetDateDescription(resetsAt: window.resetsAt)
                .map { ". \($0)" } ?? ""
            return "\(UsageFormatting.wholePercent(window.remainingPercent)) percent remaining. \(relativeReset)\(resetDate)"
        case .rolledOver:
            return "No recent data. Start Claude Code to refresh."
        case .awaitingCapture:
            return "Awaiting first capture. Start Claude Code to refresh."
        }
    }
}
