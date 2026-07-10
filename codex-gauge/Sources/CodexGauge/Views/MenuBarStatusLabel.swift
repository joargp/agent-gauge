import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.medium")

            if let usage = store.usage,
               let fiveHour = usage.fiveHourWindow,
               let weekly = usage.weeklyWindow
            {
                Text("5h \(UsageFormatting.wholePercent(fiveHour.remainingPercent))% · W \(UsageFormatting.wholePercent(weekly.remainingPercent))%")
                    .monospacedDigit()
            }
        }
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
}
