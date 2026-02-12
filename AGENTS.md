# AGENTS.md

This file defines how coding agents should work in this repository.

## Project Intent

Oto is a macOS menu bar app for local speech-to-text.

Current focus is **Phase 0.1**:
- reliable STT foundations
- Apple Speech + WhisperKit backends
- permissions from menu bar
- start/stop recording
- timestamped transcript output

Reference docs:
- `docs/phase-0.1.md`
- `docs/phase-0.2.md`
- `README.md`

## Phase Boundaries (Important)

In Phase 0.1, do not add:
- wake-word activation
- text injection
- command routing / assistant workflows
- cloud STT fallback
- dynamic backend auto-routing

Keep scope tight and reliability-first.

## Current Technical Decisions

- App type: macOS menu bar app (`LSUIElement`).
- Backend switch: Apple Speech / WhisperKit from app menu.
- WhisperKit model: fixed to `base` in this phase.
- Whisper models are bundled by default (no runtime download in release behavior).
- Debug-only opt-in fallback exists with `OTO_ALLOW_WHISPER_DOWNLOAD=1`.
- Transcript output location: `~/Documents/Oto/Transcripts`.

## Repository Map

- `project.yml`: source of truth for Xcode project config (XcodeGen).
- `Oto.xcodeproj`: generated file (do not hand-maintain).
- `Oto/`: app source.
- `Oto/Assets.xcassets`: app/menu bar icons.
- `Oto/Resources/WhisperModels`: bundled Whisper assets.
- `docs/`: phase and architecture docs.

## Required Development Workflow

1. Make code changes in `Oto/` and docs.
2. Run `xcodegen generate` **only when `project.yml` changes** (or when project structure/settings/dependencies change).
3. Build with:
   - `xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Debug -destination 'platform=macOS' build`

Do not regenerate project for normal Swift-only edits.

## Editing Rules

- Prefer modifying `project.yml` rather than hand-editing `.pbxproj`.
- Keep changes small and phase-aligned.
- Preserve local-first behavior and privacy constraints.
- If adding UI, keep menu-bar-first minimal UX.

## Verification Expectations

Before handing off work:
- ensure project builds successfully with `xcodebuild` command above
- document any runtime prerequisites (especially Whisper model assets)
- update docs if behavior or workflow changed

## Notes for Agents

If a task requests features beyond Phase 0.1 scope, pause and call it out explicitly before implementing.
