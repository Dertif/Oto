# Phase 0.1.1 – WhisperKit Responsiveness and Performance

## Goal
Improve WhisperKit user-perceived responsiveness while staying in local STT scope.

This phase addresses two observed gaps:
- No live/partial transcription while recording (compared to Apple Speech).
- Slower transcription latency, especially first run and post-stop finalization.

## Scope
- In scope:
  - WhisperKit live partial transcription path.
  - WhisperKit performance tuning (prewarm + compute configuration).
  - Validation of reliability and latency for both hotkey modes.
- Out of scope:
  - Wake word
  - Text injection
  - Command routing
  - Cloud STT fallback
  - Automatic backend routing

## Requirements
- Keep current backend switch (Apple Speech / WhisperKit) unchanged.
- Add WhisperKit live partial text updates while recording.
- Keep final transcript generation on stop and timestamped file persistence.
- Keep visual states deterministic (`idle -> recording -> processing -> idle`).
- Add WhisperKit performance optimizations:
  - model prewarm to reduce first-run delay
  - explicit compute options optimized for Apple Silicon
- Add observability for latency:
  - time-to-first-partial
  - stop-to-final-transcript
  - total transcription duration

## Proposed Optimization Defaults (initial)
- Model: `base` (unchanged)
- Prewarm: enabled for WhisperKit path
- Compute options: use Apple Silicon-optimized CoreML compute units
  - mel: GPU-capable
  - audio encoder: Neural Engine preferred when available
  - text decoder: Neural Engine preferred
  - prefill: CPU-only (unless profiling indicates a better choice)

## Acceptance Criteria
- WhisperKit provides partial transcript updates during recording (not only after stop).
- On stop, final transcript is produced and saved as timestamped file.
- No regressions in Hold and Double Tap flows.
- No stuck states in recording/processing during repeated runs.
- Performance shows measurable improvement versus current baseline for:
  - first usable output latency
  - stop-to-final latency
- Reliability remains stable across repeated runs in both hotkey modes.

## Validation Plan
- Functional:
  - Hold mode: start/stop + partial updates + final transcript save
  - Double Tap mode: start/stop + partial updates + final transcript save
- Performance:
  - capture baseline metrics before optimization
  - compare after optimization on same machine/config
- Reliability:
  - repeated runs across WhisperKit + both hotkey modes
  - log failures with repro notes

## Deliverables
- WhisperKit streaming/partial transcription behavior in app UX.
- WhisperKit performance tuning integrated into runtime config.
- Phase report with before/after latency summary and reliability notes.
