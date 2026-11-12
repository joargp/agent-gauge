import Foundation

/// How Agent Gauge looks for and installs new versions. Sparkle stores the two
/// underlying switches itself.
enum UpdateMode: String, CaseIterable, Identifiable {
    case off
    case check
    case download

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .check: "Notify Me"
        case .download: "Download, Install on Quit"
        }
    }

    var checksAutomatically: Bool { self != .off }
    var downloadsAutomatically: Bool { self == .download }

    init(checksAutomatically: Bool, downloadsAutomatically: Bool) {
        switch (checksAutomatically, downloadsAutomatically) {
        case (false, _): self = .off
        case (true, false): self = .check
        case (true, true): self = .download
        }
    }
}

/// A version found in the update feed.
struct UpdateOffer {
    let version: String
    let notes: [String]
    /// Set when the feed only points at a web page instead of a download.
    let infoURL: URL?
}

/// One step of an update, as Sparkle reports it to `UpdateDriver`.
enum UpdateState {
    case idle
    case checking(cancel: () -> Void)
    /// Fades back to idle after a few seconds.
    case upToDate
    case available(UpdateOffer, reply: (UpdateChoice) -> Void)
    case downloading(UpdateOffer?, received: UInt64, expected: UInt64?, cancel: () -> Void)
    case extracting(UpdateOffer?)
    /// Downloaded and waiting. Installs on quit, or now with `install`.
    case ready(UpdateOffer?, install: () -> Void)
    case installing(UpdateOffer?)
    case error(title: String, message: String, retry: () -> Void)

    enum UpdateChoice {
        case install
        case later
        case skip
    }

    /// The menu bar icon shows a dot while an update waits for the person.
    var wantsAttention: Bool {
        switch self {
        case .available, .ready: true
        default: false
        }
    }

    /// A manual check only makes sense when nothing is in progress.
    var allowsManualCheck: Bool {
        switch self {
        case .idle, .upToDate, .error: true
        default: false
        }
    }

    /// Ended by Sparkle closing its update session without telling us more.
    var isTransient: Bool {
        switch self {
        case .checking, .available, .downloading, .extracting: true
        default: false
        }
    }

    var downloadFraction: Double? {
        guard case let .downloading(_, received, expected?, _) = self, expected > 0 else { return nil }
        return min(1, Double(received) / Double(expected))
    }
}

enum ReleaseNotes {
    /// The bullet points of an appcast item's HTML description, as plain text.
    static func bulletPoints(fromHTML html: String?) -> [String] {
        guard let html else { return [] }
        let pattern = #"<li[^>]*>(.*?)</li>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let inner = Range(match.range(at: 1), in: html) else { return nil }
            let text = plainText(String(html[inner]))
            return text.isEmpty ? nil : text
        }
    }

    private static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
