# Oto UI Review and Re-Organization Plan

**Date:** 2026-02-17  
**Scope:** Menu bar UI review, dismissal reliability, and scalable advanced settings window design.

## 1. Findings (Highest Severity First)

1. Popover dismissal could be inconsistent when clicking outside.
   - User feedback indicated the menu did not always dismiss on outside click.
   - Risk: the app feels sticky/unpredictable and breaks expected menu bar behavior.
   - Action taken: added explicit local/global mouse monitors to close the popover when appropriate.

2. Menu bar popover carried too much low-frequency/advanced content.
   - The popover mixed fast actions with diagnostics, permissions, debug details, and artifact metadata.
   - Risk: crowded menu bar surface and poor scanability.
   - Action taken: reorganized into a stable lightweight structure and moved advanced concerns to a full window.

3. Information hierarchy was not strongly separated by frequency of use.
   - High-frequency controls and advanced controls appeared in the same dense stack.
   - Risk: high-friction operation for day-to-day dictation.
   - Action taken: clarified primary vs secondary zones and added dedicated navigation to advanced settings.

## 2. Menu Bar Re-Organization

The dropdown now follows a stable layout:

1. Header (identity + current backend)
2. Status area (flow state + short status line)
3. Primary interaction zone (start/stop, backend, quality)
4. Secondary configuration zone (hotkey mode + injection toggles)
5. Navigation zone (`Advanced Settings…`, `Open Transcripts Folder`)
6. System action (`Quit Oto`)

This keeps the menu bar calm and fast while preserving immediate control.

## 3. Dismissal Reliability Update

To address "does not always dismiss when clicking outside":

- Keep `NSPopover` behavior as transient.
- Add local mouse monitoring:
  - close popover when click target is outside popover/status-item/menu windows.
- Add global mouse monitoring:
  - close popover on external-app clicks.
- Preserve expected behavior:
  - avoid accidental close while interacting with status item button or picker menus.

## 4. Advanced Settings Window Strategy

### Chosen pattern: left sidebar + full content area

Recommendation: **use a sidebar split view** as the primary scalable pattern.

Why this over top tabs:
- Better scaling as sections grow beyond 4-5 categories.
- Clearer information architecture for future advanced features.
- macOS-native settings navigation behavior.
- Easier to host richer per-section content without crowding controls.

Top tabs remain acceptable for very shallow scope, but they become brittle as configuration depth increases.

## 5. Initial Window Information Architecture

The advanced window is structured with sidebar sections:

- Settings (Dictation + Permissions + Output & Injection)
- Transcripts (history list, copy actions, expandable previews)
- Diagnostics
- Extensions (reserved scalability slot)

This structure is intended to host existing options plus future additions without reworking navigation.

### Transcript Section Behavior

- Shows transcript artifacts in reverse chronological order (newest first).
- Includes `transcript-*`, `raw-transcript-*`, and `refined-transcript-*`.
- Excludes `failure-context-*` artifacts from the history list.
- Each transcript item is presented as a compact card with:
  - date/time
  - read-only Enhanced indicator
  - preview capped to 10 lines with expand/collapse
  - copy action with immediate visual feedback
- Refresh strategy is deterministic:
  - load when `Transcripts` section is first opened
  - explicit manual refresh button for reloading

## 6. Implementation Mapping

- Menu bar re-organization and `Advanced Settings…` entry:
  - `Oto/Views/MenuContentView.swift`
- Outside-click dismissal hardening and settings-window open action:
  - `Oto/OtoApp.swift`
- Advanced settings split view:
  - `Oto/Views/AdvancedSettingsView.swift`
- Transcript history loading/parsing:
  - `Oto/Services/TranscriptHistoryStore.swift`
- Transcript history domain model:
  - `Oto/Model/TranscriptHistoryEntry.swift`
- Advanced settings window lifecycle/controller:
  - `Oto/Windows/AdvancedSettingsWindowController.swift`
