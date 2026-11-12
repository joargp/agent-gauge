import AppKit
import Combine
import Foundation
import Sparkle

/// Built-in updates through Sparkle, shown in the popovers instead of
/// Sparkle's own windows. Builds without a feed URL and public key (debug and
/// ad hoc builds) have no updater, and every update control stays hidden.
@MainActor
final class UpdateModel: ObservableObject {
    @Published fileprivate(set) var state: UpdateState = .idle {
        didSet { scheduleUpToDateFade() }
    }
    @Published private(set) var canCheckForUpdates = false

    let currentVersion: String
    let isEnabled: Bool

    private var updater: SPUUpdater?
    private var driver: UpdateDriver?
    private var fadeTask: Task<Void, Never>?

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        currentVersion = info["CFBundleShortVersionString"] as? String ?? "dev"
        isEnabled = Self.isConfigured(info)
        guard isEnabled else { return }

        let driver = UpdateDriver()
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: driver)
        driver.model = self
        self.driver = driver
        self.updater = updater

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)

        do {
            try updater.start()
        } catch {
            state = .error(title: "Updates aren’t working", message: error.localizedDescription, retry: {})
        }
    }

    /// Sparkle needs both a feed and the key that release downloads are signed with.
    nonisolated static func isConfigured(_ info: [String: Any]) -> Bool {
        let nonEmpty = { (key: String) in !((info[key] as? String) ?? "").isEmpty }
        return nonEmpty("SUFeedURL") && nonEmpty("SUPublicEDKey")
    }

    // MARK: Settings

    var mode: UpdateMode {
        guard let updater else { return .off }
        return UpdateMode(
            checksAutomatically: updater.automaticallyChecksForUpdates,
            downloadsAutomatically: updater.automaticallyDownloadsUpdates
        )
    }

    func setMode(_ mode: UpdateMode) {
        guard let updater else { return }
        objectWillChange.send()
        updater.automaticallyChecksForUpdates = mode.checksAutomatically
        updater.automaticallyDownloadsUpdates = mode.downloadsAutomatically
    }

    var canStartCheck: Bool {
        canCheckForUpdates && state.allowsManualCheck
    }

    // MARK: Actions

    func checkForUpdates() {
        guard let updater, canStartCheck else { return }
        driver?.userInitiated = true
        state = .idle
        updater.checkForUpdates()
    }

    func answer(_ choice: UpdateState.UpdateChoice) {
        guard case let .available(offer, reply) = state else { return }
        state = .idle
        if choice == .install, let infoURL = offer.infoURL {
            // The feed points at a web page instead of a download.
            NSWorkspace.shared.open(infoURL)
            reply(.later)
            return
        }
        reply(choice)
    }

    func cancelDownload() {
        guard case let .downloading(_, _, _, cancel) = state else { return }
        state = .idle
        cancel()
    }

    func installNow() {
        guard case let .ready(offer, install) = state else { return }
        state = .installing(offer)
        install()
    }

    func retry() {
        guard case let .error(_, _, retry) = state else { return }
        state = .idle
        retry()
    }

    private func scheduleUpToDateFade() {
        fadeTask?.cancel()
        guard case .upToDate = state else { return }
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, case .upToDate = self.state else { return }
            self.state = .idle
        }
    }
}

/// Turns Sparkle's callbacks into `UpdateState` changes, the way Ghostty's
/// `UpdateDriver` does. A menu bar app has no window that is always on
/// screen, so the state waits in the model until the popover is opened, and
/// the menu bar icon shows a dot meanwhile.
@MainActor
private final class UpdateDriver: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    weak var model: UpdateModel?
    /// Errors from background checks stay quiet; Sparkle tries again later.
    var userInitiated = false
    private var offer: UpdateOffer?

    private func set(_ state: UpdateState) {
        model?.state = state
    }

    private func makeOffer(_ item: SUAppcastItem) -> UpdateOffer {
        UpdateOffer(
            version: item.displayVersionString,
            notes: ReleaseNotes.bulletPoints(fromHTML: item.itemDescription),
            infoURL: item.isInformationOnlyUpdate ? item.infoURL : nil
        )
    }

    // MARK: SPUUpdaterDelegate

    /// Download mode: the update was fetched in the background and installs on
    /// quit. Returning true keeps the immediate-install handler for Restart Now;
    /// Sparkle then pauses further checks until the app restarts.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        let offer = makeOffer(item)
        self.offer = offer
        set(.ready(offer, install: immediateInstallHandler))
        return true
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Info.plist turns automatic checks on, so Sparkle shouldn't ask. If it
        // does, keep that default; the gear menu changes it.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        userInitiated = true
        set(.checking(cancel: cancellation))
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let offer = makeOffer(appcastItem)
        self.offer = offer

        if state.stage == .installing {
            // Already downloaded and waiting for quit; installing now relaunches.
            set(.ready(offer, install: { reply(.install) }))
            return
        }

        set(.available(offer, reply: { choice in
            switch choice {
            case .install: reply(.install)
            case .later: reply(.dismiss)
            case .skip: reply(.skip)
            }
        }))
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // Notes come from the appcast item's description instead.
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        set(.upToDate)
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        let wasChecking: Bool
        let personPressedInstall: Bool
        switch model?.state {
        case .checking?:
            (wasChecking, personPressedInstall) = (true, false)
        case .downloading?, .extracting?, .installing?:
            (wasChecking, personPressedInstall) = (false, true)
        default:
            (wasChecking, personPressedInstall) = (false, false)
        }

        guard userInitiated || personPressedInstall else {
            // A background check failed; Sparkle tries again later. Keep a
            // waiting update visible.
            if model?.state.isTransient == true { set(.idle) }
            return
        }

        set(.error(
            title: wasChecking ? "Couldn’t check for updates" : "Couldn’t update Agent Gauge",
            message: Self.describe(error),
            retry: { [weak self] in self?.model?.checkForUpdates() }
        ))
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        set(.downloading(offer, received: 0, expected: nil, cancel: cancellation))
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        guard case let .downloading(offer, _, _, cancel) = model?.state else { return }
        set(.downloading(offer, received: 0, expected: expectedContentLength, cancel: cancel))
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard case let .downloading(offer, received, expected, cancel) = model?.state else { return }
        set(.downloading(offer, received: received + length, expected: expected, cancel: cancel))
    }

    func showDownloadDidStartExtractingUpdate() {
        set(.extracting(offer))
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Only reached after the person pressed Install, so go ahead.
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        set(.installing(offer))
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        set(.idle)
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        userInitiated = false
        if model?.state.isTransient == true {
            set(.idle)
        }
    }

    private static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        // Sparkle wraps network failures, sometimes more than once.
        var chain: [NSError] = []
        var next: NSError? = nsError
        while let current = next, chain.count < 8 {
            chain.append(current)
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let unreachable = chain.contains { error in
            error.domain == NSURLErrorDomain
                || (error.domain == SUSparkleErrorDomain && error.code == Int(SUError.downloadError.rawValue))
        }
        if unreachable {
            return "GitHub didn’t answer. You may be offline. Nothing was changed."
        }
        return nsError.localizedDescription
    }
}
