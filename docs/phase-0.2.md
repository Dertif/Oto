# Phase 0.2 – End-to-End Reliability Feel

## Goal
Users should feel reliability through the full path:
activation + capture + transcription + text injection.

## Baseline from Phase 0.1
- Menu bar app entry point
- Model selection (Apple Speech and WhisperKit)
- Bundled Whisper model files
- Permission status + request action in menu bar
- Start/stop recording controls
- Timestamped transcript file output

## Requirements
- Keep the Phase 0.1 foundations and add activation + text injection into the same continuous flow.
- Ensure the user can clearly understand system state at each step (ready, listening, transcribing, injected, failed).
- Make error states recoverable without restarting the app.
- Maintain transcript file output for observability and debugging.

## Out of Scope
- Advanced assistant behaviors
- Complex command routing
- Dynamic multi-backend auto-routing

## Acceptance Criteria
- Starting from idle, the user can complete activation, capture, transcription, and text injection in one uninterrupted flow.
- State transitions are visible and consistent across repeated runs.
- If one step fails, the user gets a clear status and can retry from the menu bar.
- Transcript files continue to be written with timestamps for each run.
- The flow feels reliable in repeated usage, not only in ideal conditions.
