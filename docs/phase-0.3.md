# Phase 0.3 – Injection Reliability and User Control

## Goal
Make text injection dependable across real-world macOS apps while keeping user control over clipboard-impacting behavior.

## Why This Phase
Phase 0.2 proved the end-to-end flow can work, but injection reliability varies by target app/context. This phase hardens injection behavior and makes fallback behavior explicit and configurable.

## Linked Linear Work
- Epic: `REM-35` – `[P0.3 Epic] Injection reliability and user-controlled fallback`
- `REM-37` – deterministic injection strategy chain
- `REM-38` – user setting: allow `Cmd+V` fallback
- `REM-39` – focus stabilization and target detection hardening
- `REM-40` – failure-context diagnostics expansion
- `REM-41` – cross-app injection reliability matrix

## Requirements
- Keep the existing end-to-end flow (activation + capture + transcription + injection) intact.
- Implement multi-strategy injection with deterministic fallback order:
  - `AXInsertText`
  - AX value set (when editable/settable)
  - `Cmd+V` paste fallback
- Make `Cmd+V` fallback explicitly user-configurable.
- Avoid implicit clipboard override:
  - if `Cmd+V` fallback is disabled, clipboard must not be touched by fallback injection.
  - if enabled, preserve/restore clipboard as best effort and surface warning when restore is skipped/failed.
- Improve focus stabilization and target detection before attempting injection.
- Expand failure context artifacts with injection diagnostics (strategy attempted, focused role when available, target app id).
- Keep failure states recoverable without app restart.

## Out of Scope
- Wake-word activation
- Command routing
- Cloud STT fallback
- Dynamic backend auto-routing

## Proposed Settings (User-facing)
- `Auto Inject Transcript` (existing)
- `Allow Cmd+V Fallback` (new)
- `Copy When Auto Inject Off` (existing opt-in)

## Acceptance Criteria
- Injection succeeds reliably in a cross-app matrix (chat apps, notes/docs editors, browser text fields, IDE/editor fields) with a documented pass rate.
- Failure messages are explicit and actionable (permission, no focus, target blocked, event post failure).
- `Cmd+V` fallback can be turned off by users who do not want clipboard-touching fallback behavior.
- With fallback off, no clipboard writes happen from fallback injection attempts.
- With fallback on, clipboard restore behavior is deterministic and warnings are surfaced when restoration is not guaranteed.
- No stuck flow states after injection failure; retry works from menu/hotkey.

## Todo & Progress Tracker
Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.

- [x] Add injection strategy chain with clear ordering and logging.
- [x] Add menu setting for `Allow Cmd+V Fallback`.
- [x] Gate clipboard-touching behavior behind explicit fallback setting.
- [x] Improve focus stabilization heuristics and timeouts.
- [x] Expand failure-context artifact fields for injection diagnostics.
- [~] Build and run cross-app reliability matrix and record results.

## Implemented Behavior Snapshot
- Injection path now uses deterministic strategy order:
  - `AXInsertText` (selected text replacement)
  - AX value set
  - optional `Cmd+V` fallback
- New menu setting: `Allow Cmd+V Fallback (may use clipboard)` (default OFF).
- Clipboard is only touched by the `Cmd+V` fallback strategy.
- Focus stabilization now waits up to `900ms` with `50ms` polling.
- Failure-context artifacts now include:
  - injection strategy chain
  - strategy attempts with outcomes/reasons
  - final strategy
  - focused role/subrole
  - focus wait time
  - preferred/frontmost app metadata

## Automated Validation Evidence
Run on: `2026-02-16`

- `xcodebuild -project Oto.xcodeproj -scheme Oto -destination 'platform=macOS' test`
- Result: **38 tests passed, 0 failed**
- Added/updated coverage includes:
  - strategy order + short-circuit tests
  - `Cmd+V` disabled/allowed behavior tests
  - clipboard usage isolation tests
  - focus stabilization timeout and delayed-focus tests
  - coordinator diagnostics persistence tests
  - coordinator plumbing test for `allowCommandVFallback`

## Cross-App Reliability Matrix (REM-41)
Status legend: `PASS`, `FAIL`, `NOT RUN`

| # | App | Backend | Mode | Result | Notes |
|---|---|---|---|---|---|
| 1 | Slack | Apple Speech | Hold | NOT RUN |  |
| 2 | Slack | Apple Speech | Double Tap | NOT RUN |  |
| 3 | Slack | WhisperKit | Hold | NOT RUN |  |
| 4 | Slack | WhisperKit | Double Tap | NOT RUN |  |
| 5 | Codex app | Apple Speech | Hold | NOT RUN |  |
| 6 | Codex app | Apple Speech | Double Tap | NOT RUN |  |
| 7 | Codex app | WhisperKit | Hold | NOT RUN |  |
| 8 | Codex app | WhisperKit | Double Tap | NOT RUN |  |
| 9 | Telegram | Apple Speech | Hold | NOT RUN |  |
| 10 | Telegram | Apple Speech | Double Tap | NOT RUN |  |
| 11 | Telegram | WhisperKit | Hold | NOT RUN |  |
| 12 | Telegram | WhisperKit | Double Tap | NOT RUN |  |
| 13 | Notes | Apple Speech | Hold | NOT RUN |  |
| 14 | Notes | Apple Speech | Double Tap | NOT RUN |  |
| 15 | Notes | WhisperKit | Hold | NOT RUN |  |
| 16 | Notes | WhisperKit | Double Tap | NOT RUN |  |
| 17 | Browser text field | Apple Speech | Hold | NOT RUN |  |
| 18 | Browser text field | Apple Speech | Double Tap | NOT RUN |  |
| 19 | Browser text field | WhisperKit | Hold | NOT RUN |  |
| 20 | Browser text field | WhisperKit | Double Tap | NOT RUN |  |
| 21 | Xcode/editor field | Apple Speech | Hold | NOT RUN |  |
| 22 | Xcode/editor field | Apple Speech | Double Tap | NOT RUN |  |
| 23 | Xcode/editor field | WhisperKit | Hold | NOT RUN |  |
| 24 | Xcode/editor field | WhisperKit | Double Tap | NOT RUN |  |
