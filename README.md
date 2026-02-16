# Oto

Oto is a macOS menu bar app focused on local speech-to-text (STT).

Current Phase 0.1 foundations include:
- Menu bar app entry point
- Backend switch: Apple Speech / WhisperKit
- Microphone + speech permission actions
- Start/stop recording
- Fn/Globe hotkey control (Hold + Double Tap)
- Timestamped transcript file output

Phase 0.1.1 adds WhisperKit responsiveness work:
- WhisperKit live partial transcript updates while recording
- Launch-time prewarm (best effort)
- Apple Silicon compute tuning with safe fallback
- Latency instrumentation (TTFP, Stop->Final, Total)

## Requirements

- macOS with Xcode installed
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

You only need to regenerate when project structure/settings change in `project.yml`, for example:
- adding/removing dependencies (SPM packages)
- adding new targets/schemes
- changing build settings, bundle identifiers, deployment target
- changing source/resource folder declarations

You do **not** need regeneration for normal code edits:
- editing `.swift` files
- editing logic/UI inside existing files

Recommended flow:

1. Edit Swift code
2. Build/run in Xcode (or with `xcodebuild`)
3. If you changed `project.yml`, run `xcodegen generate` once
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

WhisperKit is integrated as a Swift Package dependency and currently fixed to the `base` model for Phase 0.1.

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

Debug toggles:
- `OTO_ALLOW_WHISPER_DOWNLOAD=1`: Debug-only model download fallback.
- `OTO_DISABLE_WHISPER_STREAMING=1`: disable live streaming and use file finalization.
- `OTO_DISABLE_WHISPER_PREWARM=1`: disable launch prewarm.
- `OTO_DISABLE_WHISPER_COMPUTE_TUNING=1`: disable explicit compute options.

## Transcripts

Transcripts are saved as timestamped `.txt` files in:

- `~/Documents/Oto/Transcripts`

Use the menu action **Open Transcripts Folder** from the app UI.

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

### Debug-only model auto-download (optional)

If you do not have bundled model files yet, you can temporarily enable model download in Debug:

1. Set environment variable `OTO_ALLOW_WHISPER_DOWNLOAD=1` for the app run.
2. Run the app with WhisperKit selected.

Notes:
- This fallback is enabled in `Debug` builds only.
- Release behavior remains bundled-model only.

## Current Development Status

- Phase 0.1 in progress
- Apple Speech path works
- WhisperKit path is integrated and configured for bundled `base` model
- Model asset packaging/verification should be validated with real model files
- Phase 0.1.1 tracking doc: `docs/phase-0.1.1.md`
