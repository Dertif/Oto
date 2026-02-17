# Phase 0.4 - Dictation Excellence (Latency + Quality)

## Goal
Make Oto feel consistently fast and clean in repeated dictation runs across both backends.

## Linked Linear Work
- Epic: `REM-36` - `[P0.4 Epic] Dictation excellence (latency + quality)`
- `REM-42` - Define latency SLOs and benchmark protocol
- `REM-43` - WhisperKit latency/quality tuning pass
- `REM-44` - Apple Speech terminal error semantics cleanup
- `REM-45` - Transcript normalization consistency pass
- `REM-46` - Add minimal quality presets (`Fast` / `Accurate`)
- `REM-47` - Run repeated latency+quality validation matrix

## Scope
- Latency tracking and aggregation for Apple Speech + WhisperKit.
- Whisper quality presets with stable defaults.
- Apple stop/final semantics cleanup to reduce false terminal failures.
- Shared transcript normalization behavior.

## Out Of Scope
- Wake word
- Assistant routing/commands
- Cloud STT fallback
- Dynamic backend auto-routing

## SLOs (Balanced Profile)
- Whisper P95 `TTFP <= 1.0s`
- Whisper P95 `Stop->Final <= 0.8s`
- Whisper P95 `Total <= 6.0s`
- Apple P95 `Stop->Final <= 0.9s`
- Apple P95 `Total <= 2.5s`

Phase pass gate:
- `>= 90%` success rate on the core matrix
- no blocker issues left open
- deviations documented with follow-up tickets

## Benchmark Protocol (REM-42)
1. Use the same machine and microphone setup for all runs.
2. Use a fixed phrase for each run:
`Hello, this is Oto latency benchmark run. I am testing transcription quality and speed.`
3. Keep target app fixed to `Notes` during benchmark to reduce injection variance.
4. For each run, record:
- backend
- hotkey mode
- TTFP (if available)
- Stop->Final
- Total
- quality note (token artifacts, punctuation, hallucination)
5. Use menu latency summary plus logs as evidence source.

## Validation Matrix (REM-47)
Legend:
- `PASS` = successful run with acceptable transcript quality
- `FAIL` = run failure or major quality issue
- `N/A` = not executed yet

| App | Backend | Hotkey | Run 1 | Run 2 | Run 3 | Run 4 | Run 5 | Notes |
|---|---|---|---|---|---|---|---|---|
| Notes | Apple Speech | Hold | N/A | N/A | N/A | N/A | N/A | Pending manual validation |
| Notes | Apple Speech | Double Tap | N/A | N/A | N/A | N/A | N/A | Pending manual validation |
| Notes | WhisperKit | Hold | N/A | N/A | N/A | N/A | N/A | Pending manual validation |
| Notes | WhisperKit | Double Tap | N/A | N/A | N/A | N/A | N/A | Pending manual validation |

Core matrix extension for cross-app confidence:
- Slack, Codex, Telegram, Browser text field, Xcode editor field
- 1 run each backend/mode cell (tracked in Phase 0.3/0.4 reliability evidence)

## Implementation Status
Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.

- [x] REM-42: SLO definition + benchmark protocol + backend latency recorder.
- [x] REM-43: Whisper tuning presets (`Fast`, `Accurate`) and mapping tests.
- [x] REM-44: Apple terminal error classification cleanup and tests.
- [x] REM-45: shared transcript normalization service + backend integration + tests.
- [x] REM-46: persisted quality preset + menu picker wiring + Whisper-only behavior.
- [~] REM-47: manual matrix execution and evidence capture pending.

## Acceptance Checklist
- [x] Build succeeds on Debug.
- [x] Unit tests pass.
- [x] Backend-aware latency summary is available in menu/debug output.
- [x] Whisper preset is persisted and applied.
- [ ] Manual 20-run matrix complete and documented.
