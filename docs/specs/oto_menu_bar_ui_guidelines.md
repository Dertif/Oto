# Oto Menu Bar UI Guidelines for AI Agents

**Purpose:** practical implementation guidance derived from `docs/specs/oto_menu_bar_ui_spec.md`.  
**Not a feature spec:** this document tells agents *how* to shape UI work, not *what features* to add.

## 1. Product Posture

- Treat Oto as ambient infrastructure: calm, quick, and always ready.
- Prefer clarity and predictability over visual flourish.
- If a design choice is ambiguous, choose the simpler and more native macOS option.

## 2. Surface Boundaries

- Keep the menu bar dropdown lightweight:
  - status visibility
  - immediate actions
  - lightweight configuration
- Move complex or low-frequency tasks to windowed surfaces:
  - advanced preferences
  - history/log review
  - diagnostics
- Never turn the dropdown into a full dashboard.

## 3. Stable Dropdown Anatomy

Preserve a predictable top-to-bottom structure:

1. Header (orientation only)
2. Status line
3. Primary interaction zone
4. Secondary configuration zone
5. Navigation to expanded windows
6. System action section (for example, quit)

Use separators to group sections, but keep overall structure stable as features evolve.

## 4. Status and Language

- Keep status to one short line.
- Use neutral, state-only phrasing.
- Avoid personality, marketing, and instructional copy in the status line.

Good style examples:
- `Ready`
- `Listening`
- `Recording…`
- `Processing…`

## 5. Primary Controls

- Show only the highest-frequency controls in the dropdown.
- Keep visible primary elements to roughly `3–5`.
- Prefer direct interaction with immediate effect.
- Avoid nested submenus unless there is no reasonable alternative.
- Avoid Save/Apply patterns for primary menu bar controls.

## 6. Secondary Configuration

- Keep dropdown settings compact and native.
- Avoid deep trees and heavy configurators.
- If settings start to grow, move them to Preferences window sections.

## 7. Windowed UI Rules

Preferences-style window:
- Native macOS layout conventions.
- Clear section grouping, generous spacing.
- Avoid deep nesting and modal stacking.

Content-style window (history/logs):
- List-first layout with clear hierarchy.
- Native search at top.
- Secondary actions can appear on hover.
- Avoid card-heavy decoration.

## 8. Icon, Color, Motion

Menu bar icon:
- Single glyph, monochrome by default, legible at menu bar scale.
- No decorative/equalizer/waveform animation.

State signaling:
- Use subtle opacity change, very small scale shifts, and restrained accent.
- Accent indicates state urgency/focus/attention, not branding.

Motion:
- Prefer native macOS transitions.
- State changes should generally feel restrained (~150–250ms, ease-in-out).
- Avoid bounce or playful physics.

## 9. Interaction Behavior

- Clicking outside closes dropdown.
- `ESC` closes dropdown.
- Support standard keyboard navigation.
- Avoid over-confirmation for normal actions.
- Reserve confirmations for destructive actions.

## 10. Scope Guardrails for Phase 0.4

Do not introduce UI patterns that imply out-of-scope product expansion, including:
- menu bar dashboard behavior
- chat/assistant-style interface framing
- productivity-suite style multipane complexity

When uncertain, preserve existing hierarchy and keep the change minimal.
