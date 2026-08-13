# Feature Specification: Accessibility (VoiceOver) Audit Remediation

**Feature Branch**: `016-accessibility-audit`
**Created**: 2026-07-21
**Status**: Draft
**Input**: Deep accessibility audit fan-out (12 parallel agents + cross-validation) run against `Meshtastic/Views`, `Widgets/`, and `Meshtastic Watch App/Views`. Full raw findings: `/Users/bruschill/.pi/workflows/projects/meshtastic-apple-63f78c487247/runs/a11y-codebase-audit-mru2fgm4-u38mxd.json`.

This is a remediation backlog, not a new-feature spec — the SpecKit user-story template doesn't map cleanly onto a flat bug list, so this doc gives context and the requirements/success-criteria section states the acceptance bar per severity tier. **`tasks.md` in this directory is the actual working checklist** — grouped by the same severity tiers, one checkbox per finding, meant to be checked off across however many sessions this takes.

## Why this exists

The app has no automated accessibility test coverage and no prior systematic audit. A 12-agent fan-out audit (VoiceOver labels, value/hint, custom-control traits, element grouping, Dynamic Type, color-only signaling, contrast, touch targets, focus order, custom drawing/maps/charts, localization of a11y strings, accessibility identifiers) plus a cross-validation pass found 20 confirmed issue clusters (5 Blocker, 11 High, 4 Medium) covering ~60 individual file locations. Two reported findings were rejected as false positives during cross-validation (`NodeList.swift:110` reset-filter label; `NodeMapContent.swift` pin annotations were already fine).

## User Scenarios & Testing

### User Story 1 - VoiceOver users can send and receive messages (Priority: P1) 🎯 MVP

A blind or low-vision user relies on VoiceOver to compose, send, and read messages and direct messages — the app's core loop.

**Why this priority**: Messaging is the primary feature. Today the send button is unlabeled, cancel-reply is unlabeled, message integrity/translation badges are silently dropped from the read-aloud label, and the entire direct-message list (`DirectMessageUserRow`) has no accessibility support at all — VoiceOver users cannot reliably use messaging.

**Independent Test**: Enable VoiceOver, open a channel, compose and send a message, open Direct Messages, select a contact, verify the row announces name/unread/lock/star state, and verify a message with security/translation badges announces all of them.

**Acceptance Scenarios**:

1. **Given** VoiceOver is on and a channel is open, **When** the user swipes to the send button, **Then** it announces "Send message, button" (not "Button").
2. **Given** a received message is Verified, Store-and-forward, and machine-translated, **When** VoiceOver reads the message row, **Then** all three states are announced, not just Encrypted/Verified.
3. **Given** VoiceOver is on and Direct Messages is open, **When** the user swipes through the contact list, **Then** each row announces name, unread count, and lock/star state as one coherent element.

---

### User Story 2 - VoiceOver users can operate every custom (non-Button) interactive control (Priority: P1) 🎯 MVP

Several controls are built from `.onTapGesture` on a plain `VStack`/`HStack` rather than `Button`, so VoiceOver either can't perceive them as interactive or can't activate them with a double-tap at all (metrics column toggles, node-detail heard-time rows, the Nymea connect row, indoor air quality row, app-log stream row, and the geofence/region-selector drag handles, which have zero non-visual equivalent to dragging).

**Why this priority**: These controls are silently unreachable by VoiceOver — not degraded, unusable.

**Independent Test**: Enable VoiceOver, navigate to each listed control, verify it's announced with an interactive trait and a double-tap (or, for drag handles, the VoiceOver rotor's adjustable "increment/decrement" actions) performs the action.

**Acceptance Scenarios**:

1. **Given** VoiceOver is on and the metrics column picker is open, **When** the user swipes to a column toggle row, **Then** it announces "\<column name\>, \<Visible|Hidden\>, button" and double-tap toggles it.
2. **Given** VoiceOver is on and the geofence boundary editor is open, **When** the user selects the boundary handle, **Then** the VoiceOver rotor exposes increment/decrement (or named directional) actions that move the boundary without requiring a drag gesture.

---

### User Story 3 - VoiceOver users get equivalent information from icon-only toolbar and utility buttons (Priority: P2)

~15 files have icon-only buttons (close/dismiss, refresh, export, copy, help/filter toggles, map actions) with no `.accessibilityLabel`, so VoiceOver announces them as a bare "Button" with no indication of what they do.

**Why this priority**: Operable but opaque — real friction, not a hard block, since sighted-assist or trial-and-error can sometimes work around it.

**Independent Test**: Enable VoiceOver, swipe through each listed toolbar, verify every icon-only button announces a specific action name, not "Button."

**Acceptance Scenarios**:

1. **Given** VoiceOver is on and a firmware-update sheet is open, **When** the user swipes to the close button, **Then** it announces "Close, button."
2. **Given** VoiceOver is on the WiFi provisioning screen, **When** the user swipes to any of the three copy buttons, **Then** each announces a field-specific label ("Copy network name" / "Copy password" / "Copy PSK"), not a shared generic one.

---

### User Story 4 - Status conveyed by color has a non-color fallback (Priority: P2)

