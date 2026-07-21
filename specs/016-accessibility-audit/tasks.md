# Tasks: Accessibility (VoiceOver) Audit Remediation

**Input**: `spec.md` in this directory; full raw audit result: `/Users/bruschill/.pi/workflows/projects/meshtastic-apple-63f78c487247/runs/a11y-codebase-audit-mru2fgm4-u38mxd.json`
**Audit method**: 12-agent parallel fan-out (VoiceOver labels, value/hint, custom-control traits, element grouping, Dynamic Type, color-only signaling, contrast, touch targets, focus order, custom drawing/maps/charts, localization of a11y strings, accessibility identifiers) + cross-validation pass over `Meshtastic/Views`, `Widgets/`, `Meshtastic Watch App/Views`.

**How to use this file**: Check off `[x]` as each item is fixed and verified (VoiceOver on-device or Simulator + Accessibility Inspector). This is the persistent tracker — pick up anywhere by scanning for the first unchecked box. Update the "Progress" line below when a batch is completed.

**Progress**: 6 / 60 individual locations fixed (0 / 20 finding clusters fully closed — T002/T015/T016 done but their clusters still have other locations open) — last updated 2026-07-21.

---

## Phase 1: Blocker (VoiceOver users cannot perceive or operate the feature)

- [ ] T001 `Widgets/WidgetsLiveActivity.swift` — zero accessibility calls in the whole file. Add `.accessibilityElement(children: .ignore)` + `.accessibilityLabel` to `StatRow` (~line 296-311) and to each icon+fraction pair (lines ~64, 117, 136, 216) and the countdown timer (~line 334). Verify in the widget extension target (Lock Screen/Dynamic Island), not just the main app.
- [x] T002 `Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift:79,237` — send button (`arrow.up.circle.fill`) has no `.accessibilityLabel`. Add `String(localized: "Send message")`. **Done**: fixed both the legacy (line ~82) and `FormattingComposeArea` (line ~243) send buttons.
- [ ] T003 [P] `Meshtastic/Views/Messages/UserMessageRow.swift:35-51,180-181` and `ChannelMessageRow.swift:175-176` — combined `accessibilityLabel` (`messageAccessibilityLabel`) overwrites per-badge labels set in `MessageText.swift:172,192,206` (Verified sender, Store and forward, Detection sensor, Showing translated text). Rebuild the combined label from the same source-of-truth flags `MessageText.swift` uses instead of hand-listing only Encrypted/Verified. One fix, two call sites.
- [ ] T004 `Meshtastic/Views/Messages/UserList.swift:253-316` (`DirectMessageUserRow`) — no accessibility at all: unread dot not `.accessibilityHidden`, lock/star icons unlabeled, no combined element/label. Port the working pattern from `ChannelList.swift:59-66`.
- [ ] T005 [P] `Meshtastic/Views/Nodes/Helpers/Metrics Columns/MetricsColumnDetail.swift:46-61,65-77` — `.onTapGesture` row with no interactive trait; VoiceOver double-tap doesn't activate it. Add `.contentShape(Rectangle())` + `.accessibilityElement(children: .combine)` + `.accessibilityLabel` + `.accessibilityValue(Visible/Hidden)` + `.accessibilityAddTraits(.isButton)` + `.accessibilityAction`.
- [ ] T006 [P] `Meshtastic/Views/Connect/Connect.swift:1202-1225` (`NymeaDeviceConnectRow`) — same `.onTapGesture`-with-no-trait issue as T005; apply the same pattern.
- [ ] T007 [P] `Meshtastic/Views/Helpers/Weather/IndoorAirQuality.swift:76-78` — same `.onTapGesture`-with-no-trait issue; apply the same pattern.
- [ ] T008 [P] `Meshtastic/Views/Settings/AppLog.swift:324-326` (`streamRow`) — same `.onTapGesture`-with-no-trait issue; apply the same pattern.
- [ ] T009 [P] `Meshtastic/Views/Nodes/Helpers/NodeDetail.swift:357-374,377-399` (First/Last heard rows) — already has `.accessibilityElement(children: .combine)` but no `.isButton` trait; add the trait + `.accessibilityAction`.
- [ ] T010 `Meshtastic/Views/Nodes/Helpers/Map/GeofenceBoundsSelectorView.swift:120-138` and `Meshtastic/Views/Nodes/Helpers/Map/Offline/RegionSelectorView.swift:143-161` — drag handles have zero non-visual equivalent. Add `.accessibilityAdjustableAction` (increment/decrement to nudge the bound) or paired "Move north/south/east/west" custom actions. Two files, same pattern.
- [ ] T011 `Meshtastic/Views/Settings/Discovery/DiscoveryMapView.swift:84` — `Annotation("", coordinate: coord)` has a genuinely empty title. Change to `Annotation(device.displayName, coordinate: coord)`.

