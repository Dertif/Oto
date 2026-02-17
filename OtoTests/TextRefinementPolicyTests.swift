import XCTest
@testable import Oto

final class TextRefinementPolicyTests: XCTestCase {
    private let policy = TextRefinementPolicy()

    func testAcceptsEquivalentRefinement() {
        let raw = "Please ship build 123 to https://example.com/a/b by 2026-02-20."
        let refined = "Please ship build 123 to https://example.com/a/b by 2026-02-20."

        let result = policy.validate(rawText: raw, refinedText: refined)

        XCTAssertEqual(result, .accepted)
    }

    func testRejectsNumericDrift() {
        let raw = "Deploy version 123 today."
        let refined = "Deploy version 124 today."

        let result = policy.validate(rawText: raw, refinedText: refined)

        XCTAssertEqual(result, .rejected("guardrail_numeric_token_mismatch"))
    }

    func testRejectsURLDrift() {
        let raw = "Open https://example.com/docs first."
        let refined = "Open the docs first."

        let result = policy.validate(rawText: raw, refinedText: refined)

        XCTAssertEqual(result, .rejected("guardrail_url_token_mismatch"))
    }

    func testRejectsIdentifierDrift() {
        let raw = "Use ticket REM-58 and file config.v1.json."
        let refined = "Use ticket REM-58 only."

        let result = policy.validate(rawText: raw, refinedText: refined)

        XCTAssertEqual(result, .rejected("guardrail_identifier_token_mismatch"))
    }

    func testRejectsCommitmentShift() {
        let raw = "I think we can review this tomorrow."
        let refined = "I will review this tomorrow."

        let result = policy.validate(rawText: raw, refinedText: refined)

        XCTAssertEqual(result, .rejected("guardrail_commitment_shift"))
    }
}
