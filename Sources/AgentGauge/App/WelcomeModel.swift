import AppKit
import ClaudeProvider
import CodexProvider
import Combine
import Foundation
import GaugeCore

/// What the welcome window says about one agent's setup.
struct AgentSetupStatus: Equatable {
    enum Tone: Equatable {
        case checking
        case ready
        case attention
    }

    enum Action: Equatable {
        /// Install the capture helper and register Claude Code's status line.
        case connect
        /// Copy `codex login` so it can be pasted in Terminal.
        case copyLoginCommand
    }

    let tone: Tone
    let message: String
    let action: Action?

    init(tone: Tone, message: String, action: Action? = nil) {
        self.tone = tone
        self.message = message
        self.action = action
    }

    static let checking = AgentSetupStatus(tone: .checking, message: "Checking…")
    static let claudeConnected = AgentSetupStatus(
        tone: .ready,
        message: "Connected · Restart Claude Code sessions to start capturing"
    )

    static func claude(install: StatuslineInstallStatus, usage: UsageSnapshot?) -> AgentSetupStatus {
        switch install.state {
        case .installed, .integrated:
            guard install.captureBinaryExists else {
                return AgentSetupStatus(
                    tone: .attention,
                    message: "Capture helper missing",
                    action: .connect
                )
            }
            guard install.cacheFileExists else {
                return AgentSetupStatus(
                    tone: .ready,
                    message: "Connected · Waiting for the first capture"
                )
            }
            if let badge = usage?.badge {
                return AgentSetupStatus(tone: .ready, message: "Connected · \(badge)")
            }
            return AgentSetupStatus(tone: .ready, message: "Connected")
        case .missing:
            return AgentSetupStatus(
                tone: .attention,
                message: "Status line not connected",
                action: .connect
            )
        case .foreign, .malformed, .unreadable:
            return AgentSetupStatus(
                tone: .attention,
                message: install.guidanceMessage ?? "Status line can’t be connected automatically"
            )
        }
    }

    static func codex(_ result: Result<UsageSnapshot, any Error>) -> AgentSetupStatus {
        switch result {
        case let .success(usage):
            if let badge = usage.badge {
                return AgentSetupStatus(tone: .ready, message: "Signed in · \(badge)")
            }
            return AgentSetupStatus(tone: .ready, message: "Signed in")
        case let .failure(error as CodexUsageError) where error == .notLoggedIn:
            return AgentSetupStatus(
                tone: .attention,
                message: "Not signed in · Run codex login in Terminal",
                action: .copyLoginCommand
            )
        case let .failure(error as CodexUsageError) where error == .executableNotFound:
            return AgentSetupStatus(tone: .attention, message: "Codex CLI not found")
        case let .failure(error):
            return AgentSetupStatus(
                tone: .attention,
                message: (error as? LocalizedError)?.errorDescription ?? "Codex usage couldn’t be read"
            )
        }
    }

    /// Codex can't work without its CLI, so its switch starts off.
    var codexNotInstalled: Bool {
        self == AgentSetupStatus.codex(.failure(CodexUsageError.executableNotFound))
    }
}

/// Detection and actions behind the welcome window.
@MainActor
final class WelcomeModel: ObservableObject {
    enum Page {
        case agents
        case menuBar
    }

    static let loginCommand = "codex login"

    @Published var page: Page = .agents
    @Published private(set) var claudeStatus: AgentSetupStatus = .checking
    @Published private(set) var codexStatus: AgentSetupStatus = .checking
    @Published private(set) var isConnectingClaude = false
    @Published private(set) var copiedLoginCommand = false

    let appModel: AppModel
    private let locations: CacheLocations

    init(appModel: AppModel, locations: CacheLocations = CacheLocations()) {
        self.appModel = appModel
        self.locations = locations
    }

    func detect() async {
        claudeStatus = .checking
        codexStatus = .checking

        async let claude = Self.detectClaude(locations: locations)
        async let codex = Self.detectCodex()
        claudeStatus = await claude
        codexStatus = await codex

        if codexStatus.codexNotInstalled, !appModel.hasCompletedWelcome {
            appModel.setVisible(false, for: .codex)
        }
    }

    func connectClaude() async {
        guard !isConnectingClaude else { return }
        isConnectingClaude = true
        defer { isConnectingClaude = false }

        guard let helper = Self.bundledCaptureHelper else {
            claudeStatus = AgentSetupStatus(
                tone: .attention,
                message: "This build doesn’t include the capture helper. Run ./script/install.sh."
            )
            return
        }

        let locations = locations
        let outcome = await Task.detached {
            Result { try StatuslineInstallation.install(sourceExecutable: helper, locations: locations) }
        }.value

        switch outcome {
        case .success:
            claudeStatus = .claudeConnected
            await appModel.store(for: .claude).refresh()
        case let .failure(error):
            claudeStatus = AgentSetupStatus(
                tone: .attention,
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    func copyLoginCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.loginCommand, forType: .string)
        copiedLoginCommand = true
    }

    /// The capture helper the build script places in the app bundle.
    static var bundledCaptureHelper: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/claude-gauge-capture", isDirectory: false)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private nonisolated static func detectClaude(locations: CacheLocations) async -> AgentSetupStatus {
        let provider = ClaudeUsageProvider(locations: locations)
        let install = StatuslineInstallation.inspect(locations: locations)
        let usage = try? await provider.readUsage()
        return AgentSetupStatus.claude(install: install, usage: usage)
    }

    private nonisolated static func detectCodex() async -> AgentSetupStatus {
        do {
            return AgentSetupStatus.codex(.success(try await CodexAppServerClient().readUsage()))
        } catch {
            return AgentSetupStatus.codex(.failure(error))
        }
    }
}
