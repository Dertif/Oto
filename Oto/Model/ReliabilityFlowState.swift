import Foundation

enum ReliabilityFlowState: String {
    case ready = "Ready"
    case listening = "Listening"
    case transcribing = "Transcribing"
    case injected = "Injected"
    case failed = "Failed"
}
