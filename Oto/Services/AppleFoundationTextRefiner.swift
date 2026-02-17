import Foundation
import FoundationModels

private enum TextRefinerRuntimeError: Error {
    case timedOut
}

enum TextRefinerUnavailabilityReason: Equatable {
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case unsupportedOS
    case unknown
}

struct TextRefinerAvailabilityInfo {
    let isAvailable: Bool
    let label: String
    let reason: TextRefinerUnavailabilityReason?

    init(isAvailable: Bool, label: String, reason: TextRefinerUnavailabilityReason? = nil) {
        self.isAvailable = isAvailable
        self.label = label
        self.reason = reason
    }
}

final class AppleFoundationTextRefiner: TextRefining {
    private let timeoutSeconds: TimeInterval
    private let modelNotReadyRetryCount: Int
    private let modelNotReadyRetryDelaySeconds: TimeInterval
    private let policy: TextRefinementPolicying
    private let nowProvider: () -> Date
    private let availabilityProvider: () -> TextRefinerAvailabilityInfo
    private let generator: @Sendable (String) async throws -> String
    private let sleep: @Sendable (TimeInterval) async -> Void

    init(
        timeoutSeconds: TimeInterval = 1.4,
        modelNotReadyRetryCount: Int = 3,
        modelNotReadyRetryDelaySeconds: TimeInterval = 1.0,
        policy: TextRefinementPolicying = TextRefinementPolicy(),
        nowProvider: @escaping () -> Date = Date.init,
        availabilityProvider: @escaping () -> TextRefinerAvailabilityInfo = AppleFoundationTextRefiner.defaultAvailability,
        generator: @escaping @Sendable (String) async throws -> String = { promptText in
            try await AppleFoundationTextRefiner.defaultGenerator(promptText: promptText)
        },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            let nanoseconds = UInt64(max(0.0, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.modelNotReadyRetryCount = max(0, modelNotReadyRetryCount)
        self.modelNotReadyRetryDelaySeconds = max(0.0, modelNotReadyRetryDelaySeconds)
        self.policy = policy
        self.nowProvider = nowProvider
        self.availabilityProvider = availabilityProvider
        self.generator = generator
        self.sleep = sleep
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

        let availability = await resolvedAvailabilityForRefinement(runID: request.runID)
        guard availability.isAvailable else {
            let fallbackReason = Self.fallbackReason(for: availability)
            OtoLogger.log(
                "Refinement unavailable (runID=\(request.runID ?? "unknown"), mode=\(request.mode.rawValue), reason=\(fallbackReason), label=\(availability.label))",
                category: .flow,
                level: .error
            )
            return .raw(
                text: raw,
                mode: request.mode,
                availability: availability.label,
                fallbackReason: fallbackReason
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
                OtoLogger.log(
                    "Refinement produced empty output; falling back to raw (runID=\(request.runID ?? "unknown"))",
                    category: .flow,
                    level: .error
                )
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
                OtoLogger.log(
                    "Refinement rejected by policy; falling back to raw (runID=\(request.runID ?? "unknown"), reason=\(policyResult.reason ?? "guardrail_violation"))",
                    category: .flow,
                    level: .error
                )
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
            OtoLogger.log(
                "Refinement timed out after \(timeoutSeconds)s; falling back to raw (runID=\(request.runID ?? "unknown"))",
                category: .flow,
                level: .error
            )
            return .raw(
                text: raw,
                mode: request.mode,
                availability: availability.label,
                fallbackReason: "refiner_timeout",
                latency: nowProvider().timeIntervalSince(startedAt)
            )
        } catch {
            OtoLogger.log(
                "Refinement failed with error '\(error.localizedDescription)'; falling back to raw (runID=\(request.runID ?? "unknown"))",
                category: .flow,
                level: .error
            )
            return .raw(
                text: raw,
                mode: request.mode,
                availability: availability.label,
                fallbackReason: "refiner_error: \(error.localizedDescription)",
                latency: nowProvider().timeIntervalSince(startedAt)
            )
        }
    }

    private func resolvedAvailabilityForRefinement(runID: String?) async -> TextRefinerAvailabilityInfo {
        var availability = availabilityProvider()
        guard !availability.isAvailable, availability.reason == .modelNotReady, modelNotReadyRetryCount > 0 else {
            return availability
        }

        OtoLogger.log(
            "Foundation model not ready; starting readiness retries (runID=\(runID ?? "unknown"), attempts=\(modelNotReadyRetryCount), delay=\(modelNotReadyRetryDelaySeconds)s)",
            category: .flow,
            level: .error
        )

        for attempt in 1 ... modelNotReadyRetryCount {
            await sleep(modelNotReadyRetryDelaySeconds)
            availability = availabilityProvider()

            if availability.isAvailable {
                OtoLogger.log(
                    "Foundation model became available on retry \(attempt)/\(modelNotReadyRetryCount) (runID=\(runID ?? "unknown"))",
                    category: .flow,
                    level: .info
                )
                return availability
            }

            if availability.reason != .modelNotReady {
                OtoLogger.log(
                    "Foundation model retry interrupted by new availability reason '\(availability.label)' (runID=\(runID ?? "unknown"))",
                    category: .flow,
                    level: .error
                )
                return availability
            }
        }

        OtoLogger.log(
            "Foundation model remained not ready after retries (runID=\(runID ?? "unknown"))",
            category: .flow,
            level: .error
        )
        return availability
    }

    private static func fallbackReason(for availability: TextRefinerAvailabilityInfo) -> String {
        switch availability.reason {
        case .appleIntelligenceNotEnabled:
            return "refiner_apple_intelligence_disabled"
        case .deviceNotEligible:
            return "refiner_device_not_eligible"
        case .modelNotReady:
            return "refiner_model_not_ready"
        case .unsupportedOS:
            return "refiner_requires_macos_26"
        case .unknown, .none:
            return "refiner_unavailable"
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
                let unavailabilityReason: TextRefinerUnavailabilityReason
                switch reason {
                case .appleIntelligenceNotEnabled:
                    reasonLabel = "Unavailable: Apple Intelligence disabled"
                    unavailabilityReason = .appleIntelligenceNotEnabled
                case .deviceNotEligible:
                    reasonLabel = "Unavailable: Device not eligible"
                    unavailabilityReason = .deviceNotEligible
                case .modelNotReady:
                    reasonLabel = "Unavailable: Model not ready"
                    unavailabilityReason = .modelNotReady
                @unknown default:
                    reasonLabel = "Unavailable: Unknown reason"
                    unavailabilityReason = .unknown
                }
                return TextRefinerAvailabilityInfo(
                    isAvailable: false,
                    label: reasonLabel,
                    reason: unavailabilityReason
                )
            }
        }

        return TextRefinerAvailabilityInfo(
            isAvailable: false,
            label: "Unavailable: Requires macOS 26+",
            reason: .unsupportedOS
        )
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
