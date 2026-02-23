import XCTest
@testable import Oto

final class LMStudioTextRefinerTests: XCTestCase {
    private func request(mode: TextRefinementMode, text: String = "hello world") -> TextRefinementRequest {
        TextRefinementRequest(
            backend: .appleSpeech,
            mode: mode,
            rawText: text,
            runID: "run-1"
        )
    }

    func testRawModeSkipsNetworkCall() async {
        let refiner = LMStudioTextRefiner(
            requestExecutor: { _ in
                XCTFail("Network should not be called in raw mode.")
                let fallbackURL = URL(string: "http://127.0.0.1:1234")!
                let response = HTTPURLResponse(
                    url: fallbackURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
        )

        let result = await refiner.refine(request: request(mode: .raw, text: "hello"))

        XCTAssertEqual(result.outputSource, .raw)
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.diagnostics.fallbackReason, "refinement_mode_raw")
    }

    func testEnhancedSuccessReturnsRefinedText() async {
        let response = """
        {
          "choices": [
            {
              "message": {
                "content": "Hello, world."
              }
            }
          ]
        }
        """
        let refiner = LMStudioTextRefiner(
            baseURLString: "http://127.0.0.1:1234",
            modelName: "qwen2.5",
            requestExecutor: { request in
                XCTAssertEqual(request.url?.path, "/v1/chat/completions")
                let status = HTTPURLResponse(
                    url: request.url ?? URL(string: "http://127.0.0.1:1234")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
                return (Data(response.utf8), status!)
            }
        )

        let result = await refiner.refine(request: request(mode: .enhanced, text: "hello world"))

        XCTAssertEqual(result.outputSource, .refined)
        XCTAssertEqual(result.text, "Hello, world.")
        XCTAssertNil(result.diagnostics.fallbackReason)
        XCTAssertEqual(result.diagnostics.availability, "Configured: http://127.0.0.1:1234 (model: qwen2.5)")
    }

    func testEnhancedInvalidURLFallsBackToRaw() async {
        let refiner = LMStudioTextRefiner(baseURLString: "://bad-url")

        let result = await refiner.refine(request: request(mode: .enhanced, text: "hello"))

        XCTAssertEqual(result.outputSource, .raw)
        XCTAssertEqual(result.diagnostics.fallbackReason, "refiner_lm_studio_invalid_url")
    }

    func testEnhancedHttpErrorFallsBackToRaw() async {
        let response = """
        {
          "error": {
            "message": "model not loaded"
          }
        }
        """
        let refiner = LMStudioTextRefiner(
            requestExecutor: { request in
                let status = HTTPURLResponse(
                    url: request.url ?? URL(string: "http://127.0.0.1:1234")!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )
                return (Data(response.utf8), status!)
            }
        )

        let result = await refiner.refine(request: request(mode: .enhanced, text: "hello"))

        XCTAssertEqual(result.outputSource, .raw)
        XCTAssertEqual(result.diagnostics.fallbackReason, "refiner_lm_studio_http_503")
    }

    func testEnhancedUnreachableFallsBackToRaw() async {
        let refiner = LMStudioTextRefiner(
            requestExecutor: { _ in
                throw URLError(.cannotConnectToHost)
            }
        )

        let result = await refiner.refine(request: request(mode: .enhanced, text: "hello"))

        XCTAssertEqual(result.outputSource, .raw)
        XCTAssertEqual(result.diagnostics.fallbackReason, "refiner_lm_studio_unreachable")
    }
}
