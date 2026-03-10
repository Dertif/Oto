import Foundation

enum OtoCLIOutputFormat: String, Equatable {
    case text
    case json

    static func parse(_ rawValue: String) -> OtoCLIOutputFormat? {
        OtoCLIOutputFormat(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

enum OtoCLIOutputDestination: Equatable {
    case standardOutput
    case file(URL)
}

struct OtoCLITranscribeCommand: Equatable {
    let audioFileURL: URL
    let model: AudioFileTranscriptionModel
    let qualityPreset: DictationQualityPreset
    let outputFormat: OtoCLIOutputFormat
    let outputDestination: OtoCLIOutputDestination
}

struct OtoCLIRefineCommand: Equatable {
    let backend: STTBackend
    let mode: TextRefinementMode
    let inputText: String
    let outputFormat: OtoCLIOutputFormat
    let outputDestination: OtoCLIOutputDestination
}

enum OtoCLICommand: Equatable {
    case transcribe(OtoCLITranscribeCommand)
    case refine(OtoCLIRefineCommand)
}

enum OtoCLIParseError: LocalizedError, Equatable {
    case helpRequested
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .helpRequested:
            return nil
        case let .usage(message):
            return message
        }
    }
}

enum OtoCLIParser {
    static let usageText = """
    Oto CLI

    Usage:
      oto <command> [options]

    Commands:
      transcribe    Transcribe an audio file to text.
      refine        Refine transcript text with Oto's on-device formatter.
      format        Alias for refine.
      help          Show this help text.

    transcribe options:
      --model <apple-speech|whisper-base|tiny.en|base.en|base|small.en|small>
                                      Select the transcription model. Default: apple-speech
      --quality <fast|accurate>       WhisperKit quality preset. Default: fast
      --format <text|json>            Output format. Default: text
      --output <path|->               Write to a file or stdout (`-`). Default: -
      <audio-file>                    Audio file to transcribe

    refine options:
      --backend <apple-speech|whisper|whisper-cpp>
                                      Source backend for diagnostics. Default: apple-speech
      --mode <raw|enhanced>           Refinement mode. Default: enhanced
      --text <value>                  Transcript text to refine
      --input <path>                  Read transcript text from a file
      --format <text|json>            Output format. Default: text
      --output <path|->               Write to a file or stdout (`-`). Default: -

    Notes:
      - `whisper-base` uses Oto's bundled WhisperKit base model.
      - whisper.cpp models must already exist locally in ~/Library/Application Support/Oto/WhisperCppModels.
      - Apple Speech may request Speech Recognition permission on first use.
    """

    static func parse(
        arguments: [String],
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) throws -> OtoCLICommand {
        guard let command = arguments.first else {
            throw OtoCLIParseError.helpRequested
        }

        switch command.lowercased() {
        case "help", "--help", "-h":
            throw OtoCLIParseError.helpRequested
        case "transcribe":
            return .transcribe(try parseTranscribe(arguments: Array(arguments.dropFirst()), currentDirectoryURL: currentDirectoryURL))
        case "refine", "format":
            return .refine(try parseRefine(arguments: Array(arguments.dropFirst()), currentDirectoryURL: currentDirectoryURL))
        default:
            throw OtoCLIParseError.usage("Unknown command '\(command)'.\n\n\(usageText)")
        }
    }

    private static func parseTranscribe(
        arguments: [String],
        currentDirectoryURL: URL
    ) throws -> OtoCLITranscribeCommand {
        var model: AudioFileTranscriptionModel = .appleSpeech
        var qualityPreset: DictationQualityPreset = .fast
        var qualityWasExplicitlySet = false
        var outputFormat: OtoCLIOutputFormat = .text
        var outputDestination: OtoCLIOutputDestination = .standardOutput
        var audioFileURL: URL?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                throw OtoCLIParseError.helpRequested
            case "--model":
                let rawValue = try value(after: argument, in: arguments, index: &index)
                guard let parsedModel = AudioFileTranscriptionModel.parse(rawValue) else {
                    throw OtoCLIParseError.usage("Unsupported model '\(rawValue)'. Expected apple-speech, whisper-base, or a whisper.cpp model.")
                }
                model = parsedModel
            case "--quality":
                let rawValue = try value(after: argument, in: arguments, index: &index)
                guard let parsedPreset = parseQualityPreset(rawValue) else {
                    throw OtoCLIParseError.usage("Unsupported quality preset '\(rawValue)'. Expected fast or accurate.")
                }
                qualityPreset = parsedPreset
                qualityWasExplicitlySet = true
            case "--format":
                let rawValue = try value(after: argument, in: arguments, index: &index)
                guard let parsedFormat = OtoCLIOutputFormat.parse(rawValue) else {
                    throw OtoCLIParseError.usage("Unsupported output format '\(rawValue)'. Expected text or json.")
                }
                outputFormat = parsedFormat
            case "--output":
                let rawValue = try value(after: argument, in: arguments, index: &index)
                outputDestination = parseOutputDestination(rawValue, currentDirectoryURL: currentDirectoryURL)
            default:
                if argument.hasPrefix("-") {
                    throw OtoCLIParseError.usage("Unknown option '\(argument)' for transcribe.")
                }
                guard audioFileURL == nil else {
                    throw OtoCLIParseError.usage("transcribe accepts exactly one audio file path.")
                }
                audioFileURL = resolvePath(argument, currentDirectoryURL: currentDirectoryURL)
            }
            index += 1
        }

