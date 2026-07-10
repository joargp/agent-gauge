import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var usage: CodexUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let client: any CodexUsageFetching
    private let refreshInterval: TimeInterval
    private var refreshLoop: Task<Void, Never>?

    init(
        client: any CodexUsageFetching = CodexAppServerClient(),
        refreshInterval: TimeInterval = 60
    ) {
        self.client = client
        self.refreshInterval = refreshInterval
    }

    func start() {
        guard refreshLoop == nil else { return }
        refreshLoop = Task { [weak self] in
            guard let self else { return }
            await refresh()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(refreshInterval))
                } catch {
                    return
                }
                await refresh()
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

        do {
            usage = try await client.fetchUsage()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Codex usage could not be refreshed."
        }
    }

    deinit {
        refreshLoop?.cancel()
    }
}
