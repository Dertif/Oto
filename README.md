# Oto

Oto is a macOS menu bar app focused on local speech-to-text (STT).

Current implemented scope (Phase 0.1 -> 0.5 capability baseline) includes:
- Menu bar app entry point
- Backend switch: Apple Speech / WhisperKit
- Microphone + speech + accessibility permission actions
- Start/stop recording
- Fn/Globe hotkey control (Hold + Double Tap)
- Timestamped transcript file output
- Reliability flow states: Ready / Listening / Transcribing / Injected / Failed
- Optional text injection into focused editable target (toggle in menu)
- Coordinator-driven flow orchestration (state reducer + UI projection)
- WhisperKit live partial transcript updates while recording
- Launch-time prewarm (best effort)
- Apple Silicon compute tuning with safe fallback
- Shared transcript normalization for Apple + Whisper
- Backend latency aggregation (P50/P95 summary in UI)
- Whisper quality presets (`Fast`, `Accurate`) persisted via user settings
- Optional local text refinement modes (`Raw`, `Enhanced`) for both backends
- Deterministic refinement fallback to raw text with soft warning semantics
- Raw/refined transcript artifact split and output-source diagnostics
- Refinement latency aggregation (P50/P95 summary in UI)

## Requirements

- macOS with Xcode installed
- Apple Silicon Mac (arm64 only build target)
- Xcode command line tools (`xcodebuild` available)
- `xcodegen` installed (used to generate `Oto.xcodeproj` from `project.yml`)

Check tools:

```bash
xcodebuild -version
xcodegen --version
```

## Project Structure

- `project.yml`: XcodeGen project definition (single source of truth for project settings)
- `Oto.xcodeproj`: generated project (do not hand-edit long-term)
- `Oto/`: app source code
- `Oto/Assets.xcassets`: app and menu bar icons
- `Oto/Resources/WhisperModels`: bundled Whisper model assets
- `docs/`: phase docs and architecture notes

## Architecture Snapshot

- `Oto/AppState.swift`: thin UI adapter (intents + projection), not backend orchestration owner.
- `Oto/Services/RecordingFlowCoordinator.swift`: end-to-end flow orchestration.
- `Oto/Model/FlowReducer.swift`: deterministic transition logic.
- `Oto/Model/AppStateProjection.swift`: maps flow snapshot to UI-facing state.
- `Oto/Services/Protocols/ServiceProtocols.swift`: protocol seams for side-effecting services.
- `Oto/Services/LatencyMetricsRecorder.swift`: backend latency aggregation + summary formatting.
- `Oto/Services/RefinementLatencyRecorder.swift`: refinement latency aggregation + summary formatting.
- `Oto/Services/TranscriptNormalizer.swift`: shared transcript cleanup rules.
- `Oto/Services/AppleFoundationTextRefiner.swift`: on-device refinement provider.
- `Oto/Services/TextRefinementPolicy.swift`: meaning-preservation guardrails.

## First-Time Setup

1. Generate the Xcode project:

```bash
xcodegen generate
```

2. Build the app:

```bash
xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Debug -destination 'platform=macOS' build
```

3. Open in Xcode:

```bash
open Oto.xcodeproj
```

4. In Xcode, run the `Oto` scheme.

## Common Commands

### Regenerate project from XcodeGen

```bash
xcodegen generate
```

### Build (Debug)

```bash
xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Debug -destination 'platform=macOS' build
```

### Build (Release)

```bash
xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Release -destination 'platform=macOS' build
```

### Clean + build

```bash
xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Debug -destination 'platform=macOS' clean build
```

### Run built app from CLI (after build)

```bash
open "$(ls -dt ~/Library/Developer/Xcode/DerivedData/Oto-*/Build/Products/Debug/Oto.app | head -n 1)"
```

### List schemes/targets

```bash
xcodebuild -list -project Oto.xcodeproj
```

## Tests

Unit tests are configured under the `OtoTests` target.

Run tests:

```bash
xcodebuild -project Oto.xcodeproj -scheme Oto -destination 'platform=macOS' test
```

## XcodeGen Workflow (Important)

Short answer: **No, you do not need to run `xcodegen generate` every time you edit a Swift file.**

You need to regenerate when project structure/settings change in `project.yml`, for example:
- adding/removing dependencies (SPM packages)
- adding new targets/schemes
- changing build settings, bundle identifiers, deployment target
- changing source/resource folder declarations
- adding/removing/moving source/resource/test files when project file sync is needed

You do **not** need regeneration for normal code edits:
- editing `.swift` files
- editing logic/UI inside existing files

Recommended flow:

1. Edit Swift code
2. Build/run in Xcode (or with `xcodebuild`)
3. If you changed `project.yml` or added/removed/moved project files, run `xcodegen generate` once
4. Rebuild

## Icons

Icons are configured in `Oto/Assets.xcassets`:
- `AppIcon.appiconset`: app icon
- `MenuBarIcon.imageset`: default menu bar icon (also used for recording pulse)
- `MenuBarIconProcessing.imageset`: processing state icon

The app is configured to use `AppIcon` via `ASSETCATALOG_COMPILER_APPICON_NAME` in `project.yml`.

If a custom menu bar icon is missing, the app falls back to SF Symbols.