        guard let audioFileURL else {
            throw OtoCLIParseError.usage("transcribe requires an audio file path.")
        }

        if qualityWasExplicitlySet, !model.supportsQualityPreset {
            throw OtoCLIParseError.usage("--quality is only supported with the whisper-base model.")
        }

        return OtoCLITranscribeCommand(
            audioFileURL: audioFileURL,
            model: model,
            qualityPreset: qualityPreset,
            outputFormat: outputFormat,
            outputDestination: outputDestination
        )
    }

    private static func parseRefine(
        arguments: [String],
        currentDirectoryURL: URL
    ) throws -> OtoCLIRefineCommand {
        var backend: STTBackend = .appleSpeech
        var mode: TextRefinementMode = .enhanced
        var outputFormat: OtoCLIOutputFormat = .text
        var outputDestination: OtoCLIOutputDestination = .standardOutput
        var inlineText: String?
        var inputFileURL: URL?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                throw OtoCLIParseError.helpRequested
            case "--backend", "--model":
                let rawValue = try value(after: argument, in: arguments, index: &index)
                guard let parsedBackend = parseBackend(rawValue) else {
                    throw OtoCLIParseError.usage("Unsupported backend '\(rawValue)'. Expected apple-speech, whisper, or whisper-cpp.")
                }
                backend = parsedBackend
            case "--mode":
                let rawValue = try value(after: argument, in: arguments, index: &index)
                guard let parsedMode = parseRefinementMode(rawValue) else {
                    throw OtoCLIParseError.usage("Unsupported refinement mode '\(rawValue)'. Expected raw or enhanced.")
                }
                mode = parsedMode
            case "--format":
                let rawValue = try value(after: argument, in: arguments, index: &index)
                guard let parsedFormat = OtoCLIOutputFormat.parse(rawValue) else {
                    throw OtoCLIParseError.usage("Unsupported output format '\(rawValue)'. Expected text or json.")
                }
                outputFormat = parsedFormat
            case "--output":
                let rawValue = try value(after: argument, in: arguments, index: &index)
                outputDestination = parseOutputDestination(rawValue, currentDirectoryURL: currentDirectoryURL)
            case "--text":
                inlineText = try value(after: argument, in: arguments, index: &index)
            case "--input":
                let rawValue = try value(after: argument, in: arguments, index: &index)
                inputFileURL = resolvePath(rawValue, currentDirectoryURL: currentDirectoryURL)
            default:
                throw OtoCLIParseError.usage("Unknown option '\(argument)' for refine.")
            }
            index += 1
        }

        if inlineText != nil, inputFileURL != nil {
            throw OtoCLIParseError.usage("refine accepts either --text or --input, but not both.")
        }

        let inputText: String
        if let inlineText {
            inputText = inlineText
        } else if let inputFileURL {
            inputText = try String(contentsOf: inputFileURL, encoding: .utf8)
        } else {
            throw OtoCLIParseError.usage("refine requires --text or --input.")
        }

        return OtoCLIRefineCommand(
            backend: backend,
            mode: mode,
            inputText: inputText,
            outputFormat: outputFormat,
            outputDestination: outputDestination
        )
    }

    private static func value(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> String {
        let nextIndex = index + 1
        guard nextIndex < arguments.count else {
            throw OtoCLIParseError.usage("Missing value for \(option).")
        }
        index = nextIndex
        return arguments[nextIndex]
    }

    private static func parseBackend(_ rawValue: String) -> STTBackend? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "apple", "apple-speech", "speech":
            return .appleSpeech
        case "whisper", "whisper-base", "whisperkit":
            return .whisper
        case "whisper-cpp", "whispercpp", "tiny.en", "base.en", "base", "small.en", "small":
            return .whisperCpp
        default:
            return nil
        }
    }

    private static func parseRefinementMode(_ rawValue: String) -> TextRefinementMode? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "raw":
            return .raw
        case "enhanced":
            return .enhanced
        default:
            return nil
        }
    }

    private static func parseQualityPreset(_ rawValue: String) -> DictationQualityPreset? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "fast":
            return .fast
        case "accurate":
            return .accurate
        default:
            return nil
        }
    }

    private static func parseOutputDestination(
        _ rawValue: String,
        currentDirectoryURL: URL
    ) -> OtoCLIOutputDestination {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "-" || normalized.lowercased() == "stdout" {
            return .standardOutput
        }
        return .file(resolvePath(normalized, currentDirectoryURL: currentDirectoryURL))
    }

    private static func resolvePath(_ rawValue: String, currentDirectoryURL: URL) -> URL {
        let path = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return URL(fileURLWithPath: path, relativeTo: currentDirectoryURL).standardizedFileURL
    }
}

