import SwiftUI

@main
struct AgentGaugeApp: App {
    @StateObject private var model: AppModel

    init() {
        LaunchAtLogin.handleCommandLine()
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        // SwiftUI scenes can't be generated in a loop, so each provider gets
        // its own menu bar item here.
        MenuBarExtra(isInserted: visibility(.claude)) {
            MenuBarContentView(provider: .claude, store: model.store(for: .claude), model: model)
        } label: {
            MenuBarStatusLabel(provider: .claude, store: model.store(for: .claude))
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: visibility(.codex)) {
            MenuBarContentView(provider: .codex, store: model.store(for: .codex), model: model)
        } label: {
            MenuBarStatusLabel(provider: .codex, store: model.store(for: .codex))
        }
        .menuBarExtraStyle(.window)
    }

    private func visibility(_ provider: GaugeProvider) -> Binding<Bool> {
        Binding(
            get: { model.isVisible(provider) },
            set: { model.setVisible($0, for: provider) }
        )
    }
}
