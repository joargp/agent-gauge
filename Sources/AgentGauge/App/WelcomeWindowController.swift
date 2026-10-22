import AppKit
import SwiftUI

/// Owns the welcome window. Agent Gauge has no Dock icon or main window, so
/// this is the only window it shows.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowController()

    /// Opens the welcome window on launch even after it has been completed.
    static let showArgument = "--show-welcome"

    private var window: NSWindow?
    private var model: AppModel?

    func showIfNeeded(model: AppModel, arguments: [String] = CommandLine.arguments) {
        guard !model.hasCompletedWelcome || arguments.contains(Self.showArgument) else { return }
        show(model: model)
    }

    func show(model: AppModel) {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let welcome = WelcomeModel(appModel: model)
        let hosting = NSHostingController(rootView: WelcomeView(welcome: welcome) { [weak self] in
            self?.window?.close()
        })
        hosting.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Agent Gauge"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.model = model
        Task { await welcome.detect() }
    }

    func windowWillClose(_ notification: Notification) {
        // Shown once is enough: closing early also counts, so it never nags.
        model?.completeWelcome()
        window = nil
        model = nil
    }
}
