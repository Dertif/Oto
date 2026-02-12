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
- On stop, a transcript file is written with a timestamped filename.
- The phase is considered successful when STT can be repeatedly tested across both models with these controls.
