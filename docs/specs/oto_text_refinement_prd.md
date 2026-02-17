# Oto - Text Refinement PRD (Phase 0.5)

Product: Oto
Feature: Optional Local Text Refinement
Platform: macOS 26+ (Apple Silicon only)
Status: v1

## 1) Context
Oto already supports local STT through Apple Speech and WhisperKit. Phase 0.5 adds a post-transcription refinement step to improve readability while preserving meaning and reliability.

## 2) Locked Product Decisions
1. Refinement applies to both Apple Speech and WhisperKit outputs.
2. Two modes only in Phase 0.5:
   - `Raw`
   - `Enhanced`
3. Default mode is `Enhanced`.
4. Local-only processing (no cloud path in this phase).
5. Refinement failure/timeout/unavailable/guardrail violation never blocks dictation.
6. Persist separate artifacts when mode is `Enhanced`:
   - `raw-transcript-*`
   - `refined-transcript-*` (success only)
7. Track and surface final output source used for injection: `raw` or `refined`.
8. UI redesign is out of scope; capability exposure stays minimal.

## 3) Problem Statement
Raw STT can be readable enough for quick notes but still needs manual cleanup for punctuation and flow. Users want a cleaner transcript without losing facts, numbers, links, identifiers, or intent.

## 4) Goals
### Functional
1. Improve readability via `Enhanced` refinement.
2. Preserve semantic fidelity and critical tokens.
3. Keep behavior deterministic and observable.
4. Maintain completion reliability under all refinement outcomes.

### Non-goals
1. Assistant behavior or command routing.
2. Cloud refinement fallback.
3. Multi-style/tone presets beyond `Enhanced`.

## 5) User Modes
### Raw
- Output uses normalized transcript text only.
- Refiner is bypassed.

### Enhanced
- Uses on-device refinement aimed at neutral business readability.
- Improves punctuation/capitalization/flow while preserving meaning.
- If refinement is unavailable or rejected, fallback to raw with soft warning.

## 6) Guardrails (Meaning Preservation)
Reject refined output and fallback to raw when any of these invariants fail:
1. Numeric token preservation.
2. URL token preservation.
3. Identifier/code-like token preservation.
4. Commitment shift detection (e.g., newly introduced commitments).

Fallback reason is recorded as diagnostic (`guardrail_*`).

## 7) Technical Design
### Flow placement
`listening -> transcribing -> refining -> injecting -> completed/failed`

### Core interfaces
- `TextRefining`
- `TextRefinementRequest`
- `TextRefinementResult`
- `TextRefinementDiagnostics`
- `TextRefinementPolicy`

### Provider
- `AppleFoundationTextRefiner` (availability-gated, on-device only)

### Fallback behavior
If `Enhanced` is selected and refinement does not produce accepted output:
1. Continue with raw transcript.
2. Emit soft warning in status.
3. Persist diagnostics and output source.

## 8) Performance and Reliability
### SLO
- Enhanced refinement latency P95: `<= 1.4s`.

### Reliability
1. No stuck `refining` state.
2. Retry-safe after fallback or failure.
3. Injection path uses whichever output source is active (`raw` or `refined`).

## 9) Artifacts and Observability
### Persistence
- Mode `Raw`: standard primary transcript artifact.
- Mode `Enhanced`:
  - always persist `raw-transcript-*`
  - persist `refined-transcript-*` only when refinement succeeds
- Failure/injection diagnostics continue to use `failure-context-*`.

### Diagnostics fields
1. refinement mode
2. refinement availability
3. refinement latency
4. fallback reason
5. output source
6. backend + run linkage

## 10) Validation Plan
### Unit tests
1. Flow reducer transitions with `refining`.
2. Coordinator enhanced success + fallback paths.
3. Guardrail policy invariants.
4. Refiner availability/timeout/guardrail behavior.
5. Artifact prefix behavior.
6. Projection mapping for refining/output source.

### Manual matrix
24 runs total:
- backends: Apple Speech, WhisperKit
- refinement modes: Raw, Enhanced
- hotkey modes: Hold, Double Tap
- 3 runs per cell

Capture:
1. success/failure
2. output source
3. refinement latency
4. fallback reason (if any)
5. quality note

## 11) Delivery Boundaries
Phase 0.5 delivers capability + reliability + observability for optional local refinement. Visual UX overhaul is deferred.
