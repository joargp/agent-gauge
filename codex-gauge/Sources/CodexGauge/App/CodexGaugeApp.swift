import SwiftUI

@main
struct CodexGaugeApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            MenuBarStatusLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
