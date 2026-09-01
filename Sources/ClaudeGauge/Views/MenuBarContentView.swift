import AppKit
import SwiftUI
import ClaudeGaugeCore

struct MenuBarContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 18) {
                UsageRingView(
                    title: "5 hours",
                    state: store.usage?.fiveHourState() ?? .awaitingCapture,
                    tint: GaugePalette.fiveHour
                )
                UsageRingView(
                    title: "Weekly",
                    state: store.usage?.sevenDayState() ?? .awaitingCapture,
                    tint: GaugePalette.weekly
                )
            }

            dataAgeRow

            if let setupMessage {
                Label(setupMessage, systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }

            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }

            Divider()

            Label(
                "No credentials. Reads a local cache written by your Claude status line.",
                systemImage: "lock.shield"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isRefreshing)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(18)
        .frame(width: 340)
        .onAppear {
            store.start()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(GaugePalette.fiveHour)

            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Gauge")
                    .font(.headline)
                Text("Subscription usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let version = store.usage?.claudeCodeVersion {
                Text("Claude Code \(version)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private var dataAgeRow: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let freshness = store.usage?.freshness(now: context.date)

            HStack(spacing: 6) {
                Circle()
                    .fill(freshnessDotColor(freshness))
                    .frame(width: 7, height: 7)

                Text(dataAgeDescription(freshness: freshness, now: context.date))

                if freshness == .stale {
                    Text("· start Claude Code to refresh")
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.caption)
            .monospacedDigit()
        }
    }

    private func dataAgeDescription(freshness: DataFreshness?, now: Date) -> String {
        if freshness == .stale {
            return UsageFormatting.lastCaptureDescription(store.usage?.capturedAt, now: now)
        }
        return UsageFormatting.lastUpdatedDescription(store.usage?.capturedAt, now: now)
    }

    private func freshnessDotColor(_ freshness: DataFreshness?) -> Color {
        switch freshness {
        case .live: .green
        case .recent: .secondary
        case .stale, nil: .orange
        }
    }

    private var setupMessage: String? {
        guard let status = store.installStatus else { return nil }
        return status.guidanceMessage
    }
}
