import Foundation

@MainActor
final class GlobalTranscriptPasteShortcutHandler {
    private let clipboard: SessionTranscriptClipboard
    private let pasteService: CommandVPasting

    init(
        clipboard: SessionTranscriptClipboard,
        pasteService: CommandVPasting
    ) {
        self.clipboard = clipboard
        self.pasteService = pasteService
    }

    func handleHotkeyPress() async -> CommandVPasteOutcome {
        let outcome = await pasteService.pasteLatestTranscript(clipboard.latestTranscript)
        switch outcome {
        case .noTranscript:
            OtoLogger.log("Global paste ignored: no session transcript available", category: .hotkey, level: .info)
        case .pasted:
            OtoLogger.log("Global paste succeeded (Ctrl+Cmd+V)", category: .hotkey, level: .info)
        case let .pastedWithWarning(warning):
            OtoLogger.log("Global paste succeeded with warning: \(warning)", category: .hotkey, level: .info)
        case let .copiedOnly(message):
            OtoLogger.log("Global paste fell back to clipboard-only: \(message)", category: .hotkey, level: .info)
        case let .failed(message):
            OtoLogger.log("Global paste failed: \(message)", category: .hotkey, level: .error)
        }
        return outcome
    }
}
