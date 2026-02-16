import Foundation

extension AppleSpeechTranscriber: SpeechTranscribing {}
extension WhisperKitTranscriber: WhisperTranscribing {}
extension AudioFileRecorder: AudioRecording {}
extension TranscriptStore: TranscriptPersisting {}
extension WhisperLatencyTracker: WhisperLatencyTracking {}
