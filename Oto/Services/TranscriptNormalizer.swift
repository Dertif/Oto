import Foundation

final class TranscriptNormalizer {
    static let shared = TranscriptNormalizer()

    func normalize(_ rawText: String) -> String {
        let withoutSpecialTokens = rawText.replacingOccurrences(
            of: "<\\|[^|]+\\|>",
            with: " ",
            options: .regularExpression
        )

        let collapsedWhitespace = withoutSpecialTokens.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        let removeSpaceBeforePunctuation = collapsedWhitespace.replacingOccurrences(
            of: "\\s+([,;:!?])",
            with: "$1",
            options: .regularExpression
        )

        let removeSpaceBeforePeriod = removeSpaceBeforePunctuation.replacingOccurrences(
            of: "\\s+\\.",
            with: ".",
            options: .regularExpression
        )

        let ensureSpaceAfterPunctuation = removeSpaceBeforePeriod.replacingOccurrences(
            of: "([,;!?])(\\p{L})",
            with: "$1 $2",
            options: .regularExpression
        )

        let ensureSpaceAfterSentencePeriod = ensureSpaceAfterPunctuation.replacingOccurrences(
            of: "(\\p{Ll})\\.(\\p{Lu})",
            with: "$1. $2",
            options: .regularExpression
        )

        return ensureSpaceAfterSentencePeriod.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
