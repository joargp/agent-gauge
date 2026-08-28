import AppKit
import SwiftUI
import ClaudeGaugeCore

struct MenuBarStatusLabel: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: renderedRings)
            .renderingMode(.original)
            .frame(width: 18, height: 18)
            .accessibilityLabel(accessibilityLabel)
            .task {
                store.start()
            }
    }

    private var renderedRings: NSImage {
        let renderer = ImageRenderer(content:
            NestedUsageRings(
                fiveHour: store.usage?.fiveHourState() ?? .awaitingCapture,
                weekly: store.usage?.sevenDayState() ?? .awaitingCapture
            )
            .environment(\.colorScheme, colorScheme)
        )
        renderer.proposedSize = ProposedViewSize(width: 18, height: 18)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        let image: NSImage
        if let cgImage = renderer.cgImage {
            image = NSImage(cgImage: cgImage, size: NSSize(width: 18, height: 18))
        } else {
            image = NSImage(size: NSSize(width: 18, height: 18))
        }
        image.isTemplate = false
        return image
    }

    private var accessibilityLabel: String {
        guard let usage = store.usage else {
            return store.isRefreshing ? "Claude Gauge, refreshing" : "Claude Gauge"
        }

        func windowDescription(_ state: WindowDisplayState, name: String) -> String {
            guard case let .present(window) = state else {
                return "\(name) usage unknown"
            }
            return "\(name) usage \(UsageFormatting.wholePercent(window.remainingPercent)) percent remaining"
        }

        return "Claude Gauge. \(windowDescription(usage.fiveHourState(), name: "5-hour")). \(windowDescription(usage.sevenDayState(), name: "Weekly"))."
    }
}

private struct NestedUsageRings: View {
    let fiveHour: WindowDisplayState
    let weekly: WindowDisplayState

    var body: some View {
        ZStack {
            CompactUsageRing(
                state: weekly,
                tint: GaugePalette.weekly,
                centerRadius: 7.65
            )
                .frame(width: 15.3, height: 15.3)

            CompactUsageRing(
                state: fiveHour,
                tint: GaugePalette.fiveHour,
                centerRadius: 4.68
            )
                .frame(width: 9.36, height: 9.36)
        }
        .frame(width: 18, height: 18)
    }
}

private struct CompactUsageRing: View {
    private static let lineWidth = 2.0

    let state: WindowDisplayState
    let tint: Color
    let centerRadius: Double

    private var rawProgress: Double {
        if case let .present(window) = state {
            return window.remainingFraction
        }
        return 0
    }

    private var progress: Double {
        RingGeometry.trimProgress(
            for: rawProgress,
            centerRadius: centerRadius,
            lineWidth: Self.lineWidth
        )
    }

    private var lineCap: CGLineCap {
        RingGeometry.usesRoundedCaps(
            for: rawProgress,
            centerRadius: centerRadius,
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
        ZStack {
            Circle()
                .stroke(.tertiary, style: StrokeStyle(lineWidth: Self.lineWidth))

            if case .present = state {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: lineCap)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.45), value: progress)
            }
        }
    }
}
