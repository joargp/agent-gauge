import AppKit
import GaugeCore
import SwiftUI

struct WelcomeView: View {
    @ObservedObject private var welcome: WelcomeModel
    @ObservedObject private var model: AppModel
    private let onDone: () -> Void

    init(welcome: WelcomeModel, onDone: @escaping () -> Void) {
        self.welcome = welcome
        self.model = welcome.appModel
        self.onDone = onDone
    }

    var body: some View {
        Group {
            switch welcome.page {
            case .agents:
                agentsPage
            case .menuBar:
                menuBarPage
            }
        }
        .font(.system(size: 13))
        // Room for the transparent title bar's window buttons.
        .padding(.top, 34)
        .padding(.horizontal, 32)
        .padding(.bottom, 26)
        .frame(width: 560)
        // 600 points tall with the title bar, like the design.
        .frame(minHeight: 572, alignment: .top)
    }

    // MARK: - Choose agents

    private var agentsPage: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                    .overlay(
                        NestedRingsGlyph(
                            outer: 0.72,
                            inner: 0.55,
                            outerTint: GaugeProvider.codex.weeklyTint,
                            innerTint: GaugeProvider.claude.fiveHourTint,
                            size: 44,
                            lineWidth: 1.8
                        )
                    )
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                pageHeading(
                    "Welcome to Agent Gauge",
                    detail: "Choose which coding agents get a usage gauge in your menu bar. Each one shows how much of its 5-hour and weekly limits is left."
                )
            }

            section("Show in menu bar") {
                VStack(spacing: 0) {
                    agentRow(.claude, status: welcome.claudeStatus)
                    Divider()
                        .padding(.leading, 60)
                    agentRow(.codex, status: welcome.codexStatus)
                }
            }

            section("General") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Launch at login")
                            .fontWeight(.semibold)
                        Text(model.launchAtLoginError ?? "Opens Agent Gauge when you log in to your Mac.")
                            .font(.system(size: 12))
                            .foregroundStyle(model.launchAtLoginError == nil ? .secondary : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Toggle("Launch at login", isOn: Binding(
                        get: { model.launchesAtLogin },
                        set: { model.setLaunchesAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.vertical, 10)
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .frame(minHeight: 56)
            }

            Spacer(minLength: 0)

            HStack(spacing: 16) {
                Text(anyAgentVisible
                     ? "You can change these later from the gear menu in each popover."
                     : "Turn on at least one agent to continue.")
                    .font(.system(size: 12))
                    .foregroundStyle(anyAgentVisible ? .secondary : Color.orange)

                Spacer()

                Button("Continue") {
                    welcome.page = .menuBar
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!anyAgentVisible)
            }
        }
    }

    private var anyAgentVisible: Bool {
        !model.visibleProviders.isEmpty
    }

    private func agentRow(_ provider: GaugeProvider, status: AgentSetupStatus) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(AgentGlyph(provider: provider, store: model.store(for: provider), size: 24))
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.productName)
                    .fontWeight(.semibold)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle()
                        .fill(dotColor(status.tone))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(status.message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            if let action = status.action {
                actionButton(action)
            }

            Toggle("Show \(provider.productName) in the menu bar", isOn: Binding(
                get: { model.isVisible(provider) },
                set: { model.setVisible($0, for: provider) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!model.canHide(provider))
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(minHeight: 64)
    }

    @ViewBuilder
    private func actionButton(_ action: AgentSetupStatus.Action) -> some View {
        switch action {
        case .connect:
            Button(welcome.isConnectingClaude ? "Connecting…" : "Connect") {
                Task { await welcome.connectClaude() }
            }
            .disabled(welcome.isConnectingClaude)
        case .copyLoginCommand:
            Button(welcome.copiedLoginCommand ? "Copied" : "Copy command") {
                welcome.copyLoginCommand()
            }
            .help("Copies “\(WelcomeModel.loginCommand)” to paste in Terminal")
        }
    }

    private func dotColor(_ tone: AgentSetupStatus.Tone) -> Color {
        switch tone {
        case .checking: Color.secondary.opacity(0.5)
        case .ready: .green
        case .attention: .orange
        }
    }

    // MARK: - Menu bar

    private var menuBarPage: some View {
        VStack(spacing: 22) {
            pageHeading(
                "Agent Gauge is in your menu bar",
                detail: "Click a gauge to see what’s left and when it resets."
            )
            .padding(.top, 4)

            menuBarPreview

            HStack(spacing: 20) {
                NestedRingsGlyph(
                    outer: 0.48,
                    inner: 0.44,
                    outerTint: GaugeProvider.claude.weeklyTint,
                    innerTint: GaugeProvider.claude.fiveHourTint,
                    size: 72,
                    lineWidth: 1.6
                )
                .accessibilityLabel("Nested rings: the outer ring is the weekly limit, the inner ring is the 5-hour limit")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Reading a gauge")
                        .fontWeight(.semibold)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("**Outer ring** · weekly limit left")
                        Text("**Inner ring** · 5-hour limit left")
                        Text("A ring turns orange under 25% and red under 10%.")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .groupBox()

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Don’t see them? A full menu bar, or a menu bar manager like Ice or Bartender, can hide new items. Move the Agent Gauge items to its visible section.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor.opacity(0.28))
            )

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("Back") {
                    welcome.page = .agents
                }
                .controlSize(.large)

                Spacer()

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// A dark menu bar strip with the visible gauges, labelled underneath.
    private var menuBarPreview: some View {
        let visible = GaugeProvider.allCases.filter(model.isVisible)
        let iconColor = Color(white: 0.9)

        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(white: 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.white.opacity(0.08))
                )
                .frame(height: 36)

            Grid(horizontalSpacing: 6, verticalSpacing: 8) {
                GridRow {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                    ForEach(visible) { provider in
                        AgentGlyph(
                            provider: provider,
                            store: model.store(for: provider),
                            size: 18,
                            track: Color.white.opacity(0.22)
                        )
                        .frame(width: 44)
                    }
                    Image(systemName: "wifi")
                        .foregroundStyle(iconColor)
                        .frame(width: 32)
                    Image(systemName: "battery.75percent")
                        .foregroundStyle(iconColor)
                        .frame(width: 40)
                    Text(menuBarClock)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(iconColor)
                        .padding(.trailing, 12)
                }
                GridRow {
                    Color.clear
                        .frame(height: 1)
                    ForEach(visible) { provider in
                        Text(provider.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Menu bar with the \(visible.map(\.name).joined(separator: " and ")) gauges next to Wi-Fi, battery and the clock")
    }

    private var menuBarClock: String {
        let now = Date.now
        let day = now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day)  \(now.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: - Shared pieces

    private func pageHeading(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
                .groupBox()
        }
    }
}

private extension View {
    func groupBox() -> some View {
        background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}

/// An agent's menu bar gauge, drawn from its latest reading.
private struct AgentGlyph: View {
    let provider: GaugeProvider
    @ObservedObject var store: UsageStore
    let size: Double
    var track: Color = Color.primary.opacity(0.16)

    var body: some View {
        NestedRingsGlyph(
            outer: remaining(store.usage?.weeklyState()),
            inner: remaining(store.usage?.fiveHourState()),
            outerTint: provider.weeklyTint,
            innerTint: provider.fiveHourTint,
            size: size,
            lineWidth: 2,
            track: track
        )
    }

    private func remaining(_ state: WindowDisplayState?) -> Double? {
        guard case let .present(window) = state else { return nil }
        return window.remainingFraction
    }
}

/// Two concentric rings in the menu bar icon's proportions, scaled to `size`.
private struct NestedRingsGlyph: View {
    let outer: Double?
    let inner: Double?
    let outerTint: Color
    let innerTint: Color
    let size: Double
    let lineWidth: Double
    var track: Color = Color.primary.opacity(0.16)

    var body: some View {
        let scale = size / 18
        ZStack {
            ring(outer, tint: outerTint, radius: 7 * scale, lineWidth: lineWidth * scale)
            ring(inner, tint: innerTint, radius: 3.8 * scale, lineWidth: lineWidth * scale)
        }
        .frame(width: size, height: size)
    }

    private func ring(_ fraction: Double?, tint: Color, radius: Double, lineWidth: Double) -> some View {
        let progress = RingGeometry.trimProgress(for: fraction ?? 0, centerRadius: radius, lineWidth: lineWidth)
        let rounded = RingGeometry.usesRoundedCaps(for: fraction ?? 0, centerRadius: radius, lineWidth: lineWidth)

        return ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            if fraction != nil {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        GaugePalette.ringColor(remainingPercent: (fraction ?? 0) * 100, healthy: tint),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: rounded ? .round : .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}
