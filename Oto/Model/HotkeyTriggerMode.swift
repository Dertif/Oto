import Foundation

enum HotkeyTriggerMode: String, CaseIterable, Identifiable {
    case hold = "Hold"
    case doubleTap = "Double Tap"

    var id: String { rawValue }
}
