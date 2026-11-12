import ClaudeProvider
import Foundation
import os

/// Claude Code runs a copy of the capture helper that lives outside the app,
/// so replacing the app (by an update or by hand) leaves that copy behind.
/// On launch, an installed copy is brought up to date with the one in the
/// bundle. Settings are never touched, and nothing is installed for people
/// who haven't connected Claude Code.
enum CaptureHelperRefresh {
    private static let logger = Logger(subsystem: "com.joar.agentgauge", category: "CaptureHelperRefresh")

    @MainActor
    static func refreshInBackground(locations: CacheLocations = CacheLocations()) {
        guard let bundled = WelcomeModel.bundledCaptureHelper else { return }
        Task.detached(priority: .utility) {
            refresh(bundled: bundled, locations: locations)
        }
    }

    /// Returns true when an installed copy was checked; false when there is none.
    @discardableResult
    static func refresh(bundled: URL, locations: CacheLocations) -> Bool {
        guard FileManager.default.fileExists(atPath: locations.captureExecutable.path) else {
            return false
        }
        do {
            // Rewrites only when the bytes differ.
            try StatuslineInstallation.installHelper(sourceExecutable: bundled, locations: locations)
        } catch {
            logger.error("Couldn’t refresh the Claude capture helper: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }
}