Signal-strength indicators, trace-route arrows, and map polylines encode state through color/hue alone in `NodeListItemCompact.swift`, `TraceRouteLog.swift`, and `MeshMapMK.swift`'s polylines.

**Why this priority**: Fails colorblind and low-vision users even with full vision otherwise; not a VoiceOver issue specifically but a WCAG 1.4.1 (Use of Color) violation.

**Independent Test**: View the node list and trace route log with a color-blindness simulator (e.g. Sim Daltonism); verify signal tiers remain distinguishable via symbol/shape, not hue alone.

**Acceptance Scenarios**:

1. **Given** two nodes with different signal tiers, **When** viewed under a protanopia filter, **Then** the SF Symbol (not just tint) differs between tiers and each has a distinct `accessibilityLabel` ("Strong signal" / "Weak signal").

---

### User Story 5 - Contrast decisions are computed correctly (Priority: P3)

`Color.swift`'s `isLight()` uses BT.601 perceptual luma with a flat 0.5 cutoff instead of WCAG relative luminance, so black/white text-on-color choices in `CircleText`, `WatchCircleText`, `FoxhuntCompassView`, and `AnimatedNodePin` can fail WCAG AA contrast at certain hues despite the code believing it "picked a contrasting color."

**Why this priority**: A correctness bug in shared infrastructure, not a missing feature — worth fixing once, benefits every call site, but not urgent since it degrades rather than blocks.

**Independent Test**: Compute `Color.isLight()` for known problem hues (saturated yellow, cyan) before and after the fix and confirm chosen text color meets 4.5:1 contrast against the WCAG relative-luminance formula.

---

### Edge Cases

- Live Activity (`WidgetsLiveActivity.swift`) runs outside the main app process (Lock Screen / Dynamic Island widget extension) — fixes there must be verified in the widget extension target, not just the main app.
- macCatalyst-gated close buttons (User Story 3, tier High #7) only matter for macOS VoiceOver; lower priority than the iOS-reachable duplicates in #6.
- `.accessibilityIdentifier` (Medium #19) has no consumer today (no UI test target exists) — do not block other fixes on this; add incrementally.

## Requirements

### Functional Requirements

- **FR-001**: Every interactive control (Button, custom tap-gesture view, drag handle) MUST expose a non-empty, non-generic `accessibilityLabel` to VoiceOver.
- **FR-002**: Every custom (`.onTapGesture`-based) control that behaves like a button MUST carry `.accessibilityAddTraits(.isButton)` (or the correct trait for its role) and be activatable via VoiceOver double-tap or an explicit `.accessibilityAction`.
- **FR-003**: Drag-only controls (geofence/region boundary handles) MUST expose a non-drag VoiceOver-operable equivalent (`.accessibilityAdjustableAction` or named directional custom actions).
- **FR-004**: Composite message/list rows MUST NOT silently drop badge/state information when building a combined `accessibilityLabel` — the combined label's source of truth must match what's rendered visually.
- **FR-005**: Status/state conveyed by color MUST also be conveyed by a non-color signal (symbol, shape, or text) and captured in an `accessibilityLabel`/`accessibilityValue`.
- **FR-006**: All accessibility label/hint/value strings MUST be localized (`String(localized:)` / `Localizable.xcstrings`), not hardcoded English literals.
- **FR-007**: `Color.isLight()` MUST use WCAG relative luminance, not BT.601 luma, for any text-on-color contrast decision.
- **FR-008**: Sliders, gauges, and progress views MUST expose `.accessibilityValue` reflecting their current numeric/semantic state, not just a visual fill.

### Key Entities

- **Finding**: One audit-confirmed accessibility defect — severity (Blocker/High/Medium), file path, line range, description, proposed fix. Tracked as one checkbox item per finding in `tasks.md`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All 5 Blocker findings resolved and verified with VoiceOver on-device (or Simulator + Accessibility Inspector) before this spec is closed.
- **SC-002**: All 11 High findings resolved; each icon-only button in the affected files announces a specific, localized action name.
- **SC-003**: Zero color-only status indicators remain in the node list, trace route log, and mesh map trace overlays (User Story 4).
- **SC-004**: `Color.isLight()` uses WCAG relative luminance; all 4 call sites (`CircleText`, `WatchCircleText`, `FoxhuntCompassView` x2, `AnimatedNodePin`) verified to pick correctly-contrasting text at previously-failing hues.
- **SC-005**: 4 Medium findings addressed opportunistically (not blocking release) — tracked, not required for this spec to be considered "done enough to ship the Blocker/High fixes."

## Assumptions

- Fixes are scoped to `Meshtastic/Views`, `Widgets/`, and `Meshtastic Watch App/Views` per the original audit scope; a broader pass (Accessory, CarPlay) was not run and is out of scope here.
- No UI test target exists yet, so `.accessibilityIdentifier` work (Medium #19) is tracked but not gated on this spec.
- Work proceeds roughly in the "Top fixes to do first" order from the audit report (message badges → DM row → send/cancel buttons → tap-gesture traits → Live Activity), but `tasks.md` is the authoritative, resumable checklist — sessions can pick up anywhere by scanning for unchecked items.
