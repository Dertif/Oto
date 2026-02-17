import AppKit
import Foundation

enum InjectionStrategy: String, CaseIterable, Equatable {
    case axInsertText = "AXInsertText"
    case axSetValue = "AXSetValue"
    case commandV = "Cmd+V"
}

enum InjectionAttemptResult: String, Equatable {
    case success
    case failed
    case skipped
}

struct InjectionAttempt: Equatable {
    let strategy: InjectionStrategy
    let result: InjectionAttemptResult
    let reason: String?
}

struct TextInjectionRequest {
    let text: String
    let preferredApplication: NSRunningApplication?
    let allowCommandVFallback: Bool
}

struct TextInjectionDiagnostics: Equatable {
    let strategyChain: [InjectionStrategy]
    let attempts: [InjectionAttempt]
    let finalStrategy: InjectionStrategy?
    let focusedRole: String?
    let focusedSubrole: String?
    let focusedProcessID: pid_t?
    let focusWaitMilliseconds: Int
    let preferredAppBundleID: String?
    let preferredAppActivated: Bool
    let frontmostAppBundleID: String?
}

struct TextInjectionReport: Equatable {
    let outcome: TextInjectionOutcome?
    let error: TextInjectionError?
    let diagnostics: TextInjectionDiagnostics

    static func success(_ outcome: TextInjectionOutcome, diagnostics: TextInjectionDiagnostics) -> TextInjectionReport {
        TextInjectionReport(outcome: outcome, error: nil, diagnostics: diagnostics)
    }

    static func failure(_ error: TextInjectionError, diagnostics: TextInjectionDiagnostics) -> TextInjectionReport {
        TextInjectionReport(outcome: nil, error: error, diagnostics: diagnostics)
    }
}
