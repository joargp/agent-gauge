import SwiftUI

@main
struct AgentGaugeApp: App {
    @StateObject private var model: AppModel

    init() {
        LaunchAtLogin.handleCommandLine()
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        // Wait for the app to finish launching before opening a window.
        DispatchQueue.main.async {
            WelcomeWindowController.shared.showIfNeeded(model: model)
        }
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

    /// Only the app's own switches change visibility. AppKit also writes to
    /// this binding when an item leaves the menu bar, which menu bar managers
    /// such as Ice trigger while rearranging items, so those writes are
    /// ignored.
    private func visibility(_ provider: GaugeProvider) -> Binding<Bool> {
        Binding(
            get: { model.isVisible(provider) },
            set: { _ in }
        )
    }
}
