# AGENTS.md

This file defines how coding agents should work in this repository.

## Project Intent

Oto is a macOS menu bar app for local speech-to-text.

Current focus is **Phase 0.2**:
- reliable end-to-end flow: activation -> capture -> transcription -> text injection
- Apple Speech + WhisperKit backends in the same state machine
- clear reliability states and recoverable failures
- timestamped transcript output for observability

Reference docs:
- `docs/phase-0.1.md`
- `docs/phase-0.1.1.md`
- `docs/phase-0.2.md`
- `README.md`

## Phase Boundaries (Important)

In Phase 0.2, do not add:
- wake-word activation
- command routing / assistant workflows
- cloud STT fallback
- dynamic backend auto-routing

Keep scope tight and reliability-first.

## Current Technical Decisions

- App type: macOS menu bar app (`LSUIElement`).
- `AppState` is a thin UI adapter; flow orchestration lives in `RecordingFlowCoordinator`.
- Backend switch: Apple Speech / WhisperKit from app menu.
- WhisperKit model: fixed to `base` in this phase.
- Whisper models are bundled by default (no runtime download in release behavior).
- Debug-only opt-in fallback exists with `OTO_ALLOW_WHISPER_DOWNLOAD=1`.
- Hotkey trigger key is `Fn/Globe`, with `Hold` and `Double Tap` modes.
- Reliability transition semantics are reducer-driven (`FlowReducer`) via explicit events.
- Reliability states are user-visible (`Ready`, `Listening`, `Transcribing`, `Injected`, `Failed`).
- Text injection targets focused editable controls and requires Accessibility permission.
- Text injection is async, non-blocking, and restores clipboard when safe.
- Transcript output location: `~/Documents/Oto/Transcripts`.
- Transcript artifacts are split:
  - primary transcript URL
  - failure-context transcript URL
- Structured diagnostics are available via `OtoLogger` categories (`flow`, `speech`, `whisper`, `injection`, `hotkey`, `artifacts`).
- Debug diagnostics can be enabled with:
  - `OTO_DEBUG_LOG_LEVEL=error|info|debug`
  - `OTO_DEBUG_FLOW_TRACE=1`
  - `OTO_DEBUG_UI=1`

## Repository Map

- `project.yml`: source of truth for Xcode project config (XcodeGen).
- `Oto.xcodeproj`: generated file (do not hand-maintain).
- `Oto/`: app source.
- `Oto/Services/RecordingFlowCoordinator.swift`: end-to-end flow orchestrator.
- `Oto/Model/FlowReducer.swift`: state transition reducer.
- `Oto/Model/AppStateProjection.swift`: flow snapshot -> UI projection.
- `Oto/Services/Protocols/ServiceProtocols.swift`: side-effect service protocol seams.
- `Oto/Assets.xcassets`: app/menu bar icons.
- `Oto/Resources/WhisperModels`: bundled Whisper assets.
- `docs/`: phase and architecture docs.

## Required Development Workflow

1. Make code changes in `Oto/` and docs.
2. Run `xcodegen generate` when:
   - `project.yml` changes, or
   - source/resource/test files are added/removed/moved and project file sync is needed.
3. Build with:
   - `xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Debug -destination 'platform=macOS' build`
4. Run tests with:
   - `xcodebuild -project Oto.xcodeproj -scheme Oto -destination 'platform=macOS' test`

Do not regenerate project for normal Swift-only edits.

## Editing Rules

- Prefer modifying `project.yml` rather than hand-editing `.pbxproj`.
- Keep changes small and phase-aligned.
- Preserve local-first behavior and privacy constraints.
- If adding UI, keep menu-bar-first minimal UX.

## Verification Expectations

Before handing off work:
- ensure project builds successfully with `xcodebuild` command above
- ensure unit tests pass with `xcodebuild ... test`
- document any runtime prerequisites (especially Whisper model assets)
- update docs if behavior or workflow changed
- keep failure-context artifacts useful for debugging (do not remove run metadata fields)

## Notes for Agents

If a task requests features beyond Phase 0.2 scope, pause and call it out explicitly before implementing.
