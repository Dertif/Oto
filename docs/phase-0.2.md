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
- [ ] Implement global `Fn/Globe` handling for Hold mode.
- [ ] Implement global `Fn/Globe` handling for Double tap mode.
- [ ] Ensure menu controls and hotkey triggers share the same flow/state machine.

### 2) Capture
- [ ] Ensure capture starts/stops deterministically from both trigger modes.
- [ ] Ensure interrupted/short captures fail gracefully with clear status.

### 3) Transcription
- [ ] Ensure transcription is triggered automatically after capture stop in hotkey flows.
- [ ] Ensure Apple Speech and WhisperKit both work in the same end-to-end path.
- [ ] Preserve transcript files with timestamps for every run (success and recoverable failure context).

### 4) Text Injection
- [ ] Inject final transcript into currently focused editable field.
- [ ] Surface explicit status when injection target is unavailable/blocked.
- [ ] Keep transcript accessible even when injection fails.

### 5) Reliability UX
- [ ] Standardize state labels: ready, listening, transcribing, injected, failed.
- [ ] Keep recording vs processing indicators visually distinct and consistent.
- [ ] Implement retry path from failed states without app restart.

### 6) Validation
- [ ] Define and run repeated test loops across both backends and both trigger modes.
- [ ] Validate reliability in non-ideal conditions (quick retries, permission edge cases, focus changes).
- [ ] Mark phase complete only when repeated runs are stable end-to-end.
