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
    private var meteringTimer: DispatchSourceTimer?
    private var onAudioLevel: ((Float) -> Void)?

    func startRecording(onAudioLevel: @escaping (Float) -> Void) throws -> URL {
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
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioFileRecorderError.failedToStart
        }

        self.recorder = recorder
        currentRecordingURL = fileURL
        self.onAudioLevel = onAudioLevel
        startMetering()
        return fileURL
    }

    @discardableResult
    func stopRecording() -> URL? {
        stopMetering()
        recorder?.stop()
        let fileURL = currentRecordingURL
        recorder = nil
        currentRecordingURL = nil
        onAudioLevel = nil
        return fileURL
    }

    private func startMetering() {
        stopMetering()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.publishMeteredAudioLevel()
        }
        meteringTimer = timer
        timer.resume()
    }

    private func stopMetering() {
        meteringTimer?.setEventHandler {}
        meteringTimer?.cancel()
        meteringTimer = nil
    }

    private func publishMeteredAudioLevel() {
        guard let recorder else {
            return
        }

        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let normalized = min(1, max(0, (db + 52) / 52))
        onAudioLevel?(normalized)
    }
}
