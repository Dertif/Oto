# NVIDIA Parakeet Feasibility For Oto

Status: Research note for `REM-60`  
Date: March 9, 2026  
Verification date for external sources: March 9, 2026

## Executive Summary

Integrating NVIDIA Parakeet into Oto is technically plausible, but not as a native Swift backend comparable to Apple Speech or WhisperKit.

Based on current official NVIDIA and PyTorch sources, Parakeet is supported today through:

- NVIDIA Riva ASR NIM, which targets Linux or Windows via WSL2 and requires an NVIDIA GPU plus container runtime.
- Python inference through NVIDIA NeMo.
- For `nvidia/parakeet-ctc-0.6b`, an officially documented Hugging Face Transformers path in addition to NeMo.

I did not find an official NVIDIA deployment path for Swift, Core ML, MLX, or a macOS-native SDK. For Oto's current architecture, the only realistic local-first path is an experimental helper process that Oto invokes for file-based transcription. Even that path comes with meaningful packaging, reliability, and UX tradeoffs.

## Primary Sources Consulted

- NVIDIA NIM ASR support matrix:
  - https://docs.nvidia.com/nim/riva/asr/latest/support-matrix.html
- NVIDIA model cards:
  - https://huggingface.co/nvidia/parakeet-ctc-0.6b
  - https://huggingface.co/nvidia/parakeet-rnnt-1.1b
  - https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2
- PyTorch MPS documentation:
  - https://docs.pytorch.org/docs/stable/mps.html

## What The Official Sources Say

### 1. NVIDIA NIM is not a direct fit for Oto

The latest NVIDIA Riva ASR NIM support matrix documents:

- Linux operating systems with Ubuntu 22.04+ recommended
- NVIDIA Driver `>= 535`
- NVIDIA Docker `>= 23.0.1`
- Windows 11 support only via WSL2
- Parakeet deployment on NVIDIA GPU hardware, not Apple Silicon GPU

The same support matrix lists Parakeet models in NIM, including:

- `Parakeet 0.6b CTC English (en-US)`
- `Parakeet 1.1b CTC English (en-US)`
- `Parakeet 0.6b TDT v2 English (en-US)`
- `Parakeet 1.1b RNNT Multilingual`

It also exposes multiple inference modes such as offline, streaming, and streaming-throughput. That is useful product capability, but the deployment target is still a containerized NVIDIA stack rather than a native macOS app.

Implication for Oto:

- NIM is not a practical "third local backend" for the current menu bar app shape.
- It would turn Oto into "native app plus external service stack".

### 2. NeMo is the official runtime for all Parakeet families

The RNNT model card documents loading `nvidia/parakeet-rnnt-1.1b` through:

- `nemo.collections.asr.models.EncDecRNNTBPEModel.from_pretrained(...)`

The TDT model card documents NeMo installation and usage as well.

Implication for Oto:

- The official runtime story is Python-first.
- Oto would need to manage an external inference runtime instead of remaining fully in Swift.

### 3. Only the CTC model currently has an official Transformers path

The `nvidia/parakeet-ctc-0.6b` model card explicitly documents:

- `AutoProcessor`
- `AutoModelForCTC`
- `pipeline("automatic-speech-recognition", model="nvidia/parakeet-ctc-0.6b")`

Important nuance from the same card:

- It says to install `transformers` from source.
- It expects `16000 Hz mono-channel audio (wav files)` as input.
- It transcribes to lower-case English alphabet output.

Implication for Oto:

- CTC is the easiest official spike path.
- It still requires a Python runtime and audio normalization/resampling step.
- Raw output quality is a weaker product fit than Oto's current backends because punctuation/capitalization are not built in.

### 4. TDT is a better UX fit, but a worse integration fit

The `nvidia/parakeet-tdt-0.6b-v2` model card highlights:

- punctuation
- capitalization
- accurate timestamp prediction
- `16kHz` mono `.wav` and `.flac` input

That makes TDT more attractive for dictation UX than CTC. However, I did not find an official Transformers path for TDT in the model card, only a NeMo path. In the NIM support matrix, TDT is also tied to the NVIDIA deployment story rather than native macOS packaging.

Implication for Oto:

- TDT is the better transcript shape.
- CTC is the lower-risk prototype path.

### 5. A Mac-local helper is technically plausible, but this is an inference

This is an inference from sources, not an NVIDIA-supported deployment claim:

- The official CTC path uses standard PyTorch plus Transformers.
- PyTorch officially supports the `torch.mps` backend on macOS for Apple GPU acceleration.

That means a Python helper running on Apple Silicon may be technically feasible. However, I did not find a source from NVIDIA stating that Parakeet itself is tested or supported on macOS/Apple Silicon. So "possible" is not the same as "supported."

## Best Candidate Model For A Spike

Start with `nvidia/parakeet-ctc-0.6b`.

Why:

- It is the only Parakeet model I found with an official Transformers inference path.
- It has the smallest runtime surface for a first experiment.
- It is the fastest way to answer the core question: can Parakeet run locally on Apple Silicon with acceptable latency and packaging cost?

Why not start with TDT or RNNT:

- TDT is more attractive for punctuation/capitalization, but the official path is heavier.
- RNNT is also NeMo-first and larger.
- Both increase integration risk before the basic macOS feasibility question is answered.

## Fit With Oto's Current Architecture

Parakeet does not fit into Oto as a simple new transcriber class.

Current constraints in the app:

