# Oto Floating Overlay UI Spec

**Date:** 2026-02-17  
**Phase Alignment:** Phase 0.5 (local-first reliability)

## 1. Purpose

Provide a compact, always-on overlay for high-frequency dictation actions without expanding Oto into a dashboard surface.

The overlay is additive:
- it does not replace menu bar controls
- it does not change transcription/refinement/injection semantics

## 2. Visibility and Placement

- Overlay is enabled by default and can be toggled in Advanced Settings.
- Overlay appears above normal app windows on all desktop Spaces.
- Overlay is intentionally excluded from fullscreen spaces.
- Initial placement is top-center of the current main screen.
- Overlay is draggable.
- Position is persisted per display and restored on relaunch.
- A reset action restores default top-center placement.

## 3. Interaction Model

- Click behavior:
  - `Idle`/`Hover`: starts recording
  - `Recording`: stops recording
  - `Processing`: ignored
- Drag behavior:
  - Dragging moves overlay without activating app windows.

## 4. Visual States

1. `Idle`
   - minimal presence pill
2. `Hover`
   - hint bubble: `Click or hold fn to start dictating`
3. `Recording`
   - waveform bars reacting to live audio level
4. `Processing`
   - compact loader inside pill
   - no hint bubble

## 5. Audio Reactivity Contract

- Waveform level is normalized to `[0, 1]`.
- Level source priority:
  1. Apple Speech microphone buffer RMS
  2. Whisper streaming buffer energy
  3. Whisper file-capture recorder metering
- Audio level updates are only published while recording/listening.
- Level resets on stop/failure/completion transitions.

## 6. Session Clipboard + Global Paste

- Oto stores the latest finalized transcript in an in-memory session clipboard.
- Global shortcut: `Ctrl + Cmd + V`.
- Shortcut behavior:
  - write latest session transcript to system clipboard
  - synthesize `Cmd+V` paste
  - restore prior clipboard if safe
  - if `Cmd+V` cannot be posted, keep transcript copied for manual paste
- Session clipboard is not persisted to disk.

## 7. Reliability and Scope Guardrails

- No wake-word, command routing, or cloud fallback introduced.
- Existing flow reducer/coordinator remains source of truth.
- Existing menu bar dropdown anatomy remains unchanged.
- Overlay failures (window/hotkey/paste) must be non-blocking and logged.
