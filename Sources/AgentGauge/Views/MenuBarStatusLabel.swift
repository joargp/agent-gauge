import AppKit
import SwiftUI
import GaugeCore

struct MenuBarStatusLabel: View {
    let provider: GaugeProvider
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: renderedRings)
            .renderingMode(.original)
            .frame(width: 18, height: 18)
            .accessibilityLabel(accessibilityLabel)
    }

    private var renderedRings: NSImage {
        let renderer = ImageRenderer(content:
            NestedUsageRings(
                provider: provider,
                fiveHour: store.usage?.fiveHourState() ?? .awaitingCapture,
                weekly: store.usage?.weeklyState() ?? .awaitingCapture
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
            return store.isRefreshing ? "\(provider.name) usage, refreshing" : "\(provider.name) usage"
        }

        func windowDescription(_ state: WindowDisplayState, name: String) -> String {
            if state == .noLimit {
                return "No \(name) limit"
            }
            guard case let .present(window) = state else {
                return "\(name) usage unknown"
            }
            return "\(name) usage \(UsageFormatting.wholePercent(window.remainingPercent)) percent remaining"
        }

        return "\(provider.name) usage. \(windowDescription(usage.fiveHourState(), name: "5-hour")). \(windowDescription(usage.weeklyState(), name: "Weekly"))."
    }
}

private struct NestedUsageRings: View {
    let provider: GaugeProvider
    let fiveHour: WindowDisplayState
    let weekly: WindowDisplayState

    var body: some View {
        ZStack {
            CompactUsageRing(
                state: weekly,
                tint: provider.weeklyTint,
                centerRadius: 7.65
            )
                .frame(width: 15.3, height: 15.3)

            CompactUsageRing(
                state: fiveHour,
                tint: provider.fiveHourTint,
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
