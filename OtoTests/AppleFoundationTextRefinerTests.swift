import XCTest
@testable import Oto

final class AppleFoundationTextRefinerTests: XCTestCase {
    private actor GeneratorCallTracker {
        private(set) var wasCalled = false

        func markCalled() {
            wasCalled = true
        }
    }

    private func request(mode: TextRefinementMode, text: String = "hello world", backend: STTBackend = .appleSpeech) -> TextRefinementRequest {
        TextRefinementRequest(
            backend: backend,
            mode: mode,
            rawText: text,
            runID: "run-1"
        )
    }

    func testRawModeSkipsGenerator() async {
        let refiner = AppleFoundationTextRefiner(
            availabilityProvider: { TextRefinerAvailabilityInfo(isAvailable: true, label: "Available") },
            generator: { _ in
                XCTFail("Generator should not be called in raw mode.")
                return ""
            }
        )

        let result = await refiner.refine(request: request(mode: .raw, text: "hello"))

        XCTAssertEqual(result.outputSource, .raw)
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.diagnostics.fallbackReason, "refinement_mode_raw")
    }

    func testEnhancedModeReturnsRawWhenUnavailable() async {
        let refiner = AppleFoundationTextRefiner(
            availabilityProvider: { TextRefinerAvailabilityInfo(isAvailable: false, label: "Unavailable") },
            generator: { _ in XCTFail("Generator should not be called when unavailable."); return "" }
        )

        let result = await refiner.refine(request: request(mode: .enhanced, text: "hello"))

        XCTAssertEqual(result.outputSource, .raw)
        XCTAssertEqual(result.diagnostics.fallbackReason, "refiner_unavailable")
    }

    func testEnhancedModeReturnsModelNotReadyFallbackReason() async {
        let refiner = AppleFoundationTextRefiner(
            modelNotReadyRetryCount: 0,
            availabilityProvider: {
                TextRefinerAvailabilityInfo(
                    isAvailable: false,
                    label: "Unavailable: Model not ready",
                    reason: .modelNotReady
                )
            },
            generator: { _ in XCTFail("Generator should not be called when model is unavailable."); return "" }
        )

        let result = await refiner.refine(request: request(mode: .enhanced, text: "hello"))

        XCTAssertEqual(result.outputSource, .raw)
        XCTAssertEqual(result.diagnostics.fallbackReason, "refiner_model_not_ready")
    }

    func testEnhancedModeRetriesModelNotReadyThenSucceeds() async {
        var availabilityCallCount = 0
        let generatorCallTracker = GeneratorCallTracker()
        let refiner = AppleFoundationTextRefiner(
            modelNotReadyRetryCount: 2,
            modelNotReadyRetryDelaySeconds: 0.0,
            availabilityProvider: {
                availabilityCallCount += 1
                if availabilityCallCount < 3 {
                    return TextRefinerAvailabilityInfo(
                        isAvailable: false,
                        label: "Unavailable: Model not ready",
                        reason: .modelNotReady
                    )
                }
                return TextRefinerAvailabilityInfo(isAvailable: true, label: "Available")
            },
            generator: { _ in
                await generatorCallTracker.markCalled()
                return "Hello, world."
            },
            sleep: { _ in }
        )

        let result = await refiner.refine(request: request(mode: .enhanced, text: "hello world"))

        XCTAssertEqual(result.outputSource, .refined)
        XCTAssertEqual(result.text, "Hello, world.")
        XCTAssertNil(result.diagnostics.fallbackReason)
        let wasGeneratorCalled = await generatorCallTracker.wasCalled
        XCTAssertTrue(wasGeneratorCalled)
        XCTAssertEqual(availabilityCallCount, 3)
    }

    func testEnhancedModeTimeoutFallsBackToRaw() async {
        let refiner = AppleFoundationTextRefiner(
            timeoutSeconds: 0.05,
            availabilityProvider: { TextRefinerAvailabilityInfo(isAvailable: true, label: "Available") },
            generator: { text in
                try await Task.sleep(nanoseconds: 250_000_000)
                return text + " refined"
            }
        )

        let result = await refiner.refine(request: request(mode: .enhanced, text: "hello"))

        XCTAssertEqual(result.outputSource, .raw)
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.diagnostics.fallbackReason, "refiner_timeout")
        XCTAssertNotNil(result.diagnostics.latency)
    }

    func testEnhancedModeGuardrailViolationFallsBackToRaw() async {
        let refiner = AppleFoundationTextRefiner(
            availabilityProvider: { TextRefinerAvailabilityInfo(isAvailable: true, label: "Available") },
            generator: { _ in "Deploy version 124 tomorrow." }
        )

        let result = await refiner.refine(request: request(mode: .enhanced, text: "Deploy version 123 tomorrow."))

        XCTAssertEqual(result.outputSource, .raw)
        XCTAssertEqual(result.diagnostics.fallbackReason, "guardrail_numeric_token_mismatch")
    }

    func testEnhancedModeSuccessReturnsRefinedText() async {
        let refiner = AppleFoundationTextRefiner(
            availabilityProvider: { TextRefinerAvailabilityInfo(isAvailable: true, label: "Available") },
            generator: { _ in "Hello, world." }
        )

        let result = await refiner.refine(request: request(mode: .enhanced, text: "hello world"))

        XCTAssertEqual(result.outputSource, .refined)
        XCTAssertEqual(result.text, "Hello, world.")
        XCTAssertNil(result.diagnostics.fallbackReason)
        XCTAssertNotNil(result.diagnostics.latency)
    }
}
