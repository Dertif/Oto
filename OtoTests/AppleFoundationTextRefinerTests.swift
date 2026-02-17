import XCTest
@testable import Oto

final class AppleFoundationTextRefinerTests: XCTestCase {
    private func request(mode: TextRefinementMode, text: String = "hello world", backend: STTBackend = .appleSpeech) -> TextRefinementRequest {
        TextRefinementRequest(
            backend: backend,
            mode: mode,
            rawText: text,
            runID: "run-1"
        )
    }

    func testRawModeSkipsGenerator() async {
        var generatorCalled = false
        let refiner = AppleFoundationTextRefiner(
            availabilityProvider: { TextRefinerAvailabilityInfo(isAvailable: true, label: "Available") },
            generator: { _ in
                generatorCalled = true
                return "ignored"
            }
        )

        let result = await refiner.refine(request: request(mode: .raw, text: "hello"))

        XCTAssertEqual(result.outputSource, .raw)
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.diagnostics.fallbackReason, "refinement_mode_raw")
        XCTAssertFalse(generatorCalled)
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
