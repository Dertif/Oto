# Phase 0.2 – End-to-End Reliability Feel

## Goal
Users should feel reliability through the full path:
activation + capture + transcription + text injection.

## Baseline from Phase 0.1
- macOS menu bar app entry point
- Model selection (Apple Speech and WhisperKit)
- Bundled Whisper model files with fixed WhisperKit `base` model
- Permission status + request actions in menu bar
- Start/stop recording controls in menu bar
- Recording/processing visual indicator
- `Fn/Globe` hotkey plan with 2 modes:
  - Hold to record (press/hold starts, release stops)
  - Double tap toggle (double tap starts, double tap again stops)
- Timestamped transcript file output

## Requirements
- Keep the Phase 0.1 foundations and add activation + text injection into the same continuous flow.
- Activation must use the selected `Fn/Globe` trigger mode and feed the same capture/transcription pipeline as menu controls.
- Ensure the user can clearly understand system state at each step (ready, listening, transcribing, injected, failed).
- Make error states recoverable without restarting the app.
- Text injection targets the currently focused text field/app and gracefully fails with clear status when injection is not possible.
- Menu bar controls remain available as fallback even when hotkey flow is enabled.
- Maintain transcript file output for observability and debugging.

## Out of Scope
- Advanced assistant behaviors
- Complex command routing
- Dynamic multi-backend auto-routing

## Acceptance Criteria
- Starting from idle, the user can complete activation, capture, transcription, and text injection in one uninterrupted flow.
- This works from both hotkey modes (Hold and Double tap) and via menu fallback controls.
- State transitions are visible and consistent across repeated runs.
- If one step fails, the user gets a clear status and can retry from the menu bar.
- If text injection is unavailable for the target app/context, the failure is explicit and the transcript is still preserved.
- Transcript files continue to be written with timestamps for each run.
- The flow feels reliable in repeated usage, not only in ideal conditions.

## Todo & Progress Tracker (Phase 0.2)
Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.

### 1) Activation
- [x] Implement global `Fn/Globe` handling for Hold mode.
- [x] Implement global `Fn/Globe` handling for Double tap mode.
- [x] Ensure menu controls and hotkey triggers share the same flow/state machine.

### 2) Capture
- [x] Ensure capture starts/stops deterministically from both trigger modes.
- [x] Ensure interrupted/short captures fail gracefully with clear status.

### 3) Transcription
- [x] Ensure transcription is triggered automatically after capture stop in hotkey flows.
- [x] Ensure Apple Speech and WhisperKit both work in the same end-to-end path.
- [x] Preserve transcript files with timestamps for every run (success and recoverable failure context).

### 4) Text Injection
- [x] Inject final transcript into currently focused editable field.
- [x] Surface explicit status when injection target is unavailable/blocked.
- [x] Keep transcript accessible even when injection fails.

### 5) Reliability UX
- [x] Standardize state labels: ready, listening, transcribing, injected, failed.
- [x] Keep recording vs processing indicators visually distinct and consistent.
- [x] Implement retry path from failed states without app restart.

### 6) Validation
- [x] Define repeated test loops across both backends and both trigger modes.
- [~] Run repeated test loops across both backends and both trigger modes.
- [x] Define non-ideal-condition loops (quick retries, permission edge cases, focus changes).
- [~] Execute non-ideal-condition loops and record outcomes.
- [ ] Mark phase complete only when repeated runs are stable end-to-end.

## Implemented Behavior Snapshot
- Activation paths are unified: menu and Fn hotkey trigger the same `startRecording`/`stopRecording` pipeline.
- Capture is deterministic and guarded:
  - processing lock prevents overlapping runs
  - short capture (`< 0.2s`) fails with explicit retry status
- Transcription auto-runs immediately after stop for both Apple Speech and WhisperKit.
- Transcript persistence includes collision-safe filenames and failure-context files.
- Text injection is now explicit and recoverable:
  - uses focused editable target checks
  - surfaces clear failure reasons (permission/focus/non-editable/event failure)
  - keeps transcript artifacts when injection fails
- Reliability states are visible in menu UI: `Ready`, `Listening`, `Transcribing`, `Injected`, `Failed`.

## Automated Validation Evidence
Run on: `2026-02-16`

- Build:
  - `xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Debug -destination 'platform=macOS' build`
- Unit tests:
  - `xcodebuild -project Oto.xcodeproj -scheme Oto -destination 'platform=macOS' test`
- Covered reliability logic:
  - Fn hotkey interpreter (Hold/Double tap, noise, mode switch, processing lock)
  - transcript filename collision avoidance
  - Whisper token sanitization for live/final transcript text
  - editable role validation for text injection target checks
  - Whisper latency tracker metrics accounting

## Phase 0.2 End-to-End Reliability Matrix (REM-34)
Status legend: `PASS`, `FAIL`, `NOT RUN`

| # | Trigger Path | Backend | Injection Context | Scenario | Expected | Result | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Hold | Apple Speech | Available | Happy path | `ready -> listening -> transcribing -> injected` + file saved | NOT RUN |  |
| 2 | Hold | WhisperKit | Available | Happy path | `ready -> listening -> transcribing -> injected` + file saved | NOT RUN |  |
| 3 | Double Tap | Apple Speech | Available | Happy path | Same transitions + file saved | NOT RUN |  |
| 4 | Double Tap | WhisperKit | Available | Happy path | Same transitions + file saved | NOT RUN |  |
| 5 | Menu | Apple Speech | Available | Happy path | Same transitions + file saved | NOT RUN |  |
| 6 | Menu | WhisperKit | Available | Happy path | Same transitions + file saved | NOT RUN |  |
| 7 | Hold | Apple Speech | Blocked target | Injection unavailable | `failed` state with explicit message + file preserved | NOT RUN |  |
| 8 | Hold | WhisperKit | Blocked target | Injection unavailable | `failed` state with explicit message + file preserved | NOT RUN |  |
| 9 | Double Tap | Apple Speech | Focus changed | Focus switch mid-flow | deterministic stop + clear state + file preserved | NOT RUN |  |
| 10 | Double Tap | WhisperKit | Focus changed | Focus switch mid-flow | deterministic stop + clear state + file preserved | NOT RUN |  |
| 11 | Menu | Apple Speech | Available | Short capture (`<0.2s`) | `failed` with short-capture message + retry works | NOT RUN |  |
| 12 | Menu | WhisperKit | Available | Short capture (`<0.2s`) | `failed` with short-capture message + retry works | NOT RUN |  |
| 13 | Hold | Apple Speech | Available | Quick retry after failure | no stuck state, second run succeeds | NOT RUN |  |
| 14 | Hold | WhisperKit | Available | Quick retry after failure | no stuck state, second run succeeds | NOT RUN |  |
| 15 | Menu | Apple Speech | Permission edge | Mic or Speech permission denied | explicit failure + retry after permission grant | NOT RUN |  |
| 16 | Menu | WhisperKit | Permission edge | Accessibility permission missing | explicit injection failure + retry after grant | NOT RUN |  |
