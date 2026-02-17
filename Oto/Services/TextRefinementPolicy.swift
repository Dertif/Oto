import Foundation

struct TextRefinementPolicyResult: Equatable {
    let isAccepted: Bool
    let reason: String?

    static let accepted = TextRefinementPolicyResult(isAccepted: true, reason: nil)

    static func rejected(_ reason: String) -> TextRefinementPolicyResult {
        TextRefinementPolicyResult(isAccepted: false, reason: reason)
    }
}

protocol TextRefinementPolicying {
    func validate(rawText: String, refinedText: String) -> TextRefinementPolicyResult
}

struct TextRefinementPolicy: TextRefinementPolicying {
    func validate(rawText: String, refinedText: String) -> TextRefinementPolicyResult {
        let raw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let refined = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !raw.isEmpty, !refined.isEmpty else {
            return .rejected("guardrail_empty_output")
        }

        let rawNumbers = numberLikeTokens(in: raw)
        let refinedNumbers = numberLikeTokens(in: refined)
        if !rawNumbers.isSubset(of: refinedNumbers) {
            return .rejected("guardrail_numeric_token_mismatch")
        }

        let rawURLs = urlTokens(in: raw)
        let refinedURLs = urlTokens(in: refined)
        if !rawURLs.isSubset(of: refinedURLs) {
            return .rejected("guardrail_url_token_mismatch")
        }

        let rawIdentifiers = identifierTokens(in: raw)
        let refinedIdentifiers = identifierTokens(in: refined)
        if !rawIdentifiers.isSubset(of: refinedIdentifiers) {
            return .rejected("guardrail_identifier_token_mismatch")
        }

        if introducesCommitment(raw: raw, refined: refined) {
            return .rejected("guardrail_commitment_shift")
        }

        return .accepted
    }

    private func numberLikeTokens(in text: String) -> Set<String> {
        tokens(in: text, pattern: #"\b\d[\d.,:/-]*\b"#)
    }

    private func urlTokens(in text: String) -> Set<String> {
        tokens(in: text, pattern: #"\b(?:https?://|www\.)\S+"#)
    }

    private func identifierTokens(in text: String) -> Set<String> {
        let rawTokens = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        return Set(rawTokens.filter { token in
            token.count >= 3 && (
                token.contains("_") ||
                token.contains("/") ||
                token.contains(":") ||
                token.contains(".") ||
                token.contains("-") ||
                token.rangeOfCharacter(from: .decimalDigits) != nil && token.rangeOfCharacter(from: .letters) != nil
            )
        })
    }

    private func introducesCommitment(raw: String, refined: String) -> Bool {
        let normalizedRaw = raw.lowercased()
        let normalizedRefined = refined.lowercased()

        let commitmentPhrases = [
            "i will", "we will", "you should", "must", "guarantee", "definitely"
        ]

        return commitmentPhrases.contains { phrase in
            !normalizedRaw.contains(phrase) && normalizedRefined.contains(phrase)
        }
    }

    private func tokens(in text: String, pattern: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        return Set(matches.map { nsText.substring(with: $0.range) })
    }
}
