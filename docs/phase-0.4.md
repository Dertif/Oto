# Phase 0.4 – Dictation Excellence (Latency + Quality)

## Goal
Improve perceived speed and transcript quality so Oto feels consistently premium in repeated daily use.

## Why This Phase
After injection reliability hardening (Phase 0.3), the next biggest product feel drivers are latency consistency, final transcript quality, and predictable backend behavior.

## Linked Linear Work
- Epic: `REM-36` – `[P0.4 Epic] Dictation excellence (latency + quality)`
- `REM-42` – latency SLOs and benchmark protocol
- `REM-43` – WhisperKit latency/quality tuning
- `REM-44` – Apple Speech terminal error semantics cleanup
- `REM-45` – transcript normalization consistency
- `REM-46` – minimal quality presets (`Fast` / `Accurate`)
- `REM-47` – repeated latency+quality validation matrix

## Requirements
- Define and track concrete latency metrics in normal usage:
  - time-to-first-partial (TTFP)
  - stop-to-final
  - end-to-end total
- Improve WhisperKit runtime behavior for low-latency, stable partial/final output.
- Improve Apple Speech terminal behavior to reduce false terminal errors after useful transcript output.
- Keep transcript text normalization robust (no control tokens, clean spacing/punctuation behavior).
- Add minimal user-facing quality presets where meaningful (for example `Fast` vs `Accurate`) with fixed safe defaults.
- Preserve phase boundaries: still dictation-focused, not assistant behavior.

## Out of Scope
- Wake-word activation
- Intent parsing and command execution
- Cloud STT fallback
- Dynamic backend auto-routing based on thermal/hardware policy

## Acceptance Criteria
- Latency targets are defined and measured across both backends with repeatable runs.
- WhisperKit partial and final outputs are consistently clean and coherent.
- Apple Speech no longer reports misleading end-state errors when final transcript is valid.
- Quality/latency presets (if enabled) are understandable and stable.
- Reliability remains intact across hotkey modes and menu flow.

## Todo & Progress Tracker
Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.

- [ ] Define latency SLOs and reporting format.
- [ ] Add benchmark script/run sheet and collect baseline for both backends.
- [ ] Tune WhisperKit prewarm/streaming/finalization defaults.
- [ ] Refine Apple Speech terminal error handling semantics.
- [ ] Final transcript cleanup pass (normalization and consistency checks).
- [ ] Optional minimal quality presets with safe defaults.
- [ ] Run repeated validation loops and record results.
