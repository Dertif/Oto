# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Oto

macOS menu bar app for local speech-to-text. Apple Silicon only (arm64), macOS 26.0+. Dual STT backends: Apple Speech Framework and WhisperKit. Current focus is Phase 0.5 (optional local text refinement with deterministic fallback).

## Build & Test Commands

```bash
# Regenerate Xcode project (only when project.yml changes or files added/removed/moved)
xcodegen generate

# Build (Debug)
xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Debug -destination 'platform=macOS' build

# Build (Release)
xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Release -destination 'platform=macOS' build

# Run all tests
xcodebuild -project Oto.xcodeproj -scheme Oto -destination 'platform=macOS' test

# Run a single test class
xcodebuild -project Oto.xcodeproj -scheme Oto -destination 'platform=macOS' test -only-testing:OtoTests/FlowReducerTests

# Run a single test method
xcodebuild -project Oto.xcodeproj -scheme Oto -destination 'platform=macOS' test -only-testing:OtoTests/FlowReducerTests/testIdleToListening

# Clean + build
xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Debug -destination 'platform=macOS' clean build
```

No linter or formatter is configured. No CI pipeline.

## Build System

- **XcodeGen**: `project.yml` is the source of truth. Do not hand-edit `Oto.xcodeproj`.
- **SPM dependency**: WhisperKit v0.15.0 (local ML speech recognition).
- Regenerate project only when `project.yml` changes or source/resource/test files are added/removed/moved. Normal Swift edits do not require regeneration.

## Architecture

Unidirectional data flow (reducer-based):

```
User intent (start/stop recording)
  → RecordingFlowCoordinator (orchestrator, owns side effects)
    → FlowReducer (pure, deterministic state transitions)
      → FlowSnapshot (immutable state)
        → AppStateProjection (maps snapshot to UI properties)
          → SwiftUI Views observe via @Published
```

**Flow state machine phases**: `idle → listening → transcribing → refining → injecting → completed` (with `failed` reachable from any active phase).

### Key architectural rules

- **AppState is thin**: UI adapter only (intents + projection). It is NOT the backend orchestrator.
- **RecordingFlowCoordinator owns all flow logic**: transcription, refinement, injection, artifact persistence.
- **FlowReducer is pure**: no side effects, deterministic transitions, validates state invariants.
- **Protocol seams everywhere**: all external services are behind protocols in `Oto/Services/Protocols/ServiceProtocols.swift` for testability.
- **Refinement never blocks completion**: timeout/error/unavailable/guardrail rejection falls back to raw text with soft warning.

### Key files

| File | Role |
|------|------|
| `Oto/OtoApp.swift` | App entry point, AppDelegate, StatusBarController |
| `Oto/AppState.swift` | Thin UI state container |
| `Oto/Services/RecordingFlowCoordinator.swift` | End-to-end flow orchestrator |
| `Oto/Model/FlowReducer.swift` | Deterministic state transition logic |
| `Oto/Model/FlowState.swift` | FlowPhase enum + FlowSnapshot struct |
| `Oto/Model/FlowEvent.swift` | State machine event enum |
| `Oto/Model/AppStateProjection.swift` | Snapshot → UI-facing state mapping |
| `Oto/Services/Protocols/ServiceProtocols.swift` | All service protocol definitions |

## Phase Boundaries

Phase 0.5 scope. Do NOT add:
- Wake-word activation
- Command routing / assistant workflows
- Cloud STT fallback
- Dynamic backend auto-routing
- Multi-style refinement beyond `Raw`/`Enhanced`

If a task requests features beyond this scope, flag it before implementing.

## UI Guidelines

- Menu bar dropdown: status, immediate actions, lightweight config only.
- Separate windows: advanced settings, history, diagnostics.
- Status language: short, neutral, state-only (`Ready`, `Listening`, `Processing…`).
- Native macOS patterns first. Minimal modals. No decorative animation.
- If a task touches UI, read `docs/specs/oto_menu_bar_ui_guidelines.md` before implementing.

## Editing Rules

- Prefer modifying `project.yml` over hand-editing `.pbxproj`.
- Keep changes small and phase-aligned.
- Preserve local-first behavior and privacy constraints.

## Verification

Before handing off:
1. Build succeeds with `xcodebuild ... build`
2. All unit tests pass with `xcodebuild ... test`
3. Update docs if behavior or workflow changed
4. If files were added/removed, run `xcodegen generate` first
