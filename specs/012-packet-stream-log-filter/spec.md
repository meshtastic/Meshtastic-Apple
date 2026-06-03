# Feature Specification: Packet Stream Log Filter

**Feature Branch**: `012-packet-stream-log-filter`  
**Created**: 2026-06-02  
**Status**: Draft  
**Input**: User description: "make updates to the existing oslog filters and functionality to allow for a packet streaming filter which will display on packets that are going over the mesh currently. Update the categories and log levels filters to be accordions so they can be shown / hidden and take less space. Have packet stream as the top available option in the log filter"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Watch live mesh packet traffic (Priority: P1)

A user troubleshooting their mesh wants to see, in real time, the packets currently moving across the mesh. From the app log screen they choose a **Packet Stream** option, and the log view immediately switches to showing only packet-related activity and keeps updating on its own as new packets arrive — without the user having to pull-to-refresh or re-open the screen. New packets flow in and the newest stays in view, like watching traffic scroll by. On a busy mesh the flow is paced so it never scrolls faster than a person can read.

**Why this priority**: This is the headline capability the user asked for and the reason the other two stories exist. It turns the log screen from a static, after-the-fact snapshot into a live diagnostic window onto the mesh, which is the single most valuable outcome here. It is independently shippable: even with the existing filter layout unchanged, a working live packet stream delivers value on its own.

**Independent Test**: With a device connected and mesh traffic occurring, enable Packet Stream and confirm that (a) only packet-related entries are shown, (b) new packets appear automatically within a few seconds of occurring, and (c) disabling it returns the view to the normal log behavior.

**Acceptance Scenarios**:

1. **Given** the user is on the app log screen with a device connected and packets flowing over the mesh, **When** they enable Packet Stream, **Then** the view shows only packet-related log entries and new entries continue to appear automatically as packets arrive, with the newest entry kept in view.
2. **Given** Packet Stream is active on a busy mesh where packets arrive faster than a person can read, **When** the stream updates, **Then** new entries are surfaced at a steady, readable pace rather than flickering or scrolling by too fast to follow.
3. **Given** Packet Stream is active and showing entries, **When** no new packets occur for a period of time, **Then** the existing entries remain visible and the view does not clear or error.
4. **Given** Packet Stream is active and auto-scrolling, **When** the user scrolls back to read an earlier entry, **Then** the auto-scroll pauses so they can read, and resumes following the live edge when they return to the newest entry.
5. **Given** Packet Stream is active, **When** the user disables it, **Then** the view returns to the standard log display governed by the Categories and Log Levels filters.
6. **Given** Packet Stream is active and the user leaves the screen and returns, **When** the screen reappears, **Then** streaming resumes (or its prior state is restored) without requiring a manual refresh.

---

### User Story 2 - Trust that the stream shows only real packets (Priority: P1)

A user enables Packet Stream while their device has serial/firmware debug logging turned on. They expect to see only the packets crossing the mesh — text messages, positions, telemetry, nodeinfo, routing, etc. — and explicitly do NOT want the view drowned in device serial debug output, configuration-received chatter, admin/setup handshakes, or database save events.

**Why this priority**: A packet stream that is full of non-packet noise fails its core purpose, so this is as critical as the live updating itself (P1). Today the Mesh category mixes packet activity with config/admin lines, and the Radio category is mostly serial debug output — so the signal must be cleaned up (audited and reclassified) for Packet Stream to be trustworthy. This is independently verifiable: with serial logging enabled on the device, the Mesh category / Packet Stream should contain packet activity only.

**Independent Test**: Turn on serial debug logging on the connected device, open the log screen, select the Mesh category (or enable Packet Stream), and confirm the entries are exclusively over-the-air packet activity — no serial debug lines, no "config received", no admin/setup-only lines, no database save messages.

**Acceptance Scenarios**:

1. **Given** the connected device has serial/firmware debug logging enabled, **When** the user views the Mesh category or Packet Stream, **Then** none of the device serial debug entries appear (they appear only under the Radio category).
2. **Given** the app receives a configuration update or applies device/module config, **When** the user views the Mesh category or Packet Stream, **Then** those configuration entries do not appear there (they appear under the appropriate configuration/admin category).
3. **Given** the app saves or updates records in its database while handling traffic, **When** the user views the Mesh category or Packet Stream, **Then** those persistence entries do not appear there (they appear under the Data category).
4. **Given** the user sends a message or other packet from the app, **When** they view Packet Stream, **Then** the outgoing packet is represented alongside incoming packets.

---

### User Story 3 - Collapse and expand filter sections to save space (Priority: P2)

