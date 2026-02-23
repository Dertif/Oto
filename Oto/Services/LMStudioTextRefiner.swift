import Foundation

private enum LMStudioTextRefinerError: Error {
    case invalidResponse
    case unsuccessfulStatusCode(Int, String?)
    case emptyOutput
}

final class LMStudioTextRefiner: TextRefining {
    static let defaultBaseURLString = "http://127.0.0.1:1234"
    static let defaultModelName = "local-model"
    static let defaultTimeoutSeconds: TimeInterval = 6.0

    typealias RequestExecutor = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private struct ChatCompletionRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let temperature: Double
        let stream: Bool
        let messages: [Message]
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct ErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String?
        }

        let error: APIError?
    }

    var baseURLString: String
    var modelName: String

    private let timeoutSeconds: TimeInterval
    private let nowProvider: () -> Date
    private let requestExecutor: RequestExecutor

    init(
        baseURLString: String = defaultBaseURLString,
        modelName: String = defaultModelName,
        timeoutSeconds: TimeInterval = defaultTimeoutSeconds,
        nowProvider: @escaping () -> Date = Date.init,
        requestExecutor: @escaping RequestExecutor = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LMStudioTextRefinerError.invalidResponse
            }
            return (data, httpResponse)
        }
    ) {
        self.baseURLString = baseURLString
        self.modelName = modelName
        self.timeoutSeconds = timeoutSeconds
        self.nowProvider = nowProvider
        self.requestExecutor = requestExecutor
    }

    var availabilityLabel: String {
        let model = Self.normalizedModelName(from: modelName)
        guard let baseURL = Self.normalizedBaseURL(from: baseURLString) else {
            return "Unavailable: Invalid LM Studio URL"
        }
        return "Configured: \(baseURL.absoluteString) (model: \(model))"
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

        guard let baseURL = Self.normalizedBaseURL(from: baseURLString) else {
            OtoLogger.log(
                "LM Studio refinement unavailable: invalid base URL '\(baseURLString)'",
                category: .flow,
                level: .error
            )
            return .raw(
                text: raw,
                mode: request.mode,
                availability: availabilityLabel,
                fallbackReason: "refiner_lm_studio_invalid_url"
            )
        }

        let startedAt = nowProvider()
        let model = Self.normalizedModelName(from: modelName)
        let availability = "Configured: \(baseURL.absoluteString) (model: \(model))"

        do {
            let refinedText = try await generate(rawText: raw, baseURL: baseURL, model: model)
            let trimmedRefined = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRefined.isEmpty else {
                throw LMStudioTextRefinerError.emptyOutput
            }

            return .refined(
                text: trimmedRefined,
                mode: request.mode,
                availability: availability,
                latency: nowProvider().timeIntervalSince(startedAt)
            )
        } catch {
            let fallbackReason = Self.fallbackReason(for: error)
            OtoLogger.log(
                "LM Studio refinement failed (runID=\(request.runID ?? "unknown"), reason=\(fallbackReason), error=\(error.localizedDescription))",
                category: .flow,
                level: .error
            )
            return .raw(
                text: raw,
                mode: request.mode,
                availability: availability,
                fallbackReason: fallbackReason,
                latency: nowProvider().timeIntervalSince(startedAt)
            )
        }
    }

    private func generate(rawText: String, baseURL: URL, model: String) async throws -> String {
        let endpointURL = Self.refinementEndpoint(for: baseURL)
        let requestBody = ChatCompletionRequest(
            model: model,
            temperature: 0,
            stream: false,
            messages: [
                .init(role: "system", content: Self.instructions),
                .init(role: "user", content: rawText)
            ]
        )

        var request = URLRequest(url: endpointURL)
        request.timeoutInterval = timeoutSeconds
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await requestExecutor(request)
        guard (200 ... 299).contains(response.statusCode) else {
            let message = try? JSONDecoder().decode(ErrorResponse.self, from: data).error?.message
            throw LMStudioTextRefinerError.unsuccessfulStatusCode(response.statusCode, message)
        }

        guard
            let content = try JSONDecoder().decode(ChatCompletionResponse.self, from: data).choices.first?.message.content
        else {
            throw LMStudioTextRefinerError.invalidResponse
        }

        return content
    }

    private static func refinementEndpoint(for baseURL: URL) -> URL {
        let normalizedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath == "v1" || normalizedPath.hasSuffix("/v1") {
            return baseURL.appendingPathComponent("chat", isDirectory: true)
                .appendingPathComponent("completions", isDirectory: false)
        }

        return baseURL.appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("completions", isDirectory: false)
    }

    private static func normalizedModelName(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultModelName : trimmed
    }

    private static func normalizedBaseURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? defaultBaseURLString : trimmed
        let withScheme = candidate.contains("://") ? candidate : "http://\(candidate)"

        guard var components = URLComponents(string: withScheme) else {
            return nil
        }

        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        guard components.host != nil else {
            return nil
        }

        if components.percentEncodedPath == "/" {
            components.percentEncodedPath = ""
        }

        return components.url
    }

    private static func fallbackReason(for error: Error) -> String {
        if let error = error as? LMStudioTextRefinerError {
            switch error {
            case .invalidResponse:
                return "refiner_lm_studio_invalid_response"
            case let .unsuccessfulStatusCode(code, _):
                return "refiner_lm_studio_http_\(code)"
            case .emptyOutput:
                return "refiner_empty_output"
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "refiner_timeout"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost, .notConnectedToInternet:
                return "refiner_lm_studio_unreachable"
            default:
                return "refiner_lm_studio_network_error"
            }
        }

        return "refiner_error: \(error.localizedDescription)"
    }

    private static let instructions = """
    Refine the user's transcript for readability while preserving meaning.
    Requirements:
    - Keep all facts, numbers, dates, URLs, identifiers, and code-like tokens unchanged.
    - Use neutral business tone.
    - Improve punctuation, capitalization, sentence flow, and paragraph structure.
    - Remove filler words and disfluencies only when meaning is preserved.
    - Do not add any new information.
    - Return only the refined text.
    """
}
