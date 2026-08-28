import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 18) {
                UsageRingView(
                    title: "5 hours",
                    window: store.usage?.fiveHourWindow,
                    tint: GaugePalette.fiveHour
                )
                UsageRingView(
                    title: "Weekly",
                    window: store.usage?.weeklyWindow,
                    tint: GaugePalette.weekly
                )
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

            HStack {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(UsageFormatting.lastUpdatedDescription(
                        store.usage?.fetchedAt,
                        now: context.date
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Divider()

            Label("Uses your local Codex login. Credentials stay with Codex.", systemImage: "lock.shield")
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
        .frame(width: 330)
        .onAppear {
            store.start()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.medium")
                .font(.title2)
                .foregroundStyle(GaugePalette.weekly)

            VStack(alignment: .leading, spacing: 1) {
                Text("Codex Gauge")
                    .font(.headline)
                Text("Subscription usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let planType = store.usage?.planType {
                Text(UsageFormatting.planDisplayName(planType))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}