**Checkpoint**: All 5 Blocker clusters (T001-T011) closed → messaging, metrics/settings tap-rows, geofence editing, and the Live Activity are usable end-to-end with VoiceOver.

---

## Phase 2: High (operable, but VoiceOver gives no useful information)

### Icon-only buttons, unlabeled

- [ ] T012 [P] `Meshtastic/Views/Settings/Firmware/NRF DFU/NRFDFUSheet.swift:74` — close button (`xmark.circle.fill`), add `.accessibilityLabel(String(localized: "Close"))`.
- [ ] T013 [P] `Meshtastic/Views/Settings/Firmware/ESP32 OTA/BLE/ESP32BLEOTASheet.swift:111` — same close-button fix as T012.
- [ ] T014 [P] macCatalyst-gated close buttons (lower priority than T012/T013 — macOS VoiceOver only), same `.accessibilityLabel(String(localized: "Close"))` fix inside each `#if targetEnvironment(macCatalyst)` block:
  - `RouteRecorder.swift:274`
  - `AppLogFilter.swift:199`
  - `LogDetail.swift:154`
  - `NodeListFilter.swift:148`
  - `MetricsColumnDetail.swift:85`
  - `MapSettingsForm.swift:282`
  - `WaypointForm.swift:555`
  - `MapLegend.swift:67`
  - `InvalidVersion.swift:96`
  - `DirectMessagesHelp.swift:47`
  - `NodeListHelp.swift:197`
  - `ChannelsHelp.swift:107`
- [x] T015 [P] `TextMessageField.swift:38,190` — cancel-reply button (`x.circle.fill`), add `.accessibilityLabel(String(localized: "Cancel reply"))`. **Done**: fixed both the legacy (line ~47) and `FormattingComposeArea` (line ~202) cancel-reply buttons.
- [x] T016 [P] `TextMessageField.swift:111,311` — emoji picker button (`face.smiling`, Catalyst-only), add a localized label. **Done**: fixed both the legacy `legacyToolbarContent` (line ~123) and `FormattingComposeArea` `toolbarContent` (line ~326) emoji picker buttons.
- [ ] T017 [P] Help-toggle buttons with no on/off-reflecting label — add `.accessibilityLabel(showHelp ? "Hide help" : "Show help")` (localized):
  - `Channels.swift:343`
  - `ShareChannels.swift:147`
  - `ChannelList.swift:206`
  - `UserList.swift:35`
  - `NodeList.swift:97`
- [ ] T018 [P] Filter-toggle buttons (distinct from the already-correct reset buttons nearby) — same on/off-label pattern as T017:
  - `UserList.swift:62`
  - `NodeList.swift:124`
- [ ] T019 [P] Refresh/export/action icon buttons, unlabeled — add a specific localized `.accessibilityLabel` to each:
  - `AppLog.swift:130` (Catalyst-gated)
  - `Firmware.swift:370` — **fix in both** the `#if`/`#else` branches, both currently unlabeled
  - `BackupRowView.swift:45` (restore, `arrow.counterclockwise`)
  - `RouteRecorder.swift:70` (record/details)
  - `AppLog.swift:143` (export CSV)
  - `ChannelForm.swift:61` (generate key)
  - `DiscoverySummaryView.swift:53` (export PDF)
  - `MeshMapMK.swift:538` (open map window, macOS-only)
  - `WaypointForm.swift:455` (edit waypoint)
  - `SecureInput.swift:62` (show/hide password)
