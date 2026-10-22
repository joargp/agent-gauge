import AppKit
import SwiftUI
import GaugeCore

struct MenuBarContentView: View {
    let provider: GaugeProvider
    @ObservedObject var store: UsageStore
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 18) {
                UsageRingView(
                    provider: provider,
                    title: "5 hours",
                    state: store.usage?.fiveHourState() ?? .awaitingCapture,
                    tint: provider.fiveHourTint
                )
                UsageRingView(
                    provider: provider,
                    title: "Weekly",
                    state: store.usage?.weeklyState() ?? .awaitingCapture,
                    tint: provider.weeklyTint
                )
            }

            dataAgeRow

            if let setupMessage = store.setupMessage {
                Label(setupMessage, systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }

            if let errorMessage = store.errorMessage ?? model.launchAtLoginError {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }

            Divider()

            Label(provider.privacyNote, systemImage: "lock.shield")
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

                settingsMenu

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(18)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: provider.symbolName)
                .font(.title2)
                .foregroundStyle(provider.accentTint)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.name)
                    .font(.headline)
                Text("Subscription usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let badge = store.usage?.badge {
                Text(badge)
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
                    Text("· \(provider.staleHint)")
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
        if freshness == .stale, provider.describesAgeAsCapture {
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

    private var settingsMenu: some View {
        Menu {
            ForEach(GaugeProvider.allCases) { item in
                Toggle("Show \(item.name)", isOn: Binding(
                    get: { model.isVisible(item) },
                    set: { model.setVisible($0, for: item) }
                ))
                .disabled(!model.canHide(item))
            }

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchesAtLogin },
                set: { model.setLaunchesAtLogin($0) }
            ))
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
    }
}
