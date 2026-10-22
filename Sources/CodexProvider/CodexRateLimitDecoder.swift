import Foundation
import GaugeCore

enum CodexRateLimitDecoder {
    static let fiveHourDurationMins = 300
    static let weeklyDurationMins = 10_080

    static func decode(_ data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let response: RateLimitsRPCResponse
        do {
            response = try JSONDecoder().decode(RateLimitsRPCResponse.self, from: data)
        } catch {
            throw CodexUsageError.invalidResponse
        }

        if let error = response.error {
            throw classify(error)
        }
        guard let result = response.result else {
            throw CodexUsageError.invalidResponse
        }

        let selected = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits
        let primary = selected.primary
        let secondary = selected.secondary

        // Classify by reported duration rather than assuming the backend
        // always returns the windows in a fixed order. Fall back to the
        // conventional order only for windows of unknown duration.
        let wires = [primary, secondary].compactMap { $0 }
        let fiveHour = wires.first { $0.windowDurationMins == fiveHourDurationMins }
            ?? primary.flatMap { $0.windowDurationMins == weeklyDurationMins ? nil : $0 }
        let weekly = wires.first { $0.windowDurationMins == weeklyDurationMins }
            ?? secondary.flatMap { $0.windowDurationMins == fiveHourDurationMins ? nil : $0 }

        let fiveHourWindow = fiveHour.flatMap(makeWindow)
        let weeklyWindow = weekly.flatMap(makeWindow)
        guard fiveHourWindow != nil || weeklyWindow != nil else {
            throw CodexUsageError.usageUnavailable
        }

        return UsageSnapshot(
            fiveHourWindow: fiveHourWindow,
            weeklyWindow: weeklyWindow,
            badge: selected.planType.map(planDisplayName),
            capturedAt: fetchedAt,
            // Some plans, such as Pro Lite, only have a weekly window.
            absentWindowsHaveNoLimit: true
        )
    }

    static func planDisplayName(_ rawValue: String) -> String {
        if rawValue.lowercased() == "prolite" {
            return "Pro Lite"
        }
        return rawValue
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    static func classify(_ error: RPCErrorPayload) -> CodexUsageError {
        let message = error.message.lowercased()
        if message.contains("authentication required") ||
            message.contains("chatgpt authentication") ||
            message.contains("not logged in") ||
            message.contains("sign in")
        {
            return .notLoggedIn
        }
        return .serverError(error.code)
    }

    private static func makeWindow(_ wire: RateLimitWindowWire) -> UsageWindow? {
        guard let usedPercent = wire.usedPercent, usedPercent.isFinite else {
            return nil
        }
        return UsageWindow(
            usedPercent: usedPercent,
            resetsAt: wire.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

private struct RateLimitsRPCResponse: Decodable {
    let result: RateLimitsResultWire?
    let error: RPCErrorPayload?
}

private struct RateLimitsResultWire: Decodable {
    let rateLimits: RateLimitSnapshotWire
    let rateLimitsByLimitId: [String: RateLimitSnapshotWire]?
}

private struct RateLimitSnapshotWire: Decodable {
    let primary: RateLimitWindowWire?
    let secondary: RateLimitWindowWire?
    let planType: String?
}

private struct RateLimitWindowWire: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}

struct RPCErrorPayload: Decodable, Sendable {
    let code: Int?
    let message: String
}
