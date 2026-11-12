import SwiftUI

/// The update row above the divider in every popover. It only appears while
/// there is something to show.
struct UpdateRowView: View {
    @ObservedObject var updates: UpdateModel
    @State private var showsNotes = false

    var body: some View {
        if updates.isEnabled, let content {
            HStack(alignment: .top, spacing: 8) {
                icon
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    subtitle

                    if showsNotes, let offer = content.offer, !offer.notes.isEmpty {
                        notes(offer)
                    }

                    if content.actionsBelow, !content.actions.isEmpty {
                        HStack(spacing: 6) {
                            Spacer()
                            actions(content.actions)
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !content.actionsBelow, !content.actions.isEmpty {
                    actions(content.actions)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(content.tone.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if content.tone == .highlighted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentBlue.opacity(0.35), lineWidth: 0.5)
                }
            }
            .accessibilityElement(children: .contain)
            .animation(.easeInOut(duration: 0.15), value: showsNotes)
        }
    }

    // MARK: Content per state

    private enum Tone: Equatable {
        case highlighted, neutral, error

        var background: Color {
            switch self {
            case .highlighted: Color.accentBlue.opacity(0.1)
            case .neutral: Color.primary.opacity(0.05)
            case .error: Color.red.opacity(0.09)
            }
        }
    }

    private enum Action: Hashable {
        case later, install, cancel, restart, retry
    }

    private enum Icon {
        case spinner, check, dot, warning
    }

    private struct Content {
        var icon: Icon
        var title: String
        var offer: UpdateOffer?
        var tone: Tone = .neutral
        var actions: [Action] = []
        var actionsBelow = false
    }

    private var content: Content? {
        let current = updates.currentVersion
        func next(_ offer: UpdateOffer?) -> String {
            offer.map { " \($0.version)" } ?? ""
        }

        switch updates.state {
        case .idle:
            return nil
        case .checking:
            return Content(icon: .spinner, title: "Checking for updates…")
        case .upToDate:
            return Content(icon: .check, title: "Agent Gauge \(current) is the latest version.")
        case let .available(offer, _):
            return Content(
                icon: .dot,
                title: "Agent Gauge \(offer.version) is available",
                offer: offer,
                tone: .highlighted,
                actions: [.later, .install],
                actionsBelow: true
            )
        case let .downloading(offer, _, _, _):
            return Content(icon: .spinner, title: "Downloading\(next(offer))", offer: offer, tone: .highlighted, actions: [.cancel])
        case let .extracting(offer):
            return Content(icon: .spinner, title: "Preparing\(next(offer))…", offer: offer)
        case let .ready(offer, _):
            return Content(
                icon: .dot,
                title: offer.map { "Agent Gauge \($0.version) is ready" } ?? "An update is ready",
                offer: offer,
                tone: .highlighted,
                actions: [.restart],
                actionsBelow: true
            )
        case let .installing(offer):
            return Content(icon: .spinner, title: "Installing\(next(offer))…", offer: offer)
        case let .error(title, _, _):
            return Content(icon: .warning, title: title, tone: .error, actions: [.retry], actionsBelow: true)
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var icon: some View {
        switch content?.icon {
        case .spinner:
            ProgressView().controlSize(.mini)
        case .check:
            Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(.green)
        case .dot:
            Circle().fill(Color.accentBlue).frame(width: 7, height: 7)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch updates.state {
        case let .available(offer, _):
            subtitleLine("You have \(updates.currentVersion).", offer: offer)
        case let .ready(offer, _):
            subtitleLine("Installs when you quit.", offer: offer)
        case .downloading:
            HStack(spacing: 6) {
                if let fraction = updates.state.downloadFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(.accentBlue)
                    Text("\(Int((fraction * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(minWidth: 28, alignment: .trailing)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(.accentBlue)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        case .installing:
            Text("Agent Gauge will open again in a moment.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case let .error(_, message, _):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    private func subtitleLine(_ text: String, offer: UpdateOffer?) -> some View {
        HStack(spacing: 6) {
            Text(text)
            if let offer, !offer.notes.isEmpty {
                Button(showsNotes ? "Hide changes" : "What’s new") {
                    showsNotes.toggle()
                }
                .buttonStyle(.link)
                .foregroundStyle(Color(nsColor: .linkColor))
                .accessibilityValue(showsNotes ? "Expanded" : "Collapsed")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func notes(_ offer: UpdateOffer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(offer.notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("•")
                    Text(note).fixedSize(horizontal: false, vertical: true)
                }
            }
            if case .available = updates.state {
                Button("Skip this version") {
                    updates.answer(.skip)
                }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
        }
        .font(.caption2)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func actions(_ actions: [Action]) -> some View {
        HStack(spacing: 6) {
            ForEach(actions, id: \.self) { action in
                switch action {
                case .later:
                    Button("Later") { updates.answer(.later) }
                case .install:
                    Button("Install") { updates.answer(.install) }
                        .buttonStyle(.borderedProminent)
                case .cancel:
                    Button("Cancel") { updates.cancelDownload() }
                case .restart:
                    Button("Restart Now") { updates.installNow() }
                        .buttonStyle(.borderedProminent)
                case .retry:
                    Button("Try Again") { updates.retry() }
                        .disabled(!updates.canCheckForUpdates)
                }
            }
        }
        .controlSize(.small)
        .tint(.accentBlue)
    }
}

private extension Color {
    /// The design's update blue, the system blue in both appearances.
    static let accentBlue = Color(nsColor: .systemBlue)
}

private extension ShapeStyle where Self == Color {
    static var accentBlue: Color { Color.accentBlue }
}
