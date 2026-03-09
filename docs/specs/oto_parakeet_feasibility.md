# NVIDIA Parakeet Feasibility For Oto

Status: Research note for `REM-60`  
Date: March 9, 2026

## Executive Summary

Integrating NVIDIA Parakeet into Oto is technically possible only through a new non-native runtime layer, not as a small extension of the current Apple Speech or WhisperKit path.

Based on NVIDIA's official docs and model cards, the supported Parakeet paths today are:

- NVIDIA NIM ASR microservices, which officially target Linux and NVIDIA GPUs.
- Python inference through NVIDIA NeMo.
- For `parakeet-ctc-0.6b-en` specifically, Hugging Face Transformers inference is also officially documented.

I did not find an official Swift, Core ML, MLX, or macOS-native deployment path from NVIDIA. Because Oto is a local macOS menu bar app with native Swift backends today, Parakeet is not a good near-term Phase 0.5 backend candidate for shipping. The most realistic path is an experimental local helper process that Oto invokes for file-based transcription, with `parakeet-ctc-0.6b-en` as the first model to spike.

## Primary Sources Consulted

- NVIDIA NIM ASR support matrix:
  - https://docs.nvidia.com/nim/riva/asr/1.7.0/support-matrix.html
- NVIDIA model cards:
  - https://huggingface.co/nvidia/parakeet-ctc-0.6b-en
  - https://huggingface.co/nvidia/parakeet-rnnt-1.1b
  - https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2

## What NVIDIA Officially Supports

### 1. NIM microservice deployment

NVIDIA's NIM ASR support matrix lists:

- Compatible OSes: Linux
- CPU architectures: `x86_64`, `arm64`
- Accelerators: NVIDIA GPUs

That is a poor match for Oto's current target, which is a native Apple Silicon macOS app. This does not look like a viable direct integration path for a local menu bar backend.

### 2. NeMo Python runtime

The RNNT and TDT model cards document loading the models through `nemo.collections.asr.models.ASRModel.from_pretrained(...)`.

Implication:

- The official runtime is Python-based.
- Oto would need to embed or manage an external inference runtime instead of staying fully inside Swift.

### 3. Transformers support for CTC

The `parakeet-ctc-0.6b-en` model card documents direct Hugging Face Transformers usage with:

- `AutoProcessor`
- `AutoModelForCTC`

This is the easiest official entry point for a first spike because it reduces the runtime surface compared with NeMo-specific RNNT/TDT paths. It is still not a native Swift or Core ML path.

## Fit With Oto's Current Architecture

Parakeet does not drop into Oto's current backend seams cleanly.

Current constraints in the app:

- [`Oto/Model/STTBackend.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Model/STTBackend.swift) hardcodes two backend cases.
- [`Oto/AppState.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/AppState.swift) constructs `AppleSpeechTranscriber` and `WhisperKitTranscriber` directly.
- [`Oto/Services/Protocols/ServiceProtocols.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Services/Protocols/ServiceProtocols.swift) exposes two backend-specific protocols instead of one generalized transcription abstraction.
- [`Oto/Services/RecordingFlowCoordinator.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Services/RecordingFlowCoordinator.swift) branches on `.appleSpeech` and `.whisper` and assumes different lifecycle semantics for each.

Implication:

- Adding a third backend is not just "implement a new transcriber".
- Oto would first need a small backend abstraction refactor so a third engine can participate without growing more backend-specific coordinator logic.

## Feasibility Assessment

### Option A. Native in-process Swift backend

Feasibility: Low

Why:

- I found no official NVIDIA path for Swift, Core ML, MLX, or macOS-native packaging.
- Oto currently relies on native Apple frameworks and a Swift package for WhisperKit.
- A custom conversion pipeline would be high risk and would not be grounded in an officially supported NVIDIA deployment path.

Conclusion:

- Not recommended for Phase 0.5.

### Option B. Local helper process on the same Mac

Feasibility: Medium for an experiment, low for a polished product backend

Shape:

- Oto records audio using the existing capture flow.
- Oto shells out to a local helper for final transcription.
- Helper returns transcript text plus error/runtime metadata over stdout, JSON, or IPC.

