import Foundation

/// A source of subscription usage for one coding agent.
public protocol UsageProvider: Sendable {
    func readUsage() async throws -> UsageSnapshot

    /// What the user still needs to do before usage can be read, or nil when
    /// the provider is ready.
    func setupGuidance() async -> String?
}

/// A provider error that can describe a setup or waiting state rather than a
/// failure. The app shows those as setup guidance instead of an error.
public protocol UsageError: LocalizedError {
    var needsSetup: Bool { get }
}
