import Foundation

/// Decodes the JSON Claude Code passes to statusline scripts.
///
/// Schema: https://code.claude.com/docs/en/statusline
/// `rate_limits` appears only for Claude.ai subscribers (Pro/Max) after the
/// first API response in a session, and a window is dropped once its
/// `resets_at` passes.
enum StatuslineCaptureDecoder {
    private static let maximumTimestamp: TimeInterval = 10_000_000_000

    private struct Input: Decodable {
        struct RateLimits: Decodable {
            struct Window: Decodable {
                let usedPercentage: Double?
                let resetsAt: TimeInterval?

                enum CodingKeys: String, CodingKey {
                    case usedPercentage = "used_percentage"
                    case resetsAt = "resets_at"
                }
            }

            let fiveHour: Window?
            let sevenDay: Window?

            enum CodingKeys: String, CodingKey {
                case fiveHour = "five_hour"
                case sevenDay = "seven_day"
            }
        }

        struct ModelInfo: Decodable {
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }

        let rateLimits: RateLimits?
        let model: ModelInfo?
        let version: String?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
            case model
            case version
        }
    }

    struct Capture: Equatable, Sendable {
        /// Distinguishes an early-session render with no `rate_limits` object
        /// from a real update whose individual windows are absent.
        let hadRateLimits: Bool
        let fiveHour: UsageWindow?
        let sevenDay: UsageWindow?
        let modelDisplayName: String?
        let claudeCodeVersion: String?
    }

    static func decode(_ data: Data) throws -> Capture {
        let input = try JSONDecoder().decode(Input.self, from: data)
        return Capture(
            hadRateLimits: input.rateLimits != nil,
            fiveHour: input.rateLimits?.fiveHour.flatMap(window),
            sevenDay: input.rateLimits?.sevenDay.flatMap(window),
            modelDisplayName: input.model?.displayName,
            claudeCodeVersion: input.version
        )
    }

    private static func window(_ wire: Input.RateLimits.Window) -> UsageWindow? {
        guard let usedPercentage = wire.usedPercentage, usedPercentage.isFinite else {
            return nil
        }
        if let resetsAt = wire.resetsAt,
           !resetsAt.isFinite || resetsAt <= 0 || resetsAt > maximumTimestamp {
            return nil
        }
        return UsageWindow(
            usedPercent: usedPercentage,
            resetsAt: wire.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
