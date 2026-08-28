import SwiftUI

enum GaugePalette {
    /// Anthropic's warm brand orange, kept distinct from the brighter system
    /// orange used for low-remaining warnings.
    static let fiveHour = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let weekly: Color = .yellow

    static func ringColor(remainingPercent: Double?, healthy: Color) -> Color {
        guard let remainingPercent else { return .secondary }
        if remainingPercent <= 10 { return .red }
        if remainingPercent <= 25 { return .orange }
        return healthy
    }
}
