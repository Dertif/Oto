import XCTest
@testable import Oto

final class OtoCLICommandTests: XCTestCase {
    private let currentDirectoryURL = URL(fileURLWithPath: "/tmp/oto-cli-tests", isDirectory: true)

    func testTranscribeParsesDefaults() throws {
        let command = try OtoCLIParser.parse(
            arguments: ["transcribe", "samples/clip.wav"],
            currentDirectoryURL: currentDirectoryURL
        )

        guard case let .transcribe(parsed) = command else {
            return XCTFail("Expected transcribe command.")
        }

        XCTAssertEqual(parsed.model, .appleSpeech)
        XCTAssertEqual(parsed.qualityPreset, .fast)
        XCTAssertEqual(parsed.outputFormat, .text)
        XCTAssertEqual(parsed.outputDestination, .standardOutput)
        XCTAssertEqual(parsed.audioFileURL.path, "/tmp/oto-cli-tests/samples/clip.wav")
    }

    func testTranscribeParsesWhisperKitOptions() throws {
        let command = try OtoCLIParser.parse(
            arguments: [
                "transcribe",
                "--model", "whisper-base",
                "--quality", "accurate",
                "--format", "json",
                "--output", "artifacts/out.json",
                "samples/clip.wav"
            ],
            currentDirectoryURL: currentDirectoryURL
        )

        guard case let .transcribe(parsed) = command else {
            return XCTFail("Expected transcribe command.")
        }

        XCTAssertEqual(parsed.model, .whisperKitBase)
        XCTAssertEqual(parsed.qualityPreset, .accurate)
        XCTAssertEqual(parsed.outputFormat, .json)
        XCTAssertEqual(
            parsed.outputDestination,
            .file(URL(fileURLWithPath: "/tmp/oto-cli-tests/artifacts/out.json"))
        )
    }

    func testTranscribeParsesWhisperCppModel() throws {
        let command = try OtoCLIParser.parse(
            arguments: ["transcribe", "--model", "base.en", "samples/clip.wav"],
            currentDirectoryURL: currentDirectoryURL
        )

        guard case let .transcribe(parsed) = command else {
            return XCTFail("Expected transcribe command.")
        }

        XCTAssertEqual(parsed.model, .whisperCpp(.baseEn))
        XCTAssertEqual(parsed.qualityPreset, .fast)
    }

    func testRefineParsesInlineText() throws {
        let command = try OtoCLIParser.parse(
            arguments: [
                "refine",
                "--backend", "whisper-cpp",
                "--mode", "raw",
                "--text", "hello world"
            ],
            currentDirectoryURL: currentDirectoryURL
        )

        guard case let .refine(parsed) = command else {
            return XCTFail("Expected refine command.")
        }

        XCTAssertEqual(parsed.backend, .whisperCpp)
        XCTAssertEqual(parsed.mode, .raw)
        XCTAssertEqual(parsed.inputText, "hello world")
        XCTAssertEqual(parsed.outputFormat, .text)
        XCTAssertEqual(parsed.outputDestination, .standardOutput)
    }

    func testRefineRejectsMultipleInputSources() {
        XCTAssertThrowsError(try OtoCLIParser.parse(
            arguments: [
                "refine",
                "--text", "hello world",
                "--input", "samples/input.txt"
            ],
            currentDirectoryURL: currentDirectoryURL
        )) { error in
            XCTAssertEqual(
                error as? OtoCLIParseError,
                .usage("refine accepts either --text or --input, but not both.")
            )
        }
    }

    func testTranscribeRejectsWhisperQualityForAppleSpeech() {
        XCTAssertThrowsError(try OtoCLIParser.parse(
            arguments: [
                "transcribe",
                "--quality", "accurate",
                "samples/clip.wav"
            ],
            currentDirectoryURL: currentDirectoryURL
        )) { error in
            XCTAssertEqual(
                error as? OtoCLIParseError,
                .usage("--quality is only supported with the whisper-base model.")
            )
        }
    }
}