Recording animation note:
- The menu bar icon uses AppKit (`NSStatusItem`) and applies a runtime breathing opacity animation while recording.
- Internal debug speed override is available with `OTO_DEBUG_RECORDING_ANIMATION_SPEED_MULTIPLIER` (for example `1.5`).

## WhisperKit Models (Bundled)

WhisperKit is integrated as a Swift Package dependency and currently fixed to the `base` model for this phase.

Expected location for bundled model assets:
- `Oto/Resources/WhisperModels`

Runtime note:
- Whisper mode requires bundled model artifacts in app resources.
- No runtime model download is intended for this phase.
- Debug-only opt-in fallback is available with `OTO_ALLOW_WHISPER_DOWNLOAD=1`.

Runtime behavior:
- Preferred Whisper path uses live streaming partials while recording.
- If streaming is unavailable, Debug can force file-based finalization mode.
- Prewarm is triggered once on app launch to reduce first-run delay.
- Quality presets:
  - `Fast`: more responsive partials and lower latency defaults.
  - `Accurate`: higher confirmation stability and VAD-enabled defaults.
  - Presets apply to WhisperKit only.
- Refinement modes:
  - `Raw`: bypasses refiner, uses normalized transcript text.
  - `Enhanced`: attempts on-device refinement and falls back to raw on unavailability/timeout/guardrail rejection.

Debug toggles:
- `OTO_ALLOW_WHISPER_DOWNLOAD=1`: Debug-only model download fallback.
- `OTO_DISABLE_WHISPER_STREAMING=1`: disable live streaming and use file finalization.
- `OTO_DISABLE_WHISPER_PREWARM=1`: disable launch prewarm.
- `OTO_DISABLE_WHISPER_COMPUTE_TUNING=1`: disable explicit compute options.
- `OTO_DEBUG_LOG_LEVEL=error|info|debug`: controls structured diagnostics verbosity.
- `OTO_DEBUG_FLOW_TRACE=1`: emits detailed reducer transition traces.
- `OTO_DEBUG_UI=1`: shows debug diagnostics panel in the menu.
- `OTO_DISABLE_INVALID_TRANSITION_ASSERT=1`: disables Debug assertion on invalid reducer transitions.

## Transcripts

Transcripts are saved as timestamped `.txt` files in:

- `~/Documents/Oto/Transcripts`

Use the menu action **Open Transcripts Folder** from the app UI.
Transcript history is also browsable from **Advanced Settings → Transcripts**.

On recoverable failures, Oto also persists a failure-context transcript artifact to keep debugging visibility.
The app tracks two separate artifacts:
- primary transcript artifact (`lastPrimaryTranscriptURL`)
- failure-context artifact (`lastFailureContextURL`)
- raw transcript artifact (`raw-transcript-*`) for enhanced runs
- refined transcript artifact (`refined-transcript-*`) for successful enhanced runs
- failure-context files use the `failure-context-...` filename prefix for quick scanning

Failure-context artifacts include run metadata for easier debugging:
- run id
- backend/phase/last event
- permission snapshot
- hotkey mode + auto-inject setting
- whisper runtime status
- frontmost app bundle id
- refinement mode/availability/latency/fallback reason
- final output source used for injection (`raw` or `refined`)

## Troubleshooting

### `xcodegen` command not found

Install with Homebrew:

```bash
brew install xcodegen
```

### Build fails after changing `project.yml`

Run:

```bash
xcodegen generate
xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Debug -destination 'platform=macOS' build
```

### WhisperKit backend fails at runtime

Check that valid model assets are actually bundled under `Oto/Resources/WhisperModels` and included in the built app resources.

### Text injection fails

If status shows an injection failure:

1. In Oto menu, click **Request Access**.
2. In macOS Settings, grant Accessibility permission to Oto.
3. Retry in an editable text field (for example Notes or a text input in a browser).

Injection behavior notes:
- Injection is async and non-blocking.
- Injection strategy order is deterministic: `AXInsertText -> AX value set -> Cmd+V fallback`.
- `Cmd+V` fallback is user-controlled via **Allow Cmd+V Fallback (may use clipboard)**.
- By default, `Cmd+V` fallback is disabled to protect clipboard expectations.
- Clipboard content is restored after injection when safe.
- If clipboard changes externally during injection, restore is skipped and Oto keeps a warning-level success outcome.
- When auto-inject is disabled, Oto saves transcripts without touching clipboard by default.
- Optional menu toggle `Copy When Auto Inject Off` enables clipboard copy for that mode.

### Debug-only model auto-download (optional)

If you do not have bundled model files yet, you can temporarily enable model download in Debug:

1. Set environment variable `OTO_ALLOW_WHISPER_DOWNLOAD=1` for the app run.
2. Run the app with WhisperKit selected.

Notes:
- This fallback is enabled in `Debug` builds only.
- Release behavior remains bundled-model only.

## Current Development Status

- Phase 0.5 in progress
- Shared hotkey/menu state machine for recording/transcription is implemented
- Reliability states and recoverable failure UX are implemented
- Text injection path includes deterministic strategy chain and user-controlled `Cmd+V` fallback
- Optional local refinement (`Raw`/`Enhanced`) is implemented with deterministic fallback
- Refinement policy, diagnostics, and unit tests are implemented
- Remaining Phase 0.5 work is manual matrix evidence (`docs/phase-0.5.md`)
- Phase 0.1.1 tracking doc: `docs/phase-0.1.1.md`