A user opening the log filter sees that the Categories list and Log Levels list take up most of the screen. They want to collapse the section(s) they are not currently adjusting so the filter panel is compact and easier to scan, and expand a section only when they want to change it.

**Why this priority**: The filter currently shows every category and level expanded at all times, which crowds the panel — especially once Packet Stream is added at the top. Making the Categories and Log Levels sections collapsible (accordions) directly improves usability and makes room for the new top option. It is independently testable and valuable even without the packet stream feature.

**Independent Test**: Open the log filter, collapse the Categories section and the Log Levels section, confirm their contents hide and the panel becomes shorter, then expand each and confirm the toggles reappear with their selections intact.

**Acceptance Scenarios**:

1. **Given** the log filter is open, **When** the user collapses the Categories section, **Then** the individual category toggles are hidden and the section occupies only its header height.
2. **Given** the Categories section is collapsed, **When** the user expands it, **Then** all category toggles reappear with their previous selection states unchanged.
3. **Given** the Log Levels section is collapsed or expanded, **When** the user toggles its state, **Then** the same show/hide behavior applies independently of the Categories section.
4. **Given** a section is collapsed, **When** the user applies filters, **Then** the selections inside the collapsed section are still honored by the filter.

---

### User Story 4 - Find Packet Stream as the first filter option (Priority: P3)

A user opening the log filter wants the Packet Stream option to be immediately visible at the top of the filter, above Categories and Log Levels, so the most common live-troubleshooting action is the first thing they reach.

**Why this priority**: Discoverability of the new capability. It depends on Packet Stream (P1) existing and is a small placement/ordering concern, so it ranks below the functional stories — but it ensures the feature is easy to find.

**Independent Test**: Open the log filter and confirm the Packet Stream control is the first option presented, positioned above the Categories and Log Levels sections.

**Acceptance Scenarios**:

1. **Given** the user opens the log filter, **When** the panel appears, **Then** the Packet Stream option is the first/topmost control, above the Categories and Log Levels sections.
2. **Given** Packet Stream is the top option, **When** the user enables it, **Then** its active state is clearly indicated in the filter.

---

### Edge Cases

- **No device connected / no traffic**: When Packet Stream is enabled but no packets are flowing, the view shows an empty or "waiting for packets" state rather than an error, and begins populating once traffic resumes.
- **High packet volume**: When packets arrive very rapidly, the stream remains responsive and readable — it must not freeze the screen or grow without bound. New entries are revealed at a capped, readable pace (FR-021); a maximum number of retained streamed entries applies (oldest dropped first); and ingestion continues independent of the display pace.
- **Interaction with existing filters**: When Packet Stream is active, it overrides the Categories and Log Levels selections (forces the Mesh packet signal at all levels) and those toggles are visibly disabled/ignored; disabling Packet Stream restores them.
- **Search text active**: When the user has search text entered and enables Packet Stream, the search continues to narrow the streamed packet entries.
- **Backgrounding / screen change**: When the app is backgrounded or the user navigates away, streaming pauses to avoid unnecessary work and resumes when the screen is active again.
- **Sharing/exporting logs**: When the user exports or copies logs while Packet Stream is active, the export is the Mesh-category packet log (the stream is the Mesh category filtered, so the standard category-filtered export applies — the full Mesh log, not truncated to the on-screen display cap), and PII (location/coordinates) remains redacted via the existing privacy markers (FR-024).
- **Location/PII in the stream**: Position packets appear in the stream; their coordinates use the app's private-redaction markers so exports and external log viewers redact them. On-screen, the in-app viewer shows the device's own log data as it does today.

## Clarifications

### Session 2026-06-02