- [`Oto/Model/STTBackend.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Model/STTBackend.swift) hardcodes two backend cases.
- [`Oto/AppState.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/AppState.swift) constructs `AppleSpeechTranscriber` and `WhisperKitTranscriber` directly.
- [`Oto/Services/Protocols/ServiceProtocols.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Services/Protocols/ServiceProtocols.swift) exposes backend-specific protocols instead of one generalized transcription abstraction.
- [`Oto/Services/RecordingFlowCoordinator.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Services/RecordingFlowCoordinator.swift) branches directly on `.appleSpeech` and `.whisper`.

Implication:

- Adding Parakeet is not just "add a third case and wire a class".
- Oto would first need a small backend abstraction refactor so a third engine can describe its capabilities cleanly.

## Feasibility Assessment

### Option A. Native in-process Swift backend

Feasibility: Low

Why:

- I found no official NVIDIA path for Swift, Core ML, MLX, or Apple-native packaging.
- The current official deployment story is Python/NeMo, Transformers for CTC, or NVIDIA NIM.
- A custom conversion/runtime path would be R&D work outside the officially documented NVIDIA deployment surface.

Conclusion:

- Not recommended for Phase 0.5.

### Option B. Local helper process on the same Mac

Feasibility: Medium for a research spike, low for a polished production backend

Shape:

- Oto keeps its current local audio capture flow.
- Oto writes or hands off a finalized audio file.
- A helper process transcribes the file and returns transcript text plus structured runtime metadata.

Pros:

- Preserves local-first behavior.
- Avoids Linux/NVIDIA GPU dependence.
- Reuses Oto's existing file-based finalization patterns.

Cons:

- Adds Python runtime management and dependency packaging.
- Adds more startup, model loading, and environment-failure modes.
- Likely starts as finalize-only rather than live partial streaming.
- Complicates signing, notarization, and release packaging for a native menu bar app.

Conclusion:

- This is the only realistic path worth spiking if the team wants to answer "Can Parakeet run locally inside Oto's product constraints?"

### Option C. Local or bundled NIM service

Feasibility: Low

Why:

- Official NIM deployment assumes Linux or WSL2 plus NVIDIA GPU.
- Oto is a macOS menu bar utility, not a service-orchestrating app.
- It materially changes install size, operator burden, and failure surface.

Conclusion:

- Not recommended.

## Dependencies And Work Required

### Runtime dependencies

- Python runtime management inside or alongside the app
- PyTorch runtime for local execution
- Hugging Face Transformers from source for the CTC spike, or NeMo for RNNT/TDT
- Model weight download, cache, integrity, and storage management
- Audio conversion to Parakeet-expected input shape such as `16 kHz` mono WAV for CTC and RNNT

### Oto codebase dependencies

- Add a third backend case to [`Oto/Model/STTBackend.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Model/STTBackend.swift)
- Replace the current Apple-versus-Whisper protocol split in [`Oto/Services/Protocols/ServiceProtocols.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Services/Protocols/ServiceProtocols.swift) with a generalized backend abstraction
- Refactor [`Oto/Services/RecordingFlowCoordinator.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/Services/RecordingFlowCoordinator.swift) to query backend capabilities instead of branching on known concrete engines
- Extend [`Oto/AppState.swift`](/Users/remi.bouchez/Documents/oto-workspaces/REM-60/Oto/AppState.swift) to construct and surface a third backend
- Add helper-process lifecycle management, timeout handling, structured stderr/stdout parsing, and deterministic fallback semantics
- Extend diagnostics, transcript artifact labeling, and latency reporting to include Parakeet runtime details

### Product and UX dependencies

- Decide whether Parakeet is finalize-only or must support streaming partials
- Decide whether Parakeet is hidden behind an experimental flag
- Decide whether output quality is acceptable if CTC remains lower-case and punctuation-light before refinement
- Decide whether the signed-app packaging story can tolerate a Python/helper runtime
- Decide acceptable disk footprint, memory footprint, and cold-start latency for a menu bar app

## Main Risks

- No official native Apple deployment path found
- Packaging complexity is much higher than Apple Speech or WhisperKit
- Model/runtime footprint may be too heavy for Oto's product shape
- CTC-first integration may depend heavily on Oto's `Enhanced` refinement mode to recover punctuation/capitalization
- First implementation likely loses WhisperKit-style live partials
- More failure states: helper launch, runtime mismatch, model discovery, dependency drift, audio format mismatch

## Recommendation

Recommendation: do not treat Parakeet as a production backend candidate for Phase 0.5.

If the team wants to continue, treat it as a research spike with a strict go/no-go gate:

1. Build a tiny local helper around `nvidia/parakeet-ctc-0.6b`.
2. Feed it finalized audio files from an Apple Silicon Mac.
3. Measure cold start, stop-to-final latency, memory, CPU, and transcript quality against WhisperKit `base`.
4. Verify whether a signed, reproducible macOS packaging story exists without Docker or cloud services.
5. Only continue if the helper path is operationally reliable and the UX degradation versus WhisperKit is acceptable.

## Suggested Spike Deliverable

The next research step should answer these questions before any product integration work starts:

- Can `nvidia/parakeet-ctc-0.6b` produce acceptable dictation quality on Apple Silicon macOS?
- What is the stop-to-final latency versus WhisperKit `base` on the same device?
- What are the package size and dependency costs of a Python helper?
- Can the helper be distributed reliably inside a signed macOS app?
- Is finalize-only behavior acceptable if streaming partials are not practical?
- Does TDT become worth the extra runtime complexity after the CTC spike is measured?

## Bottom Line

Parakeet is promising from a model-quality perspective, but the official deployment story is still much closer to Python or NVIDIA service infrastructure than to a native Swift macOS app. For Oto, that makes Parakeet a high-friction experimental backend rather than a straightforward alternative to Apple Speech or WhisperKit.
