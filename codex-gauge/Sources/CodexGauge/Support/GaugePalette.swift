import SwiftUI

enum GaugePalette {
    static let fiveHour: Color = .green
    static let weekly: Color = .blue

    static func ringColor(remainingPercent: Double?, healthy: Color) -> Color {
        guard let remainingPercent else { return .secondary }
        if remainingPercent <= 10 { return .red }
        if remainingPercent <= 25 { return .orange }
        return healthy
    }
}