- Q: How should outbound over-the-air packets feed the Mesh packet signal (today they log under Transport)? → A: During the audit, reclassify outbound over-the-air packet sends to the **Mesh** category so Packet Stream is purely the Mesh category (one authoritative source).
- Q: While Packet Stream is ON, how should the Categories and Log Levels selections behave? → A: Override — Packet Stream is a self-contained mode that forces the Mesh packet signal at **all log levels** and ignores/disables the Category and Level toggles while active.
- Q: Should the readable pacing rate be user-adjustable or fixed? → A: Fixed sensible default (~6 entries/sec); no user-facing control in this version.
- Q: How many streamed entries should the scroll-back buffer retain before dropping the oldest? → A: 1,000 entries.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The log filter MUST present a **Packet Stream** option as the first/topmost control, positioned above the Categories and Log Levels sections.
- **FR-002**: When Packet Stream is enabled, the log view MUST display only over-the-air mesh packet activity — the log entries that represent packets sent and received across the mesh — sourced from the **Mesh** activity category at all log levels. While Packet Stream is active it is a self-contained mode: the Categories and Log Levels selections are ignored/disabled and do not narrow the stream.
- **FR-003**: When Packet Stream is enabled, the log view MUST update automatically as new packet activity occurs, without requiring the user to manually refresh or re-open the screen.
- **FR-004**: The system MUST allow the user to turn Packet Stream off, returning the log view to its standard behavior governed by the Categories and Log Levels filters.
- **FR-005**: The Categories filter section MUST be collapsible and expandable (accordion), defaulting to a state that keeps the overall filter panel compact.
- **FR-006**: The Log Levels filter section MUST be collapsible and expandable (accordion), independently of the Categories section.
- **FR-007**: Collapsing a filter section MUST hide its individual toggles and reduce the space it occupies to approximately its header, while preserving the user's selections within that section.
- **FR-008**: Expanding a previously collapsed section MUST restore the visibility of its toggles with their selection states unchanged.
- **FR-009**: Filter selections inside a collapsed section MUST continue to be applied to the log view.
- **FR-010**: The filter MUST clearly indicate when Packet Stream is active.
- **FR-011**: While Packet Stream is active, the system MUST bound the number of retained streamed entries to **1,000** so the view remains responsive under high traffic, discarding the oldest entries when the limit is reached.
- **FR-012**: When Packet Stream is active but no packet activity is present, the system MUST show a non-error empty/waiting state and begin populating when activity resumes.
- **FR-013**: Active search text MUST continue to narrow results while Packet Stream is enabled.
- **FR-014**: Streaming MUST pause when the log screen is not active (e.g., app backgrounded or navigated away) and resume when it becomes active again.
- **FR-015**: The system MUST preserve the existing log viewer capabilities (search, manual refresh, viewing entry detail, exporting/copying) when Packet Stream is not active.
- **FR-016**: The **Mesh** activity category MUST represent only over-the-air mesh packet activity, so that selecting it (directly or via Packet Stream) yields a reliable, packet-only signal.
- **FR-017**: The Mesh packet signal MUST exclude non-packet activity, specifically: device serial/firmware debug output, configuration updates (device/module config received or applied), admin/setup message handling that is not itself an over-the-air packet event, and database/persistence events. These MUST be recorded under their appropriate categories (e.g., serial under Radio, configuration/admin under Admin, persistence under Data) rather than Mesh.
- **FR-018**: Existing log statements currently emitted under the Mesh category that do not represent over-the-air packet activity MUST be audited and reclassified to the correct category, as a prerequisite for FR-016/FR-017. (The audit covers the points where incoming packets are dispatched and where outgoing packets are sent.)
- **FR-019**: Both incoming and outgoing over-the-air mesh packets MUST be represented consistently in the **Mesh** category, so the stream reflects traffic in both directions rather than only received packets. Outbound packet sends that are currently logged under the Transport category MUST be reclassified to the Mesh category as part of the audit, so Packet Stream draws from the Mesh category alone.
- **FR-020**: While Packet Stream is active, the view MUST continuously append new packets and keep the newest entry in view (auto-scroll / live edge), giving the impression of traffic flowing by.
- **FR-021**: When packets arrive faster than a person can comfortably read, the system MUST pace the rate at which new entries are surfaced to the view to a fixed, readable maximum of approximately **6 entries per second** (no user-facing control in this version), so the stream remains legible rather than flickering or scrolling past too quickly. Below that threshold, entries appear as they arrive.
- **FR-022**: Pacing MUST NOT block ingestion: incoming packets continue to be received and counted while paced; the readable-rate limit governs only how quickly entries are revealed in the view. Sustained overload beyond capacity is handled by the bounded-retention limit (FR-011), discarding the oldest entries first.
- **FR-023**: The user MUST be able to pause the live flow to read an earlier entry (e.g., by scrolling away from the newest entry) and resume following the live edge, without disabling Packet Stream.
- **FR-024**: Packet log entries that contain personally identifying information — notably node location/coordinates carried by position packets — MUST continue to use the app's existing log privacy redaction (sensitive fields marked private) so the data is redacted in exported/shared logs and external log tools, consistent with current behavior. The Mesh-category audit and any new/relocated packet log statements MUST NOT downgrade a field that is currently redacted (private) to unredacted (public).

### Key Entities *(include if feature involves data)*

