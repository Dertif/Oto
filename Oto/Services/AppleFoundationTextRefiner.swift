import Foundation
import FoundationModels

private enum TextRefinerRuntimeError: Error {
    case timedOut
}

struct TextRefinerAvailabilityInfo {
    let isAvailable: Bool
    let label: String
}

final class AppleFoundationTextRefiner: TextRefining {
    private let timeoutSeconds: TimeInterval
    private let policy: TextRefinementPolicying
    private let nowProvider: () -> Date
    private let availabilityProvider: () -> TextRefinerAvailabilityInfo
    private let generator: @Sendable (String) async throws -> String

    init(
        timeoutSeconds: TimeInterval = 1.4,
        policy: TextRefinementPolicying = TextRefinementPolicy(),
        nowProvider: @escaping () -> Date = Date.init,
        availabilityProvider: @escaping () -> TextRefinerAvailabilityInfo = AppleFoundationTextRefiner.defaultAvailability,
        generator: @escaping @Sendable (String) async throws -> String = { promptText in
            try await AppleFoundationTextRefiner.defaultGenerator(promptText: promptText)
        }
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.policy = policy
        self.nowProvider = nowProvider
        self.availabilityProvider = availabilityProvider
        self.generator = generator
    }

    var availabilityLabel: String {
        availabilityProvider().label
    }

    func refine(request: TextRefinementRequest) async -> TextRefinementResult {
        let raw = request.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return .raw(
                text: request.rawText,
                mode: request.mode,
                availability: availabilityLabel,
                fallbackReason: "refinement_empty_input"
            )
        }

        guard request.mode == .enhanced else {
            return .raw(
                text: raw,
                mode: request.mode,
                availability: availabilityLabel,
                fallbackReason: "refinement_mode_raw"
            )
        }

        let availability = availabilityProvider()
        guard availability.isAvailable else {
            return .raw(
                text: raw,
                mode: request.mode,
                availability: availability.label,
                fallbackReason: "refiner_unavailable"
            )
        }

        let startedAt = nowProvider()

        do {
            let refined = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await self.generator(raw)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(max(0.1, self.timeoutSeconds) * 1_000_000_000))
                    throw TextRefinerRuntimeError.timedOut
                }

                let generated = try await group.next() ?? raw
                group.cancelAll()
                return generated
            }

            let latency = nowProvider().timeIntervalSince(startedAt)
            let trimmedRefined = refined.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRefined.isEmpty else {
                return .raw(
                    text: raw,
                    mode: request.mode,
                    availability: availability.label,
                    fallbackReason: "refiner_empty_output",
                    latency: latency
                )
            }

            let policyResult = policy.validate(rawText: raw, refinedText: trimmedRefined)
            guard policyResult.isAccepted else {
                return .raw(
                    text: raw,
                    mode: request.mode,
                    availability: availability.label,
                    fallbackReason: policyResult.reason ?? "guardrail_violation",
                    latency: latency
                )
            }

            return .refined(
                text: trimmedRefined,
                mode: request.mode,
                availability: availability.label,
                latency: latency
            )
        } catch TextRefinerRuntimeError.timedOut {
            return .raw(
                text: raw,
                mode: request.mode,
                availability: availability.label,
                fallbackReason: "refiner_timeout",
                latency: nowProvider().timeIntervalSince(startedAt)
            )
        } catch {
            return .raw(
                text: raw,
                mode: request.mode,
                availability: availability.label,
                fallbackReason: "refiner_error: \(error.localizedDescription)",
                latency: nowProvider().timeIntervalSince(startedAt)
            )
        }
    }

    private static func defaultAvailability() -> TextRefinerAvailabilityInfo {
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return TextRefinerAvailabilityInfo(isAvailable: true, label: "Available")
            case let .unavailable(reason):
                let reasonLabel: String
                switch reason {
                case .appleIntelligenceNotEnabled:
                    reasonLabel = "Unavailable: Apple Intelligence disabled"
                case .deviceNotEligible:
                    reasonLabel = "Unavailable: Device not eligible"
                case .modelNotReady:
                    reasonLabel = "Unavailable: Model not ready"
                @unknown default:
                    reasonLabel = "Unavailable: Unknown reason"
                }
                return TextRefinerAvailabilityInfo(isAvailable: false, label: reasonLabel)
            }
        }

        return TextRefinerAvailabilityInfo(isAvailable: false, label: "Unavailable: Requires macOS 26+")
    }

    private static func defaultGenerator(promptText: String) async throws -> String {
        if #available(macOS 26.0, *) {
            let instructions = """
            Refine the user's transcript for readability while preserving meaning.
            Requirements:
            - Keep all facts, numbers, dates, URLs, identifiers, and code-like tokens unchanged.
            - Use neutral business tone.
            - Improve punctuation, capitalization, sentence flow, and paragraph structure.
            - Remove filler words and disfluencies only when meaning is preserved.
            - Do not add any new information.
            - Return only the refined text.
            """

            let session = LanguageModelSession(model: .default, instructions: instructions)
            let response = try await session.respond(to: promptText)
            return response.content
        }

        return promptText
    }
}
