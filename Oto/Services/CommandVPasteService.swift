import Foundation

enum CommandVPasteOutcome: Equatable {
    case noTranscript
    case pasted
    case pastedWithWarning(String)
    case copiedOnly(String)
    case failed(String)
}

@MainActor
protocol CommandVPasting: AnyObject {
    func pasteLatestTranscript(_ transcript: String?) async -> CommandVPasteOutcome
}

@MainActor
final class CommandVPasteService: CommandVPasting {
    private let pasteboard: PasteboardAccessing
    private let postCommandV: () -> Bool
    private let sleepNanos: (UInt64) async -> Void

    init(
        pasteboard: PasteboardAccessing = SystemPasteboard(),
        postCommandV: @escaping () -> Bool = TextInjectionRuntime.live.postCommandV,
        sleepNanos: @escaping (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.pasteboard = pasteboard
        self.postCommandV = postCommandV
        self.sleepNanos = sleepNanos
    }

    func pasteLatestTranscript(_ transcript: String?) async -> CommandVPasteOutcome {
        guard let transcript else {
            return .noTranscript
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .noTranscript
        }

        let backup = pasteboard.snapshot()
        guard pasteboard.setString(trimmed) else {
            return .failed("Unable to copy transcript to clipboard.")
        }
        let injectedChangeCount = pasteboard.changeCount

        guard postCommandV() else {
            return .copiedOnly("Cmd+V event could not be generated; transcript copied to clipboard.")
        }

        await sleepNanos(70_000_000)

        if pasteboard.changeCount != injectedChangeCount {
            return .pastedWithWarning("Clipboard changed during paste; restore skipped.")
        }

        if pasteboard.restore(backup) {
            return .pasted
        }

        return .pastedWithWarning("Transcript pasted, but clipboard restore failed.")
    }
}
