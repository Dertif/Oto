# RFC – Oto Voice Architecture (Exploration)

**Status:** Draft – Exploratory  
**Author:** Oto  
**Scope:** MVP Dictation + Future Hybrid Direction  
**Decision Level:** No final decisions taken. Directional discussion document.

---

# 1. Context

Oto aims to become a local, premium voice layer for macOS.

The initial release (MVP) focuses strictly on replacing macOS dictation with a faster, more reliable, fully local solution.

The longer-term vision expands into hybrid voice control (dictation + commands + workflow routing).

This RFC outlines architectural exploration and tradeoffs. It does not lock decisions.

---

# 2. Goals

## MVP Goals
- Local-only processing
- Fast perceived activation
- Reliable text injection
- Minimal CPU usage while idle
- Apple-native UX feel

## Non-Goals (MVP)
- Conversational assistant
- Cloud transcription
- Complex intent parsing
- Command routing layer

---

# 3. Proposed High-Level Flow (Exploratory)

Idle State:
- Passive wake-word detection only
- No transcription
- No recording storage

Activation:
1. User says "Hey Oto"
2. Wake word detected
3. Recording starts
4. Local transcription begins (streaming)
5. Text injected at active cursor
6. Stop on silence timeout or shortcut

This preserves a clean transition path toward future command support.

---

# 4. Wake Word Architecture

Requirements:
- Low CPU footprint
- Minimal false positives
- Minimal false negatives
- Fast activation perception (<300ms target)

Exploration Options:
- Lightweight CoreML wake-word model
- Dedicated wake-word engine separate from STT

Open Questions:
- Should sensitivity be configurable?
- Should push-to-talk remain first-class fallback?

No final implementation chosen.

---

# 5. STT Engine Exploration

Multiple engines are being evaluated.

## Option A – Apple Speech Framework
Pros:
- Native integration
- Low perceived latency
- Built-in punctuation

Cons:
- Quality variability
- On-device vs network ambiguity

Possible Role:
- Default backend for seamless experience

---

## Option B – Whisper.cpp / WhisperKit
Pros:
- Fully offline
- Model size flexibility
- Predictable behavior

Cons:
- CPU / thermal impact
- Requires careful optimization

Possible Role:
- Offline-strict mode
- Accuracy-focused mode
- Secondary backend

---

## Option C – NVIDIA Parakeet (Local)
Pros:
- Potential performance improvements
- Modern architecture

Cons:
- Integration complexity
- macOS constraints

Possible Role:
- Experimental / Turbo backend

---

# 6. Engine Routing (Exploratory)

Possible dynamic routing model:

- Wake word engine runs independently
- Dictation backend selected based on:
  - User preference
  - Hardware capability
  - Thermal state
  - Privacy configuration

This adds flexibility but increases complexity.

Open Question:
- Is multi-backend routing justified for v1?

---

# 7. Streaming & Finalization Strategy

Objective: Premium perceived experience.

Options under consideration:
- Streaming partial transcription + final correction pass
- Single-engine optimized streaming
- Small model for live stream + larger model for finalize

No final approach selected.

---

# 8. UX Principles (MVP)

Oto should feel:
- Invisible
- Infrastructure-like
- Calm
- Non-conversational

Design constraints:
- Menu-bar first
- Minimal visual presence
- Subtle activation feedback
- Keyboard shortcut fallback
- Optional push-to-talk

Personality evolution is deferred to post-MVP.

---

# 9. Technical Risks & Constraints

- Idle CPU cost (wake loop)
- Sustained dictation thermals
- Battery impact
- Microphone permission UX
- Text injection reliability across apps
- Formatting consistency

Performance perception is critical.

---

# 10. Future Evolution Path

Phase 0.1 → Reliable STT only  
Phase 0.2 → End-to-end reliability feel (activation + capture + transcription + text injection)  
Phase 1 → Dictation excellence  
Phase 2 → Voice-triggered commands  
Phase 3 → Context-aware workflow routing

Architectural decisions should preserve this expansion path without overbuilding in v1.
Early phases intentionally de-risk fundamentals in tiny, sequential steps.

---

# 11. Decision Log

No decisions finalized at this stage.

Next steps:
- Benchmark latency across engines
- Measure idle CPU for wake-word approach
- Compare accuracy across real-world dictation samples
- Evaluate integration complexity

---

End of RFC (Exploratory Draft)
