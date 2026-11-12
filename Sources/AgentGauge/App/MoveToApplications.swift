import AppKit
import os

/// Offers to move Agent Gauge into Applications when it was opened from
/// somewhere else, such as Downloads or the disk image. Sparkle can't update
/// an app outside Applications: one opened straight from Downloads even runs
/// from a read-only copy macOS makes ("App Translocation").
@MainActor
enum MoveToApplications {
    static let suppressKey = "moveToApplications.suppressed"
    private static let logger = Logger(subsystem: "com.joar.agentgauge", category: "MoveToApplications")

    /// True when the bundle is outside both Applications folders.
    nonisolated static func needsMove(bundlePath: String, homeDirectory: String) -> Bool {
        let path = (bundlePath as NSString).standardizingPath
        let folders = ["/Applications/", (homeDirectory as NSString).appendingPathComponent("Applications") + "/"]
        return !folders.contains { path.hasPrefix($0) }
    }

    /// True when the copy already in Applications should be opened instead of
    /// replaced: it is the same version or newer, for example because it has
    /// updated itself since this copy was downloaded.
    nonisolated static func keepsInstalledCopy(installedBuild: String?, runningBuild: String?) -> Bool {
        guard let installed = installedBuild.flatMap(Int.init) else { return false }
        guard let running = runningBuild.flatMap(Int.init) else { return true }
        return installed >= running
    }

    /// /Applications when it can be written to, otherwise ~/Applications.
    nonisolated static func destinationFolder(
        homeDirectory: String,
        canWriteSystemApplications: Bool
    ) -> URL {
        canWriteSystemApplications
            ? URL(fileURLWithPath: "/Applications", isDirectory: true)
            : URL(fileURLWithPath: homeDirectory, isDirectory: true).appendingPathComponent("Applications", isDirectory: true)
    }

    /// Returns true when the app is quitting to relaunch from Applications.
    @discardableResult
    static func offerIfNeeded(updatesEnabled: Bool, defaults: UserDefaults = .standard) -> Bool {
        let bundle = Bundle.main.bundleURL
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard updatesEnabled,
              !defaults.bool(forKey: suppressKey),
              needsMove(bundlePath: bundle.path, homeDirectory: home)
        else { return false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Agent Gauge to Applications?"
        alert.informativeText = "Agent Gauge can only update itself from the Applications folder. It will open again from there."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask again"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            defaults.set(true, forKey: suppressKey)
        }
        guard response == .alertFirstButtonReturn else { return false }

        do {
            let destination = try move(bundle, home: home)
            relaunch(destination)
            return true
        } catch {
            logger.error("Couldn’t move to Applications: \(error.localizedDescription, privacy: .public)")
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "Agent Gauge couldn’t be moved"
            failure.informativeText = "\(error.localizedDescription)\n\nDrag Agent Gauge into your Applications folder in Finder instead."
            failure.runModal()
            return false
        }
    }

    private static func move(_ bundle: URL, home: String) throws -> URL {
        let fileManager = FileManager.default
        let folder = destinationFolder(
            homeDirectory: home,
            canWriteSystemApplications: fileManager.isWritableFile(atPath: "/Applications")
        )
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(bundle.lastPathComponent, isDirectory: true)

        if fileManager.fileExists(atPath: destination.path) {
            let installed = Bundle(url: destination)?.infoDictionary?["CFBundleVersion"] as? String
            let running = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            if keepsInstalledCopy(installedBuild: installed, runningBuild: running) {
                return destination
            }
            // An older copy goes to the Trash, so it can be recovered.
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }

        // ditto keeps the framework symlinks, permissions and signature intact.
        try run("/usr/bin/ditto", [bundle.path, destination.path])
        // The person chose to open this notarized app already; without this,
        // the moved copy would ask again on its first launch.
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])

        // The original stays where it is. Removing it from Downloads would make
        // macOS ask for access to the Downloads folder. If it is opened again
        // later, the copy in Applications is simply opened instead.
        return destination
    }

    /// Opens the moved app once this process has quit.
    private static func relaunch(_ destination: URL) {
        let script = "while /bin/kill -0 \(getpid()) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$1\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", destination.path]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            logger.error("Couldn’t relaunch: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "MoveToApplications", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "\((tool as NSString).lastPathComponent) failed with status \(process.terminationStatus)."
            ])
        }
    }
}
