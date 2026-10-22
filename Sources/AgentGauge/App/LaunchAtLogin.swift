import Foundation
import ServiceManagement

/// Registers the app bundle itself as a login item.
enum LaunchAtLogin {
    static let enableArgument = "--enable-launch-at-login"
    static let disableArgument = "--disable-launch-at-login"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Lets install and uninstall scripts change the login item without
    /// showing the menu bar UI. Returns normally when no flag was passed.
    static func handleCommandLine(_ arguments: [String] = CommandLine.arguments) {
        let enabled: Bool
        if arguments.contains(enableArgument) {
            enabled = true
        } else if arguments.contains(disableArgument) {
            enabled = false
        } else {
            return
        }

        do {
            if enabled != isEnabled {
                try setEnabled(enabled)
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Could not change launch at login: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
