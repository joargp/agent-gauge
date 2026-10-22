import Combine
import Foundation
import GaugeCore

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var usage: UsageSnapshot?
    @Published private(set) var setupMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let provider: any UsageProvider
    private let refreshInterval: TimeInterval
    private var refreshLoop: Task<Void, Never>?

    init(provider: any UsageProvider, refreshInterval: TimeInterval) {
        self.provider = provider
        self.refreshInterval = refreshInterval
    }

    var isRunning: Bool {
        refreshLoop != nil
    }

    func start() {
        guard refreshLoop == nil else { return }
        let refreshInterval = refreshInterval
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                if let self {
                    await self.refresh()
                } else {
                    return
                }
                do {
                    try await Task.sleep(for: .seconds(refreshInterval))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        refreshLoop?.cancel()
        refreshLoop = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var setupMessage = await provider.setupGuidance()

        do {
            usage = try await provider.readUsage()
            errorMessage = nil
        } catch let error as any UsageError where error.needsSetup {
            // A setup or waiting state is guidance, not an error.
            setupMessage = setupMessage ?? error.errorDescription
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Usage could not be read."
        }

        self.setupMessage = setupMessage
    }

    deinit {
        refreshLoop?.cancel()
    }
}
