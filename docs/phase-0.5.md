# Phase 0.5 - Local Text Refinement

## Goal
Add optional on-device transcript refinement with deterministic fallback so dictation remains reliable for both Apple Speech and WhisperKit.

## Source PRD
- `/Users/remi.bouchez/Documents/Oto/docs/specs/oto_text_refinement_prd.md` (v1)

## Locked Decisions
1. Two modes only: `Raw`, `Enhanced`.
2. Default mode is `Enhanced`.
3. Refinement is optional and never blocks dictation completion.
4. On timeout/error/unavailable/guardrail violation: fallback to raw with a soft warning.
5. Persist distinct artifacts when refinement mode is `Enhanced`:
   - `raw-transcript-*`
   - `refined-transcript-*` (only when refinement succeeds)
6. Track final output source (`raw` or `refined`) for diagnostics.
7. Platform constraint is enforced in build config: Apple Silicon (`arm64`) + macOS 26+.
8. Enhanced refinement latency SLO target: P95 <= `1.4s`.
9. Manual validation depth: `24 runs` (`2 backends x 2 refinement modes x 2 hotkey modes x 3 runs`).

## Linked Linear Work
- Epic: `REM-48`
- `REM-49` flow integration (`refining` phase)
- `REM-50` refinement protocol + models + provider
- `REM-51` deterministic fallback behavior
- `REM-52` guardrail policy
- `REM-53` refinement latency metrics + summaries
- `REM-54` artifact split + output source wiring
- `REM-55` diagnostics expansion
- `REM-56` unit tests
- `REM-57` manual matrix + evidence
- `REM-58` arm64/macOS constraints in project config

## Progress Tracker
Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.

- [x] Add `refining` flow phase and reducer transitions.
- [x] Add `TextRefining` protocol + refinement request/result models.
- [x] Integrate refinement orchestration into coordinator.
- [x] Implement deterministic fallback to raw on timeout/error/unavailable.
- [x] Add refinement latency metrics recorder and summary output.
- [x] Persist raw and refined artifacts with output-source tracking.
- [x] Extend failure/debug diagnostics with refinement fields.
- [x] Add unit tests (policy, flow, fallback, artifacts, refiner).
- [~] Execute manual validation matrix and capture evidence.
- [x] Enforce Apple Silicon + minimum macOS version in project config.

## Validation Matrix (Template)
Legend: `PASS`, `FAIL`, `NOT RUN`

| Backend | Refinement Mode | Hotkey | Run 1 | Run 2 | Run 3 | Notes |
|---|---|---|---|---|---|---|
| Apple Speech | Raw | Hold | NOT RUN | NOT RUN | NOT RUN |  |
| Apple Speech | Raw | Double Tap | NOT RUN | NOT RUN | NOT RUN |  |
| Apple Speech | Enhanced | Hold | NOT RUN | NOT RUN | NOT RUN |  |
| Apple Speech | Enhanced | Double Tap | NOT RUN | NOT RUN | NOT RUN |  |
| WhisperKit | Raw | Hold | NOT RUN | NOT RUN | NOT RUN |  |
| WhisperKit | Raw | Double Tap | NOT RUN | NOT RUN | NOT RUN |  |
| WhisperKit | Enhanced | Hold | NOT RUN | NOT RUN | NOT RUN |  |
| WhisperKit | Enhanced | Double Tap | NOT RUN | NOT RUN | NOT RUN |  |

## Completion Gate
1. `REM-49..REM-56` and `REM-58` are done.
2. Matrix success rate is >= 90% with no blocker failures.
3. SLO result is documented with P95 values and pass/fail rationale.
4. Any blocker failures have linked follow-up Linear issues.
