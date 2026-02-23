import XCTest
@testable import Oto

final class SelectableTextRefinerTests: XCTestCase {
    private final class MockTextRefiner: TextRefining {
        let availabilityLabel: String
        let result: TextRefinementResult

        init(availabilityLabel: String, result: TextRefinementResult) {
            self.availabilityLabel = availabilityLabel
            self.result = result
        }

        func refine(request: TextRefinementRequest) async -> TextRefinementResult {
            result
        }
    }

    private func request() -> TextRefinementRequest {
        TextRefinementRequest(
            backend: .appleSpeech,
            mode: .enhanced,
            rawText: "hello world",
            runID: "run-1"
        )
    }

    func testRoutesToSelectedProvider() async {
        let apple = MockTextRefiner(
            availabilityLabel: "Apple Available",
            result: .refined(
                text: "Apple output",
                mode: .enhanced,
                availability: "Apple Available",
                latency: 0.1
            )
        )
        let lmStudio = LMStudioTextRefiner(
            requestExecutor: { request in
                let responseBody = """
                {
                  "choices": [
                    {
                      "message": {
                        "content": "LM Studio output"
                      }
                    }
                  ]
                }
                """
                let status = HTTPURLResponse(
                    url: request.url ?? URL(string: "http://127.0.0.1:1234")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
                return (Data(responseBody.utf8), status!)
            }
        )

        let refiner = SelectableTextRefiner(
            provider: .appleIntelligence,
            appleRefiner: apple,
            lmStudioRefiner: lmStudio
        )

        let appleResult = await refiner.refine(request: request())
        XCTAssertEqual(appleResult.text, "Apple output")
        XCTAssertEqual(refiner.availabilityLabel, "Apple Available")

        refiner.provider = .lmStudio
        let lmResult = await refiner.refine(request: request())
        XCTAssertEqual(lmResult.text, "LM Studio output")
        XCTAssertEqual(lmResult.outputSource, .refined)
    }
}
