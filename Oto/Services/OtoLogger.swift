import Foundation
import OSLog

enum OtoLogLevel: Int {
    case error = 0
    case info = 1
    case debug = 2

    var osLogType: OSLogType {
        switch self {
        case .error:
            return .error
        case .info:
            return .info
        case .debug:
            return .debug
        }
    }
}

enum OtoLogCategory: String, CaseIterable {
    case flow
    case speech
    case whisper
    case injection
    case hotkey
    case artifacts
}

enum OtoLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.remi.oto"
    private static let configuredLevel: OtoLogLevel = {
        let raw = ProcessInfo.processInfo.environment["OTO_DEBUG_LOG_LEVEL"]?.lowercased()
        switch raw {
        case "debug":
            return .debug
        case "info":
            return .info
        default:
            return .error
        }
    }()

    static let flowTraceEnabled = envFlag("OTO_DEBUG_FLOW_TRACE")
    static let debugUIPanelEnabled = envFlag("OTO_DEBUG_UI")

    static let assertOnInvalidTransition: Bool = {
#if DEBUG
        !envFlag("OTO_DISABLE_INVALID_TRANSITION_ASSERT")
#else
        false
#endif
    }()

    private static let loggerByCategory: [OtoLogCategory: Logger] = Dictionary(
        uniqueKeysWithValues: OtoLogCategory.allCases.map { category in
            (category, Logger(subsystem: subsystem, category: category.rawValue))
        }
    )

    static var activeDebugFlagsSummary: String {
        var parts: [String] = []
        parts.append("log=\(configuredLevel)")
        parts.append("flowTrace=\(flowTraceEnabled ? "on" : "off")")
        if debugUIPanelEnabled {
            parts.append("debugUI=on")
        }
        if assertOnInvalidTransition {
            parts.append("transitionAssert=on")
        } else {
            parts.append("transitionAssert=off")
        }
        return parts.joined(separator: ", ")
    }

    static func log(_ message: String, category: OtoLogCategory, level: OtoLogLevel = .info) {
        guard shouldLog(level) else {
            return
        }
        logger(for: category).log(level: level.osLogType, "\(message, privacy: .public)")
    }

    static func flowTrace(_ message: String) {
        guard flowTraceEnabled else {
            return
        }
        log(message, category: .flow, level: .debug)
    }

    private static func shouldLog(_ level: OtoLogLevel) -> Bool {
        level.rawValue <= configuredLevel.rawValue
    }

    private static func logger(for category: OtoLogCategory) -> Logger {
        loggerByCategory[category] ?? Logger(subsystem: subsystem, category: category.rawValue)
    }

    private static func envFlag(_ key: String) -> Bool {
        let raw = ProcessInfo.processInfo.environment[key]?.lowercased()
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }
}
