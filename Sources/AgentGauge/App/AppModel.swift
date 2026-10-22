import Combine
import Foundation

/// Which providers are shown in the menu bar, and their stores. A hidden
/// provider's store is stopped so it does no background work.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var visibleProviders: Set<GaugeProvider>
    @Published private(set) var launchAtLoginError: String?

    let stores: [GaugeProvider: UsageStore]
    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        stores: [GaugeProvider: UsageStore]? = nil
    ) {
        self.defaults = defaults
        self.stores = stores ?? Dictionary(uniqueKeysWithValues: GaugeProvider.allCases.map {
            ($0, UsageStore(provider: $0.makeUsageProvider(), refreshInterval: $0.refreshInterval))
        })

        var visible = Set(GaugeProvider.allCases.filter {
            defaults.object(forKey: Self.visibilityKey($0)) as? Bool ?? true
        })
        // Never start with no menu bar item, or the app can't be reached.
        if visible.isEmpty {
            visible = Set(GaugeProvider.allCases)
        }
        visibleProviders = visible

        for provider in visible {
            self.stores[provider]?.start()
        }
    }

    func store(for provider: GaugeProvider) -> UsageStore {
        stores[provider]!
    }

    func isVisible(_ provider: GaugeProvider) -> Bool {
        visibleProviders.contains(provider)
    }

    /// The last visible provider can't be hidden.
    func canHide(_ provider: GaugeProvider) -> Bool {
        visibleProviders != [provider]
    }

    func setVisible(_ visible: Bool, for provider: GaugeProvider) {
        guard visible != isVisible(provider) else { return }
        guard visible || canHide(provider) else { return }

        if visible {
            visibleProviders.insert(provider)
            stores[provider]?.start()
        } else {
            visibleProviders.remove(provider)
            stores[provider]?.stop()
        }
        defaults.set(visible, forKey: Self.visibilityKey(provider))
    }

    var launchesAtLogin: Bool {
        LaunchAtLogin.isEnabled
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        objectWillChange.send()
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Launch at login couldn’t be changed: \(error.localizedDescription)"
        }
    }

    private static func visibilityKey(_ provider: GaugeProvider) -> String {
        "show.\(provider.rawValue)"
    }
}