- **Packet Stream filter state**: Whether live packet streaming is currently enabled; the user-facing on/off control that, when on, overrides the Category/Level selections (forcing the Mesh packet signal at all levels) and live-updates the log view.
- **Log Category**: A named grouping of log entries (e.g., the existing set such as Mesh, Radio, Data, MQTT, Services, Transport, etc.) used by the Categories filter section. The **Mesh** category is the authoritative source of "packet" traffic for the stream; after the audit it contains only over-the-air packet activity, for both received packets and outbound sends (outbound sends are moved from Transport into Mesh). **Radio** = device serial/firmware debug output (not packets), **Admin** = configuration/admin/setup activity, **Data** = database/persistence events.
- **Log Level**: A severity grouping (e.g., Debug, Info, Notice, Error, Fault) used by the Log Levels filter section.
- **Filter section state**: For each collapsible section (Categories, Log Levels), whether it is currently expanded or collapsed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With live mesh traffic, newly occurring packets appear in the Packet Stream view within 5 seconds of occurring, without any manual user action.
- **SC-002**: Enabling Packet Stream takes a single tap from the open log filter, and the option is the first control the user encounters in the filter.
- **SC-003**: With both filter sections collapsed, the filter panel's vertical footprint is reduced by at least 50% compared to the current always-expanded layout, measured by on-screen height.
- **SC-004**: Collapsing and expanding a filter section never changes the user's existing category/level selections (0% selection loss across collapse/expand cycles).
- **SC-005**: Under sustained high packet traffic, the log screen remains interactive (scroll and toggle filters without noticeable stalls) and memory use stays bounded by the 1,000-entry retention limit.
- **SC-006**: A user unfamiliar with the feature can locate and enable live packet viewing in under 15 seconds from opening the log screen.
- **SC-007**: With device serial/firmware debug logging enabled, 0% of the entries shown in Packet Stream (the Mesh category) are device serial debug lines, configuration-update lines, admin/setup-only lines, or database/persistence lines — every shown entry is an over-the-air packet event.
- **SC-008**: On a busy mesh generating packets well above the readable rate, new entries are revealed at no more than the fixed readable cadence (≈ 6 entries per second), the view stays smoothly scrollable (no stutter or freeze), and a user can visually follow individual entries as they appear.
- **SC-009**: When the user scrolls back during an active stream, auto-scroll pauses within one update cycle and does not yank the view back to the newest entry until the user returns to the live edge (0 unexpected jumps while reading).
- **SC-010**: In exported/shared logs and external log tools, 100% of location/coordinate PII in packet entries is redacted (no raw coordinates leak); no packet field currently redacted is exposed as a result of the Mesh audit.

## Assumptions

- **"Packets going over the mesh currently"** is interpreted as a live tail of the **Mesh** activity category, which is being made the single authoritative packet signal. Rather than adding a new logging category or a structured packet-capture pipeline, the existing **Mesh** category is audited so that it contains only over-the-air packet activity (see FR-016–FR-019). The **Radio** category is explicitly NOT used because it is dominated by device serial/firmware debug output when serial logging is enabled.
- **Packet Stream is a distinct viewing mode** layered on the existing log source: when active it narrows the view to packet traffic and enables automatic live updating; when inactive the screen behaves exactly as today.
- **No structured packet decoding** (parsing individual fields like from/to/port/hop-limit into columns) is in scope for this version; the stream shows the existing log-line content for packet activity. Structured packet display can be a later enhancement.
- **Default collapsed/expanded state**: sections default to a compact arrangement (at least the lower-priority sections collapsed) so the panel is smaller out of the box; exact defaults can be tuned during design.
- **Live updates are limited to the live log source available to the app** (the same source the current viewer reads); historical entries already present remain available as today.
- **Readable pacing**: when packets exceed a human-readable rate, new entries are revealed at a fixed steady cap of ≈ 6 entries per second, with no user-facing control in this version. Ingestion is not throttled — only the rate at which entries are revealed in the view. The pacing interacts with the bounded-retention limit (FR-011): sustained overload drops the oldest entries (beyond 1,000 retained) rather than letting a backlog grow without bound.
- **Auto-scroll with read-pause**: the stream follows the newest entry by default; scrolling away from the live edge pauses auto-scroll so the user can read, and returning to the newest entry resumes it.
- **Streaming pauses when off-screen/backgrounded** to conserve battery and CPU, consistent with typical iOS app behavior.
- **PII redaction is preserved, not introduced**: the app already redacts location/coordinate PII in logs via OSLog privacy markers (`.private`). This feature reuses that mechanism; the audit must keep sensitive packet fields redacted for export/external viewing. The in-app viewer reads the current process's own log store, so it can display the device's own data on-screen as today — redaction's purpose is for shared/exported logs and external tools, not to hide the user's own data from themselves.
- This feature targets the existing in-app log/diagnostics screen; it does not change how logs are written elsewhere in the app.
