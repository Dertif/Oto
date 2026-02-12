import AVFoundation
import Foundation

enum AudioFileRecorderError: LocalizedError {
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            return "Unable to start audio recording."
        }
    }
}

final class AudioFileRecorder {
    private var recorder: AVAudioRecorder?
    private var currentRecordingURL: URL?

    func startRecording() throws -> URL {
        let folderURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("OtoRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let fileURL = folderURL.appendingPathComponent("recording-\(timestamp).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioFileRecorderError.failedToStart
        }

        self.recorder = recorder
        currentRecordingURL = fileURL
        return fileURL
    }

    @discardableResult
    func stopRecording() -> URL? {
        recorder?.stop()
        let fileURL = currentRecordingURL
        recorder = nil
        currentRecordingURL = nil
        return fileURL
    }
}
