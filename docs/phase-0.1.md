# Phase 0.1 – Reliable STT

## Goal
Deliver reliable speech-to-text only, with the minimum macOS foundations needed to validate quality.

## Requirements
- A macOS menu bar app entry point.
- Model selection in the menu bar with Apple Speech and WhisperKit options.
- Whisper model files bundled with the app for this phase.
- WhisperKit uses a fixed bundled `base` model for this phase.
- Permission management in the menu bar that shows current microphone status and provides a request-access action.
- Recording controls in the menu bar with Start recording and Stop recording actions.
- Hotkey trigger support for recording.
- Use a single-key hotkey: `Fn/Globe`.
- Two hotkey trigger modes:
  - Hold to record (record while key is held, stop on release).
  - Double tap to toggle (double tap to start, double tap again to stop).
- Clear visual recording indicator:
  - Recording state is visually obvious at a glance.
  - Processing/transcribing state is visually distinct from recording.
- Persist STT output as timestamped text files.

## Out of Scope
- Wake word activation
- Text injection
- Command handling

## Acceptance Criteria
- The app launches and is accessible from the macOS menu bar.
- The menu bar UI shows microphone permission status and provides a request action.
- The user can switch between Apple Speech and WhisperKit from the menu.
- Whisper is usable without external downloads because model files are bundled.
- WhisperKit runs with the bundled `base` model (no model picker yet).
- The user can start and stop recording from the menu bar.
- `Fn/Globe` is the hotkey used for recording controls.
- The user can trigger recording by hotkey in Hold mode (press/hold starts, release stops).
- The user can trigger recording by hotkey in Double tap mode (double tap starts, double tap again stops).
- The app provides a clear visual indicator for Recording and a distinct indicator for Processing.
- On stop, a transcript file is written with a timestamped filename.
- The phase is considered successful when STT can be repeatedly tested across both models with these controls.

## Status (as of 2026-02-13)
### Done
- [x] macOS menu bar app entry point exists.
- [x] Model selection exists in menu bar (Apple Speech and WhisperKit).
- [x] WhisperKit fixed `base` model setup is in place.
- [x] Menu bar permission UI exists (status + request actions).
- [x] Menu bar Start/Stop recording controls exist.
- [x] Transcripts are persisted as timestamped files.

### Remaining
- [x] Implement global hotkey capture on `Fn/Globe`.
- [x] Implement hotkey mode 1: Hold to record (start on press, stop on release).
- [x] Implement hotkey mode 2: Double tap to toggle start/stop.
- [x] Add clear visual indicator for Recording and distinct indicator for Processing.
- [x] Run final repeated reliability validation across both STT backends with hotkey flows.
- [ ] Improve Recording status indicator to use the same Oto logo with a different color or animation.
- [ ] Improve Processing status indicator to use the same Oto logo with a different color or animation.

## Reliability Run Sheet (24 runs)
Instructions:
- Execute all rows.
- Mark `Result` with `PASS` or `FAIL`.
- Use `Notes` for issues (e.g., missed hotkey, empty transcript, wrong icon state).
- Phase 0.1 reliability is complete when all 24 rows are `PASS`.

| # | Backend | Mode | Run | Result | Notes |
|---|---|---|---|---|---|
| 1 | Apple Speech | Hold | 1 |  |  |
| 2 | Apple Speech | Hold | 2 |  |  |
| 3 | Apple Speech | Hold | 3 |  |  |
| 4 | Apple Speech | Hold | 4 |  |  |
| 5 | Apple Speech | Hold | 5 |  |  |
| 6 | Apple Speech | Hold | 6 |  |  |
| 7 | Apple Speech | Double Tap | 1 |  |  |
| 8 | Apple Speech | Double Tap | 2 |  |  |
| 9 | Apple Speech | Double Tap | 3 |  |  |
| 10 | Apple Speech | Double Tap | 4 |  |  |
| 11 | Apple Speech | Double Tap | 5 |  |  |
| 12 | Apple Speech | Double Tap | 6 |  |  |
| 13 | WhisperKit | Hold | 1 |  |  |
| 14 | WhisperKit | Hold | 2 |  |  |
| 15 | WhisperKit | Hold | 3 |  |  |
| 16 | WhisperKit | Hold | 4 |  |  |
| 17 | WhisperKit | Hold | 5 |  |  |
| 18 | WhisperKit | Hold | 6 |  |  |
| 19 | WhisperKit | Double Tap | 1 |  |  |
| 20 | WhisperKit | Double Tap | 2 |  |  |
| 21 | WhisperKit | Double Tap | 3 |  |  |
| 22 | WhisperKit | Double Tap | 4 |  |  |
| 23 | WhisperKit | Double Tap | 5 |  |  |
| 24 | WhisperKit | Double Tap | 6 |  |  |