Pros:

- Stays local-first.
- Avoids GPU/Linux NIM dependency.
- Reuses Oto's existing file-based finalize path patterns.

Cons:

- Adds a Python runtime and packaging burden.
- Harder install/update story than current backends.
- Likely no live streaming partials in the first version.
- Higher cold-start and operational failure surface.

Conclusion:

- This is the only realistic path worth spiking if the goal is "Parakeet on macOS" without abandoning local execution.

### Option C. Local containerized NIM service

Feasibility: Low for Oto

Why:

- Official support is Linux plus NVIDIA GPU.
- It conflicts with Oto's lightweight native-app expectation.
- It changes the product shape from "single local app" to "app plus service stack".

Conclusion:

- Not recommended.

## Recommended Model For A Spike

Start with `nvidia/parakeet-ctc-0.6b-en`.

Why this one first:

- It has an official Transformers inference path in the model card.
- It is simpler to prototype than the NeMo-only RNNT/TDT paths.
- It is better suited to answering the core question: can Parakeet run locally on an Apple Silicon Mac with acceptable latency and packaging cost?

Do not start with RNNT or TDT unless the CTC spike clears the performance and packaging bar.

## Dependencies And Work Required

### Runtime dependencies

- Python runtime management inside or alongside the app
- PyTorch-compatible runtime for local execution
- Hugging Face Transformers for the CTC spike, or NeMo for RNNT/TDT
- Model weight distribution and storage strategy

### Oto codebase dependencies

- Add a third backend case to [`Oto/Model/STTBackend.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Model/STTBackend.swift)
- Replace the current Apple-specific vs Whisper-specific protocol split in [`Oto/Services/Protocols/ServiceProtocols.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Services/Protocols/ServiceProtocols.swift) with a generalized backend abstraction
- Refactor backend branching in [`Oto/Services/RecordingFlowCoordinator.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Services/RecordingFlowCoordinator.swift) so the coordinator asks the backend what capabilities it has instead of hardcoding backend behavior
- Extend [`Oto/AppState.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/AppState.swift) backend construction and menu presentation
- Add runtime status, diagnostics, transcript labeling, latency recording, and artifact metadata for the new backend

### Product and UX dependencies

- Decide whether Parakeet is file-finalize only or must support streaming partials
- Decide whether the backend is hidden behind an experimental flag
- Decide how model assets are downloaded, bundled, or installed
- Decide acceptable disk footprint, memory footprint, and cold-start latency for a menu bar app

## Main Risks

- No official native Apple deployment path found
- Packaging complexity is much higher than Apple Speech or WhisperKit
- Large model/runtime footprint may be out of bounds for a menu bar utility
- First implementation likely loses WhisperKit-style live partials
- More failure states: helper process launch, runtime mismatch, model discovery, Python environment issues

## Recommendation

Recommendation: do not plan Parakeet as a production backend inside Phase 0.5.

If the team wants to continue, treat it as an experimental research spike with a strict go/no-go gate:

1. Build a tiny local helper around `parakeet-ctc-0.6b-en`.
2. Feed it recorded audio files from an Apple Silicon Mac.
3. Measure cold start, stop-to-final latency, memory, CPU, and transcript quality.
4. Only proceed if it runs locally on macOS without Docker, without cloud services, and without an unacceptable packaging story.

## Suggested Spike Deliverable

The next research step should answer these questions before any product integration work starts:

- Can Parakeet produce acceptable dictation quality on Apple Silicon macOS?
- What is the end-to-end stop-to-final latency versus WhisperKit `base`?
- What are the package size and runtime dependency costs?
- Can the runtime be distributed reliably inside a signed macOS app?
- Is lack of native streaming partials acceptable for an experimental backend?

## Bottom Line

Parakeet is interesting, but the official NVIDIA deployment story is currently much closer to Python or Linux GPU infrastructure than to a native Swift macOS app. For Oto, that makes Parakeet a high-friction experimental backend, not a straightforward alternative to Apple Speech or WhisperKit.
