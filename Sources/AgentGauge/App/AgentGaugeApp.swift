import SwiftUI

@main
struct AgentGaugeApp: App {
    @StateObject private var model: AppModel
    @StateObject private var updates = UpdateModel()

    init() {
        LaunchAtLogin.handleCommandLine()
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        CaptureHelperRefresh.refreshInBackground()
        // Wait for the app to finish launching before opening a window.
        DispatchQueue.main.async {
            WelcomeWindowController.shared.showIfNeeded(model: model)
        }
    }

    var body: some Scene {
        // SwiftUI scenes can't be generated in a loop, so each provider gets
        // its own menu bar item here.
        MenuBarExtra(isInserted: visibility(.claude)) {
            MenuBarContentView(provider: .claude, store: model.store(for: .claude), model: model, updates: updates)
        } label: {
            MenuBarStatusLabel(
                provider: .claude,
                store: model.store(for: .claude),
                showsUpdateDot: showsUpdateDot(on: .claude)
            )
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: visibility(.codex)) {
            MenuBarContentView(provider: .codex, store: model.store(for: .codex), model: model, updates: updates)
        } label: {
            MenuBarStatusLabel(
                provider: .codex,
                store: model.store(for: .codex),
                showsUpdateDot: showsUpdateDot(on: .codex)
            )
        }
        .menuBarExtraStyle(.window)
    }

    /// One dot, on the first visible icon, while an update waits for the person.
    private func showsUpdateDot(on provider: GaugeProvider) -> Bool {
        updates.state.wantsAttention
            && GaugeProvider.allCases.first(where: model.isVisible) == provider
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
