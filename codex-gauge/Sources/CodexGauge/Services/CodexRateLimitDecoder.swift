import Foundation

enum CodexRateLimitDecoder {
    static func decode(_ data: Data, fetchedAt: Date = Date()) throws -> CodexUsageSnapshot {
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
        let primary = selected.primary.flatMap(makeWindow)
        let secondary = selected.secondary.flatMap(makeWindow)
        guard primary != nil || secondary != nil else {
            throw CodexUsageError.usageUnavailable
        }

        return CodexUsageSnapshot(
            primary: primary,
            secondary: secondary,
            planType: selected.planType,
            fetchedAt: fetchedAt
        )
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
            windowDurationMins: wire.windowDurationMins,
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
