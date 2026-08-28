import AppKit
import SwiftUI

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

    private var accessibilityLabel: String {
        guard let usage = store.usage,
              let fiveHour = usage.fiveHourWindow,
              let weekly = usage.weeklyWindow
        else {
            return store.isRefreshing ? "Codex Gauge, refreshing" : "Codex Gauge"
        }
        return "Codex Gauge. 5-hour usage \(UsageFormatting.wholePercent(fiveHour.remainingPercent)) percent remaining. Weekly usage \(UsageFormatting.wholePercent(weekly.remainingPercent)) percent remaining."
    }

    private var renderedRings: NSImage {
        let renderer = ImageRenderer(content:
            NestedUsageRings(
                fiveHour: store.usage?.fiveHourWindow,
                weekly: store.usage?.weeklyWindow
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
}

private struct NestedUsageRings: View {
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?

    var body: some View {
        ZStack {
            CompactUsageRing(
                window: weekly,
                tint: GaugePalette.weekly,
                centerRadius: 7.65
            )
                .frame(width: 15.3, height: 15.3)

            CompactUsageRing(
                window: fiveHour,
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

    let window: UsageWindow?
    let tint: Color
    let centerRadius: Double

    private var rawProgress: Double {
        window?.remainingFraction ?? 0
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
        GaugePalette.ringColor(
            remainingPercent: window?.remainingPercent,
            healthy: tint
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, style: StrokeStyle(lineWidth: Self.lineWidth))

            if window != nil {
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