private struct OtoCLITranscriptionOutput: Encodable {
    let audioFilePath: String
    let backend: String
    let model: String
    let qualityPreset: String?
    let text: String
}

private struct OtoCLIRefinementOutput: Encodable {
    let backend: String
    let mode: String
    let text: String
    let outputSource: String
    let diagnostics: OtoCLIRefinementDiagnosticsOutput
}

private struct OtoCLIRefinementDiagnosticsOutput: Encodable {
    let availability: String
    let fallbackReason: String?
    let latencyMilliseconds: Int?
}

enum OtoCLIRunner {
    @MainActor
    static func run(arguments: [String]) async -> Int32 {
        do {
            let command = try OtoCLIParser.parse(arguments: arguments)
            try await execute(command)
            return 0
        } catch OtoCLIParseError.helpRequested {
            write(OtoCLIParser.usageText, to: .standardOutput)
            return 0
        } catch let error as OtoCLIParseError {
            write(error.errorDescription ?? "Invalid command.", to: .standardError)
            return 64
        } catch {
            write(error.localizedDescription, to: .standardError)
            return 1
        }
    }

    @MainActor
    private static func execute(_ command: OtoCLICommand) async throws {
        switch command {
        case let .transcribe(command):
            try await executeTranscribe(command)
        case let .refine(command):
            try await executeRefine(command)
        }
    }

    @MainActor
    private static func executeTranscribe(_ command: OtoCLITranscribeCommand) async throws {
        guard FileManager.default.fileExists(atPath: command.audioFileURL.path) else {
            throw NSError(
                domain: "OtoCLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Audio file not found at \(command.audioFileURL.path)."]
            )
        }

        let transcriptionService = AudioFileTranscriptionService()
        let result = try await transcriptionService.transcribe(
            audioFileURL: command.audioFileURL,
            model: command.model,
            qualityPreset: command.qualityPreset
        )

        switch command.outputFormat {
        case .text:
            try writePayload(result.text, to: command.outputDestination)
        case .json:
            let payload = OtoCLITranscriptionOutput(
                audioFilePath: command.audioFileURL.path,
                backend: result.backend.rawValue,
                model: result.model.cliValue,
                qualityPreset: result.qualityPreset?.rawValue,
                text: result.text
            )
            try writeJSONPayload(payload, to: command.outputDestination)
        }
    }

    @MainActor
    private static func executeRefine(_ command: OtoCLIRefineCommand) async throws {
        let normalizedInput = TranscriptNormalizer.shared.normalize(command.inputText)
        let refiner = AppleFoundationTextRefiner()
        let result = await refiner.refine(request: TextRefinementRequest(
            backend: command.backend,
            mode: command.mode,
            rawText: normalizedInput,
            runID: UUID().uuidString
        ))

        if
            command.mode == .enhanced,
            result.outputSource == .raw,
            let fallbackReason = result.diagnostics.fallbackReason,
            fallbackReason != "refinement_mode_raw"
        {
            write("Refinement fallback: \(fallbackReason). Using raw transcript.", to: .standardError)
        }

        switch command.outputFormat {
        case .text:
            try writePayload(result.text, to: command.outputDestination)
        case .json:
            let latencyMilliseconds = result.diagnostics.latency.map { Int(($0 * 1_000).rounded()) }
            let payload = OtoCLIRefinementOutput(
                backend: command.backend.rawValue,
                mode: command.mode.rawValue,
                text: result.text,
                outputSource: result.outputSource.rawValue,
                diagnostics: OtoCLIRefinementDiagnosticsOutput(
                    availability: result.diagnostics.availability,
                    fallbackReason: result.diagnostics.fallbackReason,
                    latencyMilliseconds: latencyMilliseconds
                )
            )
            try writeJSONPayload(payload, to: command.outputDestination)
        }
    }

    private static func writePayload(
        _ text: String,
        to destination: OtoCLIOutputDestination
    ) throws {
        let output = text.hasSuffix("\n") ? text : text + "\n"
        let data = Data(output.utf8)
        try writeData(data, to: destination)
    }

    private static func writeJSONPayload<T: Encodable>(
        _ payload: T,
        to destination: OtoCLIOutputDestination
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(payload)
        let data = jsonData + Data("\n".utf8)
        try writeData(data, to: destination)
    }

    private static func writeData(
        _ data: Data,
        to destination: OtoCLIOutputDestination
    ) throws {
        switch destination {
        case .standardOutput:
            FileHandle.standardOutput.write(data)
        case let .file(url):
            let folderURL = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    private static func write(_ message: String, to handle: OtoCLIStreamHandle) {
        let normalized = message.hasSuffix("\n") ? message : message + "\n"
        let data = Data(normalized.utf8)
        switch handle {
        case .standardOutput:
            FileHandle.standardOutput.write(data)
        case .standardError:
            FileHandle.standardError.write(data)
        }
    }
}

private enum OtoCLIStreamHandle {
    case standardOutput
    case standardError
}
