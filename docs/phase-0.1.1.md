# Phase 0.1.1 – WhisperKit Responsiveness and Performance

## Goal
Improve WhisperKit responsiveness while staying local-first and fully inside STT scope.

## Scope
- In scope:
  - WhisperKit live partial transcription during recording.
  - Launch-time WhisperKit prewarm.
  - Apple Silicon compute tuning with safe fallback.
  - Latency instrumentation and reporting.
  - Light reliability validation across hotkey modes.
- Out of scope:
  - Wake word
  - Text injection
  - Command routing
  - Cloud STT fallback
  - Automatic backend routing

## Linked Linear Work
- `REM-22` Epic: WhisperKit responsiveness and optimization.
- `REM-23`: live partial transcript updates.
- `REM-24`: prewarm and lifecycle.
- `REM-25`: compute tuning.
- `REM-26`: latency instrumentation and report.
- `REM-27`: reliability validation.

## Implementation Status
- [x] `REM-23` Live partial UX implemented with hybrid rendering:
  - confirmed/stable text + lighter live tail while recording.
- [x] `REM-24` Launch prewarm implemented (`prepareWhisperRuntimeForLaunch`).
- [x] `REM-25` Compute tuning implemented with fallback:
  - preferred `ModelComputeOptions` for Apple Silicon.
  - automatic retry without explicit compute options if preferred config fails.
- [x] `REM-26` Latency instrumentation implemented:
  - `TTFP` (time-to-first-partial)
  - `Stop->Final`
  - `Total`
  - surfaced in UI + console.
- [ ] `REM-27` Manual reliability validation complete and recorded.

## Runtime Defaults
- Whisper model: fixed `base`.
- Streaming: enabled by default.
- Prewarm: enabled on app launch (best effort).
- Compute tuning: enabled by default, with runtime fallback to default compute behavior.

## Debug Flags
- `OTO_ALLOW_WHISPER_DOWNLOAD=1`
  - Debug-only fallback if bundled model files are missing.
- `OTO_DISABLE_WHISPER_STREAMING=1`
  - Force file-based Whisper flow (baseline behavior).
- `OTO_DISABLE_WHISPER_PREWARM=1`
  - Disable launch prewarm.
- `OTO_DISABLE_WHISPER_COMPUTE_TUNING=1`
  - Disable explicit compute options.

## Latency Benchmark Sheet
Machine: `TODO`  
Build: `Debug`  
Model: `base`  
Prompt sample: `TODO` (keep fixed across runs)

| Metric | Baseline (streaming/prewarm/compute OFF) | Optimized (default ON) | Delta |
|---|---:|---:|---:|
| Time-to-first-partial (TTFP) | TODO | TODO | TODO |
| Stop->Final | TODO | TODO | TODO |
| Total | TODO | TODO | TODO |

## Light Reliability Validation Sheet (`REM-27`)
Target: 8 successful runs (WhisperKit x 2 hotkey modes x 4 runs each)

| # | Mode | Run | Result | Notes |
|---|---|---|---|---|
| 1 | Hold | 1 |  |  |
| 2 | Hold | 2 |  |  |
| 3 | Hold | 3 |  |  |
| 4 | Hold | 4 |  |  |
| 5 | Double Tap | 1 |  |  |
| 6 | Double Tap | 2 |  |  |
| 7 | Double Tap | 3 |  |  |
| 8 | Double Tap | 4 |  |  |

## Acceptance Criteria
- WhisperKit shows live partial text while recording.
- Stop still produces final transcript and saves timestamped file.
- Hotkey/menu controls remain stable in Hold and Double Tap modes.
- Visual state flow remains deterministic (`idle -> recording -> processing -> idle`).
- Before/after latency table is filled.
- Reliability sheet is filled with no stuck-state failures.
