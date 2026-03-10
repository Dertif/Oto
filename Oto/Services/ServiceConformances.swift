import Foundation

extension AppleSpeechTranscriber: SpeechTranscribing {}
extension WhisperKitTranscriber: WhisperTranscribing {}
extension WhisperCppTranscriber: WhisperCppTranscribing {}
extension AudioFileRecorder: AudioRecording {}
extension TranscriptStore: TranscriptPersisting {}
extension WhisperLatencyTracker: WhisperLatencyTracking {}