- [ ] T020 `WifiProvisioningView.swift:133,348,395` — three separate `doc.on.doc` copy buttons. Give each its own field-specific label: "Copy network name" / "Copy password" / "Copy PSK" — not one shared generic label.
- [ ] T021 [P] `MeshMapMK.swift:372` — clear-trace-route button (`trash`), unlabeled while neighboring buttons (`:365`) already are. Add `.accessibilityLabel(String(localized: "Clear trace route"))`.
- [ ] T022 [P] `MeshMapMK.swift:511` — map-settings button (`info.circle`), unlabeled while neighboring buttons (`:507`) already are. Add `.accessibilityLabel(String(localized: "Map settings"))`.
- [ ] T023 [P] `NodeMapSwiftUI.swift:204-210,214-218,226-230` — unlabeled while neighboring buttons (`:200-202`) already are. Add matching localized labels.

### Value/hint gaps

- [ ] T024 `Meshtastic/Views/Nodes/Helpers/NodeListFilter.swift:96-107` — Slider's hidden `label:` is `Text("Speed")` (wrong domain) with no `.accessibilityValue`. Fix label text and add `.accessibilityValue("\(Int(filterValue)) dBm")`.
- [ ] T025 `AppLogFilter.swift:245-261` (`selectionRow`) — checkmark row has no trait/value. Add `.accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)`.
- [ ] T026 `DiscoveryScanView.swift:234-236` — `ProgressView(value:)` is unlabeled and ungrouped from its "Time Remaining" text. Combine with `.accessibilityElement(children: .combine)` + `.accessibilityValue("\(Int(progress * 100)) percent")`.
- [ ] T027 [P] `LoRaSignalStrength.swift:31-45` (compact Gauge) — no explicit accessibility. Add `.accessibilityLabel("Signal strength")` + `.accessibilityValue(signalDescription)`.
- [ ] T028 [P] `AirQualityIndex.swift:49-58` (`.gauge` case) — same gap as T027; apply the same pattern.

### Color-only signaling

- [ ] T029 `Meshtastic/Views/Nodes/TraceRouteLog.swift:296-300` — `arrowshape.right.fill` tinted by `snrColor` only, no text/shape distinction. Add a per-tier `accessibilityLabel`.
- [ ] T030 `Meshtastic/Views/Nodes/Helpers/NodeListItemCompact.swift:287-288` — identical SF Symbol across all signal tiers, only color changes. Vary the symbol per tier (e.g. `wifi` / `wifi.slash`) and add `.accessibilityLabel(signalTier.description)`.
- [ ] T031 `Meshtastic/Views/Nodes/MeshMapMK.swift:1240,1252` — trace-route polylines vary by hue only. Add `lineDashPhase`/width variation keyed to SNR tier so shape, not just hue, encodes strength.

### Localization of accessibility strings

- [ ] T032 [P] `Channels.swift:527,530,533` (`ChannelStatusIcon`) — hardcoded English a11y strings, absent from `Localizable.xcstrings`. Wrap in `String(localized:)` and add keys.
- [ ] T033 [P] `TextMessageField/FormattingToolbarButtons.swift:107-114` — same localization gap as T032.
- [ ] T034 [P] `Model/Firmware/FirmwareUpdateNotifier.swift:75-82` (feeds `Connect.swift:869`) — same localization gap as T032.
- [ ] T035 [P] `Lockdown/LockdownSheet.swift:159,207` — same localization gap as T032.
- [ ] T036 [P] `Messages/MessageSearchBar.swift:27` — same localization gap as T032.

### Contrast correctness

