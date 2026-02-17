# AGENTS.md

This file defines how coding agents should work in this repository.

## Project Intent

Oto is a macOS menu bar app for local speech-to-text.

Current focus is **Phase 0.5**:
- optional local text refinement (`Raw` / `Enhanced`)
- deterministic fallback to raw on timeout/error/unavailable/guardrail rejection
- dual-backend support (Apple Speech + WhisperKit) on one deterministic flow
- measurable refinement latency tracking (P50/P95)
- artifact split and diagnostics for raw/refined output source

Reference docs:
- `docs/phase-0.1.md`
- `docs/phase-0.1.1.md`
- `docs/phase-0.2.md`
- `docs/phase-0.5.md`
- `docs/specs/oto_text_refinement_prd.md`
- `docs/specs/oto_menu_bar_ui_guidelines.md` (agent-facing UI guidance)
- `README.md`

## Phase Boundaries (Important)

In Phase 0.5, do not add:
- wake-word activation
- command routing / assistant workflows
- cloud STT fallback
- dynamic backend auto-routing
- multi-style refinement modes beyond `Raw`/`Enhanced`

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
- Backend latency aggregation is handled by `LatencyMetricsRecorder`.
- Refinement latency aggregation is handled by `RefinementLatencyRecorder`.
- Shared cleanup rules are handled by `TranscriptNormalizer`.
- Refinement guardrails are enforced by `TextRefinementPolicy`.
- Refinement provider is `AppleFoundationTextRefiner`.
- Build constraints are enforced in project config:
  - `arm64` only
  - macOS `26.0+`
- Whisper preset defaults:
  - `Fast`: required segments `1`, workers `4`, VAD `off`.
  - `Accurate`: required segments `2`, workers `2`, VAD `on`.
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
2. If a task touches UI, read and apply `docs/specs/oto_menu_bar_ui_guidelines.md` before implementing.
3. Run `xcodegen generate` when:
   - `project.yml` changes, or
   - source/resource/test files are added/removed/moved and project file sync is needed.
4. Build with:
   - `xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Debug -destination 'platform=macOS' build`
5. Run tests with:
   - `xcodebuild -project Oto.xcodeproj -scheme Oto -destination 'platform=macOS' test`

Do not regenerate project for normal Swift-only edits.

## Linear Task Workflow

- For implementation work tied to a Linear issue:
  - move issue status from `Backlog`/`Todo` to `In Progress` before starting changes.
  - move issue status to `Done` only after implementation and validation are complete.
- If work is blocked, keep or move the issue to the appropriate non-done state and add a blocker note/comment.
- For planning/discussion-only work, do not move issue status to `In Progress` or `Done`.

## Editing Rules

- Prefer modifying `project.yml` rather than hand-editing `.pbxproj`.
- Keep changes small and phase-aligned.
- Preserve local-first behavior and privacy constraints.
- If adding UI, keep menu-bar-first minimal UX.

## UI Guidelines for Agents

Use these as implementation guardrails (not feature specs):

- Preserve surface hierarchy:
  - Menu bar dropdown = status, immediate actions, lightweight config.
  - Separate windows = advanced settings, history, diagnostics, logs.
- Keep the dropdown structure stable and vertically grouped:
  - Header, status line, primary actions, secondary config, navigation to windows, system action.
- Keep status language short and neutral:
  - state-only phrasing (`Ready`, `Listening`, `Recording…`, `Processing…`), no coaching or marketing tone.
- Keep primary interactions compact:
  - show about 3–5 high-frequency controls, avoid nested submenus, no explicit Save button for immediate controls.
- Move complexity out of the dropdown:
  - if content becomes scroll-heavy, deeply nested, or low-frequency advanced config, move it to windowed UI.
- Use native macOS patterns first:
  - native controls, predictable keyboard behavior, outside-click/ESC to dismiss dropdown, minimal modal usage.
- Keep icon/motion calm:
  - single monochrome glyph at menu-bar size, subtle state changes only (opacity/small scale/accent), no decorative animation.
- Keep accent color state-driven:
  - use for focus/active/attention only; avoid accent-dominant idle UI.
- Keep motion restrained:
  - system transitions, ~150–250ms ease-in-out for state changes, no bounce effects.
- Avoid scope drift:
  - no dashboard-like menu bar, no chat/assistant-style window UI, no productivity-suite expansion in this phase.

## Verification Expectations

Before handing off work:
- ensure project builds successfully with `xcodebuild` command above
- ensure unit tests pass with `xcodebuild ... test`
- document any runtime prerequisites (especially Whisper model assets)
- update docs if behavior or workflow changed
- keep failure-context artifacts useful for debugging (do not remove run metadata fields)

## Notes for Agents

If a task requests features beyond Phase 0.5 scope, pause and call it out explicitly before implementing.
