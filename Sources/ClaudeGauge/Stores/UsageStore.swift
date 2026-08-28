import Combine
import Foundation
import ClaudeGaugeCore

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var usage: ClaudeUsageSnapshot?
    @Published private(set) var installStatus: StatuslineInstallStatus?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let reader: any UsageReading
    private let refreshInterval: TimeInterval
    private var refreshLoop: Task<Void, Never>?

    init(
        reader: any UsageReading = LocalUsageReader(),
        refreshInterval: TimeInterval = 10
    ) {
        self.reader = reader
        self.refreshInterval = refreshInterval
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

        installStatus = await reader.readInstallStatus()

        do {
            usage = try await reader.readUsage()
            errorMessage = nil
        } catch let error as ClaudeUsageError where error == .noCacheYet {
            // No capture yet is a waiting state, not an error.
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Claude usage could not be read."
        }
    }

    deinit {
        refreshLoop?.cancel()
    }
}