- [ ] T037 `Meshtastic/Extensions/Color.swift:63-67,74-78` (`isLight()`) — uses BT.601 luma with a flat 0.5 cutoff instead of WCAG relative luminance. Replace with a `relativeLuminance()` implementation (WCAG formula) and a `>0.179` (~4.5:1) cutoff. This is shared infrastructure — fixing it here fixes T038 below plus `CircleText.swift:25` and `Meshtastic Watch App/Views/WatchCircleText.swift:27` for free.
- [ ] T038 `Meshtastic/Views/Nodes/Helpers/Map/MapContent/AnimatedNodePin.swift:43-47` — hardcoded `.foregroundStyle(.white)` ignores contrast entirely, unlike `CircleText.swift` one line below. Switch to `nodeColor.isLight() ? .black : .white` (depends on T037 being correct first).

**Checkpoint**: All 11 High clusters (T012-T038) closed → every icon-only control announces a specific action, sliders/gauges report state, signal tiers are distinguishable without color, a11y strings are localized, and contrast decisions use the correct formula.

---

## Phase 3: Medium (correct but suboptimal)

- [x] T039 [P] Element grouping missing (readable today, but each glyph/number is a separate VoiceOver stop) — add `.accessibilityElement(children: .combine)` to each:
  - `PowerMetricsLog.swift:127-137`
  - `DeviceMetricsLog.swift:105-121`
  - `HelpItem.swift:23-38`
  - `MapLegend.swift:22-37` (`MapLegendItem`)
  - `TAKServerConfig.swift:194-224`
  - `Firmware.swift:131-146`
  - `Connect.swift:191-207`
  - `WifiProvisioningView.swift:15-32` (`ActivityRow`)
  - `AppData.swift:49-63`
- [x] T040 `Meshtastic/Views/Settings/Firmware/Helpers/CircularProgressView.swift` — zero accessibility in this shared component. Add `.accessibilityElement(children: .ignore)` + `.accessibilityLabel("Update progress")` + `.accessibilityValue("\(Int(progress * 100)) percent")`. One fix covers 4 call sites: `NRFDFUSheet.swift`, `ESP32WifiOTASheet.swift`, `ESP32BLEOTASheet.swift`, `FirmwareUpdateGameView.swift`.
- [ ] T041 Accessibility identifiers absent app-wide except `FirmwareUpdateGameView.swift:18,45,121,247`. No UI test target exists today, so this doesn't break anything — **not urgent**, add `.accessibilityIdentifier` incrementally to primary nav/interactive elements as they're touched for other fixes in this list, rather than as a standalone pass.
- [x] T042 [P] Dynamic Type clipping in compact widgets — `DistanceCompactWidget.swift`, `HumidityCompactWidget.swift` (and siblings) cap `maxHeight: 140` while using `.font(.largeTitle)` inside; text clips at larger accessibility sizes. Add `.minimumScaleFactor(0.5)` + `.lineLimit(1)`.
- [x] T043 [P] `ChannelList.swift:135` and `UserList.swift:316` — fixed `.frame(height: 62)` rows won't grow for large Dynamic Type sizes. Switch to `.frame(minHeight: 62)`.

**Checkpoint**: All 4 Medium clusters (T039-T043) closed → grouping is coherent, firmware progress is announced, Dynamic Type no longer clips, and identifiers are being added opportunistically.

---

## Dependencies & Execution Order

- **T037 before T038**: `AnimatedNodePin`'s fix depends on `Color.isLight()` being correct first.
- Everything else in Phase 1/2/3 is independent — most rows are marked `[P]` (different files, no shared state) and can be done in any order or batched by file/area.
- Recommended order (matches the audit's "top fixes first" list): T002-T004 (messaging) → T005-T011 (tap-gesture traits + Live Activity) → rest of Phase 2 → Phase 3.

## Notes

- [P] = different files, no dependencies — safe to batch or parallelize across sessions/people.
- Each task cites exact file(s) and line numbers from the audit; line numbers may drift as the file changes — re-locate by symbol/context if a line number is stale, don't skip the task.
- Verify fixes with VoiceOver (on-device preferred; Simulator + Accessibility Inspector as fallback) before checking a box, not just by code review.
- Update the **Progress** line at the top of this file when a batch is completed so future sessions know where things stand at a glance.
