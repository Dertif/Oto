# Oto – Menu Bar & Windowed Interface UX Framework

**Version:** 0.2  
**Status:** Structural Guidelines (Content-Agnostic)  
**Scope:** Interaction framework only – no feature locking

---

# 1. Philosophy

This document defines structural UX principles for Oto’s menu bar and windowed surfaces.

It does NOT define:
- Specific features
- Exact settings
- Backend choices
- Product scope decisions

It defines:
- Surface hierarchy
- Interaction rules
- Layout logic
- Behavioral constraints

Oto is ambient infrastructure — visible, calm, always ready.

---

# 2. Surface Hierarchy

Oto has two primary surfaces:

1. Menu Bar Surface (Primary, lightweight)
2. Windowed Surface (Secondary, expanded control)

The menu bar is for:
- Status visibility
- Immediate actions
- Lightweight configuration

The windowed interface is for:
- Extended configuration
- History / logs
- Advanced controls

The menu bar must never evolve into a full dashboard.

---

# 3. Menu Bar Icon System

## 3.1 Core Principles

- Single glyph icon
- Monochrome by default
- Legible at 16px
- No decorative animation

## 3.2 State Signaling

Icon states may communicate:
- Idle
- Listening / armed
- Active / recording
- Error / attention required

State changes must use:
- Subtle opacity shifts
- Minimal scale adjustments (2–4%)
- Controlled accent usage

No aggressive waveform animation.
No equalizer-style movement.

---

# 4. Dropdown Framework (Content-Agnostic)

## 4.1 Structural Layout

The dropdown must follow a predictable vertical structure:

1. Header area
2. Status area
3. Primary interaction zone
4. Secondary configuration zone
5. Navigation / extended actions
6. System-level action (e.g. quit)

Dividers may separate logical groups.

The structure remains stable even as features evolve.

---

## 4.2 Header Area

- Displays product name or minimal identifier
- No branding overload
- No marketing copy

Purpose: orientation only.

---

## 4.3 Status Area

A dedicated status line must exist.

Rules:
- Single-line status text
- Short phrasing
- Neutral tone
- No personality

Examples of tone (not feature commitments):
- Ready
- Listening
- Recording…
- Processing…

The status line communicates state, not guidance.

---

## 4.4 Primary Interaction Zone

Reserved for:
- Immediate actions
- High-frequency controls

Guidelines:
- Max 3–5 primary elements visible
- No nested submenus unless absolutely necessary
- Direct interaction only
- Immediate effect (no Save button)

This zone must remain lightweight.

---

## 4.5 Secondary Configuration Zone

Reserved for:
- Low-frequency adjustments
- Mode switches
- Behavioral preferences

Guidelines:
- Compact controls
- Native macOS components
- No deep configuration trees

If configuration grows complex, it must move to the windowed surface.

---

## 4.6 Navigation to Extended Surface

The dropdown may include entry points to:
- History
- Advanced configuration
- Diagnostics

These must open a separate window.

The dropdown is not scroll-heavy.

---

# 5. Windowed Interface Framework

The windowed interface supports expanded interaction without overloading the menu bar.

## 5.1 Window Types

Two structural categories:

1. Preferences-style window
2. Content-style window (e.g. history/logs)

Both must follow macOS-native conventions.

---

## 5.2 Preferences Window Guidelines

- Native segmented sidebar (if multiple sections)
- Clear section grouping
- Generous spacing (16–24pt)
- No custom-styled panels unless necessary

Rules:
- Avoid deep nesting
- Avoid modal stacking
- Avoid hidden advanced toggles inside toggles

Preferences should feel controlled and deliberate.

---

## 5.3 Content Window Guidelines

For surfaces such as transcript history or logs:

- List-based layout
- Clear hierarchy (timestamp, preview, metadata)
- Search field at top (native macOS style)
- Hover-reveal secondary actions

No card-heavy UI.
No heavy visual decoration.

---

# 6. Interaction Principles

## 6.1 Immediate Feedback

All actions must:
- Provide subtle visual acknowledgment
- Avoid blocking UI
- Avoid loading spinners unless necessary

---

## 6.2 No Over-Confirmation

Avoid:
- "Are you sure?" for normal actions
- Excess confirmation modals

Use confirmation only for destructive actions.

---

## 6.3 Predictability

- Clicking outside closes dropdown
- ESC closes dropdown
- Standard macOS keyboard navigation supported

No surprising behavior.

---

# 7. Accent Color Usage (Framework Level)

Accent color is state-driven, not decorative.

It may indicate:
- Active state
- Focus
- Attention

It must not:
- Dominate backgrounds
- Be used as primary layout color
- Appear in idle state

Accent intensity may scale with state urgency.

---

# 8. Motion Constraints

Dropdown:
- Native macOS animation

Window open/close:
- System-standard transitions

State transitions:
- 150–250ms
- Ease-in-out
- No bounce physics

Motion must reinforce clarity, not personality.

---

# 9. Guardrails

The menu bar must never become:
- A settings dashboard
- A marketing surface
- A complex configuration tree

The windowed interface must never become:
- A productivity suite
- A chat interface
- A conversational assistant UI

Oto remains infrastructure.

---

# 10. Evolution Strategy

As Oto expands (hybrid voice layer):

- The structural zones remain stable
- Content may change
- The hierarchy does not

Structure first. Features adapt within structure.

---

End of UX Framework.