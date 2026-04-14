# Install and Use Oto

Oto is a macOS menu bar app for local speech-to-text. It records from your microphone, transcribes speech with a selected local backend, optionally refines the transcript on device, and can inject the final text into the focused editable field.

## Requirements

- Apple Silicon Mac.
- macOS 26.0 or later.
- Xcode and Xcode command line tools.
- `xcodegen`.
- Microphone, Speech Recognition, and Accessibility permission for the app.
- Bundled WhisperKit model assets in `Oto/Resources/WhisperModels` if you plan to use the WhisperKit backend.

Check local tools:

```bash
xcodebuild -version
xcodegen --version
```

Install XcodeGen with Homebrew if needed:

```bash
brew install xcodegen
```

## Install From Source

Generate the Xcode project:

```bash
xcodegen generate
```

Build a Release app:

```bash
xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Release -destination 'platform=macOS' build
```

Open the built app:

```bash
open "$(ls -dt ~/Library/Developer/Xcode/DerivedData/Oto-*/Build/Products/Release/Oto.app | head -n 1)"
```

For development, you can also open `Oto.xcodeproj` and run the `Oto` scheme from Xcode.

## First Launch

Oto runs as a menu bar app, so it appears in the macOS menu bar instead of the Dock.

On first use, grant the permissions Oto needs:

- Microphone: required to record speech.
- Speech Recognition: required for Apple Speech transcription.
- Accessibility: required to inject text into the focused app.

Use `Advanced Settings...` from the Oto menu, then find `System Access` in the `Settings` section and click `Request Access` for any missing permission. macOS may open System Settings so you can finish granting access.

## Basic Dictation

1. Open the app where you want text to appear and focus an editable text field.
2. Open Oto from the menu bar.
3. Choose a `Backend`.
4. Choose `Refinement`: `Enhanced` for on-device cleanup, or `Raw` for normalized transcription without refinement.
5. Leave `Auto Inject Transcript` enabled if you want Oto to insert the transcript into the focused field.
6. Click `Start Recording`, speak, then click `Stop Recording`.

The recorder status moves through `Ready`, `Listening`, `Transcribing`, and then either `Injected` or `Failed`.

## Fn/Globe Hotkey

Oto uses the `Fn/Globe` key for global recording control.

- `Hold`: hold `Fn/Globe` to record, then release it to stop.
- `Double Tap`: double tap `Fn/Globe` to start recording, then double tap it again to stop.

Change the mode from `Hotkey Mode` in the menu, or from `Advanced Settings...` under `Hotkey`.

If the key does not trigger recording, check macOS keyboard shortcuts that use `Fn/Globe`, and make sure Oto has the permissions listed in `System Access`.

## Backend Choices

Oto supports three local transcription backends:

- `Apple Speech`: uses Apple's speech recognition framework and may prompt for Speech Recognition permission.
- `WhisperKit`: uses the bundled WhisperKit `base` model from `Oto/Resources/WhisperModels`.
- `Whisper.cpp`: uses downloaded ggml models stored in `~/Library/Application Support/Oto/WhisperCppModels`.

The `Quality` picker applies to WhisperKit only:

- `Fast`: lower latency and more responsive partial transcripts.
- `Accurate`: more stable confirmations with higher final quality.

For Whisper.cpp, open `Advanced Settings...`, find `Dictation` in the `Settings` section, select a model, then use `Download Model` if it is not already available locally.

## Refinement

The `Refinement` picker controls the final text Oto uses after transcription:

- `Raw`: use normalized transcript text without on-device refinement.
- `Enhanced`: apply on-device refinement for readability while preserving meaning.

`Enhanced` is designed to be reliable. If refinement is unavailable, times out, errors, or fails meaning-preservation guardrails, Oto falls back to the raw transcript and continues the dictation flow.

## Output and Transcripts

With `Auto Inject Transcript` enabled, Oto injects the final transcript into the focused editable field. The injection path is non-blocking and uses deterministic fallback behavior, including an optional `Cmd+V` fallback controlled by `Allow Cmd+V Fallback (may use clipboard)` in `Advanced Settings...`.

With `Auto Inject Transcript` disabled, Oto saves the transcript without injecting it. Enable `Copy When Auto Inject Off` if you also want Oto to copy the transcript to the clipboard in that mode.

Oto also keeps the latest finalized transcript in a session-only internal clipboard. Press `Ctrl + Cmd + V` to paste it again while the app is running.

Transcript files are saved in:

```text
~/Documents/Oto/Transcripts
```

Open them from `Open Transcripts Folder` in the menu, or browse them in `Advanced Settings...` under `Transcripts`.

For `Enhanced` runs, Oto stores raw and refined artifacts separately when refinement succeeds. Failure-context artifacts are also saved when recoverable failures need debugging context.

## Floating Overlay

The floating overlay gives you a compact always-on recorder control outside fullscreen apps.

Configure it from `Advanced Settings...` under `Settings` > `Floating Overlay`:

- `Show Floating Overlay`: show or hide the overlay.
- `Position`: choose a screen position.
- `Reset Overlay Position`: return the overlay to its default position.

You can click the overlay to start or stop recording, and drag it to a custom position.

## CLI

Oto also includes a CLI target for audio-file transcription and transcript refinement.

Build the CLI:

```bash
xcodebuild -project Oto.xcodeproj -scheme OtoCLI -configuration Debug -destination 'platform=macOS' build
```

Show help:

```bash
"$(ls -dt ~/Library/Developer/Xcode/DerivedData/Oto-*/Build/Products/Debug/oto | head -n 1)" --help
```

Examples:

```bash
oto transcribe --model whisper-base --quality accurate meeting.m4a
oto transcribe --model base.en --format json --output result.json meeting.wav
oto refine --backend whisper --mode enhanced --text "hello team i will send the notes tomorrow"
```

## Troubleshooting

### Oto is not in the Dock

This is expected. Oto is a menu bar app and appears in the macOS menu bar.

### Recording does not start

Open `Advanced Settings...` and check `Settings` > `System Access`. Grant Microphone access, and grant Speech Recognition access if you use Apple Speech.

### Text is not inserted

Grant Accessibility permission to Oto in `Settings` > `System Access`. Also make sure the target app has a focused editable field before you stop recording.

### WhisperKit is unavailable

Check that bundled model assets exist under `Oto/Resources/WhisperModels` before building. Release behavior expects the model to be bundled.

### Whisper.cpp says the model is missing

Open `Advanced Settings...`, find `Settings` > `Dictation`, select the desired Whisper.cpp model, and click `Download Model`.

### Enhanced refinement falls back to raw

This can happen when on-device refinement is unavailable, times out, errors, or changes protected details such as numbers, URLs, identifiers, or commitments. The transcript still completes with raw text.
