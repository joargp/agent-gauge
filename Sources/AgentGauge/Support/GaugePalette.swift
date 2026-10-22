import SwiftUI

enum GaugePalette {
    /// Anthropic's warm brand orange, kept distinct from the brighter system
    /// orange used for low-remaining warnings.
    static let claudeFiveHour = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let claudeWeekly: Color = .yellow
    static let codexFiveHour: Color = .green
    static let codexWeekly: Color = .blue

    static func ringColor(remainingPercent: Double?, healthy: Color) -> Color {
        guard let remainingPercent else { return .secondary }
        if remainingPercent <= 10 { return .red }
        if remainingPercent <= 25 { return .orange }
        return healthy
    }
}
