# Manual Test Guide: Accessibility Audit Branches

Step-by-step verification instructions for each of the 9 local `a11y/*` branches
before opening PRs. Verified against actual diffs (not just commit messages) —
see "Coverage note" per branch for anything the branch's own commit messages
under-claim or over-claim.

## Before you start

**Simulator cannot produce real VoiceOver speech.** Confirmed via Apple's own
docs/forums: VoiceOver has no audio/speech simulation in iOS Simulator, on any
Xcode version. `Settings > Accessibility` in the Simulator has no VoiceOver
toggle at all. For real speech + gesture testing you need a **physical iPhone**.

Two testing methods, pick based on what you have available:

- **Physical device (preferred, required for a true pass/fail):** Settings →
  Accessibility → VoiceOver → on. Use it exactly as intended: single-finger
  tap/swipe to move focus and hear the announcement, double-tap anywhere to
  activate. This is the only way to hear the actual announced strings.
- **Simulator + Accessibility Inspector (fallback, structural check only):**
  `Xcode > Open Developer Tool > Accessibility Inspector` → target the booted
  Simulator → hover/click elements to see their **Label**, **Value**, and
  **Traits** in the inspector panel. This proves the label/trait/value exist
  and read correctly, but does not prove real touch-gesture activation or
  actual spoken phrasing — use it only when a physical device isn't available.

**Build once per branch:**
```bash
cd .a11y-worktrees/<branch-dir>   # each branch already has its own worktree
xcodebuild build -project Meshtastic.xcodeproj -scheme Meshtastic \
  -destination 'platform=iOS Simulator,id=<YOUR_BOOTED_SIM_UDID>' -configuration Debug
xcrun simctl install <UDID> <path/to/Meshtastic.app from build output>
xcrun simctl launch <UDID> gvh.MeshtasticClient
```
(`xcrun simctl list devices | grep Booted` to get UDID; DerivedData path is
printed near the end of the build log, or `xcodebuild -showBuildSettings | grep TARGET_BUILD_DIR`.)

**⚠️ Known cross-branch conflict — read before merging:**
All 9 branches independently contain an identical commit (`50cf3657`, fixing
`TextMessageField.swift` send/cancel-reply/emoji-picker button labels) that is
**not yet in `main`**. Whichever branch merges first will land it cleanly;
**rebase the remaining 8 branches onto `main` afterward** so this duplicate
drops out automatically, or you'll get repeated no-op diffs / conflicts on
every subsequent PR.

**⚠️ Known task conflict — `medium-polish` vs `pr8-dynamic-type`:**
Both branches fix the same Compact Widgets Dynamic Type clipping (T042), on
the same lines, with **two different approaches**:
- `medium-polish`: removes the `maxHeight: 140` cap entirely (`.frame(minHeight: 120)`, no max).
- `pr8-dynamic-type`: keeps the frame cap but scales the font down (`@ScaledMetric` + `.minimumScaleFactor(0.5)` + `.lineLimit(1)`).

Pick one before merging both — they'll conflict. `pr8-dynamic-type` also has
no worktree set up and its `main..branch` diff shows unrelated file drift
(stale base) — rebase it onto current `main` before testing/opening a PR.

**Task numbers referenced below are the original audit's T001–T043 IDs** in
`specs/016-accessibility-audit/tasks.md` (as of commit `96875d36`).

---

## 1. `a11y/live-activity` — T001 (Live Activity / Dynamic Island)

**Files:** `Widgets/WidgetsLiveActivity.swift`

**No live BLE data needed to see the labels exist (Accessibility Inspector
check), but seeing the actual Live Activity requires a running mesh session.**

Steps:
1. Build/install this branch, connect to (or simulate) an active mesh session so a Live Activity is running.
2. Long-press the Dynamic Island (or check the Lock Screen presentation) to see the expanded Live Activity.
3. With VoiceOver on (physical device) or Accessibility Inspector (simulator), inspect:
   - The "X of Y nodes online" text in the **expanded trailing region** → should announce as one grouped element, not one VoiceOver stop per digit/word.
   - The **compact-leading** Dynamic Island region (small pill) → "X nodes online".
   - The **minimal** presentation (multiple Live Activities stacked) → "X nodes online".
   - The Live Activity's own in-app header row (`LiveActivityView`) → "X of Y nodes online".
4. Pass criteria: each of the 4 locations reads as a single combined VoiceOver stop with the exact node-count phrase, not "Label, Label, Label" fragments or generic "Text".

---

## 2. `a11y/messaging-badges` — T003, T004

**Files:** `MessageEntityExtension.swift`, `ChannelMessageRow.swift`, `MessageText.swift`, `UserList.swift`, `UserMessageRow.swift`, `MessageDestination.swift`

Steps:
1. Messages tab → open any channel with messages that have badges (Verified sender, Store-and-forward, Detection sensor, or a translated message).
2. Focus each flagged message row.
   - **Pass (T003):** the combined accessibility label includes **every** active badge (Verified / Store-and-forward / Detection sensor / Showing translated text), not just Encrypted/Verified. Compare against what badge icons are actually visible on the row — labels and visible badges must match 1:1.
3. Messages tab → Direct Messages list → find a contact row with an unread indicator and/or lock/star icon.
   - **Pass (T004):** the unread dot is not separately announced (should be `.accessibilityHidden` and folded into value/label instead), lock/star icons have their own labels, and the whole row reads as one combined element (matches the working pattern already used in `ChannelList.swift`).

---

## 3. `a11y/map-drag-handles` — T010, T011

**Files:** `GeofenceBoundsSelectorView.swift`, `RegionSelectorView.swift`, `DiscoveryMapView.swift`, `DiscoveredNodeEntity.swift`

Steps:
1. Navigate to a **geofence editor** (Node Detail → geofence/region settings) and a **region selector** (Nodes → offline region download, if applicable).
2. Focus a drag handle on the map boundary.
   - **Pass (T010):** VoiceOver reports a custom action or adjustable value (swipe up/down = increment/decrement, or rotor-accessible "Move north/south/east/west" custom actions) — a real gesture-only drag is no longer the only way to move the bound.
3. Settings → Discovery → Discovery Map view, with at least one discovered device plotted.
   - **Pass (T011):** each device pin's `Annotation` announces the actual `device.displayName`, not an empty/blank title.

---

## 4. `a11y/tap-gesture-traits` — T005, T006, T007, T008, T009

**Files:** `Connect.swift`, `IndoorAirQuality.swift`, `MetricsColumnDetail.swift`, `NodeDetail.swift`, `AppLog.swift`

| Task | Screen | Steps |
|---|---|---|
| T005 | Node Detail → Environment or Air Quality metrics log → tap a metric column | Focus the row; double-tap (VoiceOver) or click (Inspector) should activate it. Requires environment/air-quality history data. |
| T006 | Connect tab → discovered Nymea (mPWRD-OS) device row | Requires a real Nymea device broadcasting on the network — otherwise inspect statically via code review only. |
| T007 | Weather → Indoor Air Quality view → legend row | Focus the legend tap row; should register as a button and announce Visible/Hidden value. Requires air-quality data. |
| T008 | Settings → Logs (App Log) → Filter button → **Packet Stream** row | This is the actual `streamRow` fix. Focus it — should announce as a switch/checkbox (not generic unlabeled row), and double-tap/click toggles it. **No live data needed — always reachable.** |
| T009 | Any Node → Node Detail → "First heard" / "Last heard" rows | Focus each row — should announce with a button trait and support a VoiceOver activation action (previously combined but not activatable). Requires at least one known node. |

T008 is the only task in this branch guaranteed testable with zero setup —
start there.

---

## 5. `a11y/action-buttons` — T012, T013, T014, T015, T016 (shared base), T017, T018, T019, T020, T021, T022, T023

**Files:** 24 files — every icon-only button across Settings, Firmware, Map, Provisioning, RouteRecorder, Channels, AppLog, WifiProvisioning.

This is the largest branch. Test by category rather than file-by-file:

1. **Close buttons (T012–T014):** open NRF DFU sheet, ESP32 BLE OTA sheet, and (Mac Catalyst only) AppLogFilter/LogDetail/NodeListFilter/MetricsColumnDetail/MapSettingsForm/WaypointForm/MapLegend/InvalidVersion/DirectMessagesHelp/NodeListHelp/ChannelsHelp — each close (`xmark`) button should announce "Close", not "Button".
2. **Help/filter toggles (T017, T018):** Channels, ShareChannels, ChannelList, UserList, NodeList — tap the help (`?`) and filter icons; label should read "Show help"/"Hide help" reflecting current state (not a static label).
3. **Action icons (T019):** AppLog export/refresh, Firmware retry (both branches of the `#if`), BackupRowView restore, RouteRecorder record button, ChannelForm generate-key, DiscoverySummaryView export-PDF, MeshMapMK open-map-window (macOS only), WaypointForm edit, SecureInput show/hide password — each should have a specific action-name label.
4. **Copy buttons (T020):** WifiProvisioningView → 3 separate copy (`doc.on.doc`) buttons for network name / password / PSK — each must announce a **different, field-specific** label, not one generic "Copy".
5. **Map buttons (T021–T023):** MeshMapMK clear-trace-route (`trash`) and map-settings (`info.circle`) buttons; NodeMapSwiftUI's 3 unlabeled buttons — compare against already-correct neighboring buttons for consistent labeling.

**Coverage note:** matches its own "T017–T023" checkoff commit but the diff
also includes T012–T016 — the tracker undercounts this branch's actual scope.

---

## 6. `a11y/localization-contrast` — T032, T033, T034, T035, T036, T037, T038

**Files:** `Localizable.xcstrings`, `Color.swift`, `FirmwareUpdateNotifier.swift`, `LockdownSheet.swift`, `MessageSearchBar.swift`, `FormattingToolbarButtons.swift`, `Channels.swift`, `AnimatedNodePin.swift`, `FoxhuntCompassView.swift`

1. **Localization (T032–T036):** switch device language (Settings → General → Language & Region → add a second language, e.g. German) and re-check: `ChannelStatusIcon` a11y strings (Channels.swift), formatting-toolbar buttons, firmware-update-notifier strings (surfaced via Connect.swift banner), Lockdown sheet strings, message search bar — **all must translate**, not stay hardcoded English.
2. **Contrast (T037, T038):** find a node pin on the map with a light background color — the pin's text/foreground should switch to black text; a dark-background pin should get white text. This is driven by the shared `Color.isLight()` WCAG fix, so also spot-check `CircleText.swift` and the Watch app's `WatchCircleText.swift` (same formula, no separate diff needed — they inherit the fix for free).
3. Run `MeshtasticTests/ExtensionTests.swift` (has new/updated cases for this) to confirm the WCAG relative-luminance formula unit tests pass before doing the visual check.

---

## 7. `a11y/medium-polish` — T039, T040, T042 (conflicts with pr8-dynamic-type), T043

**Files:** 24 files — Connect.swift, Compact Widgets (10 files), HelpItem.swift, PowerMetrics.swift, ChannelList.swift, UserList.swift, DeviceMetricsLog.swift, MapLegend.swift, PowerMetricsLog.swift, WifiProvisioningView.swift, AppData.swift, Firmware.swift, CircularProgressView.swift, TAKServerConfig.swift

1. **Element grouping (T039):** visit each of Power/Device Metrics Log, Help items, Map Legend, TAK Server Config, Firmware, Connect, WifiProvisioning ActivityRow, AppData — each icon+number/label pair should now be **one** VoiceOver stop, not separate stops per glyph.
2. **Firmware progress (T040):** start a firmware update (NRF DFU, ESP32 Wifi/BLE OTA, or the Chirpy game view) — the shared `CircularProgressView` should announce "Update progress, N percent" as a single element.
3. **Dynamic Type widgets (T042):** ⚠️ see conflict note at top — this branch removes the widget height cap. Test at largest accessibility text size (Settings → Accessibility → Display & Text Size → largest) that Compact Widget text no longer clips.
4. **Row growth (T043):** at largest Dynamic Type size, Channel list and Direct Message list rows should grow taller instead of clipping/truncating fixed 62pt rows.

---

## 8. `a11y/values-signals` — T024, T025, T026, T027, T028, T029, T030, T031

**Files:** `LoRaSignalStrength.swift`, `AirQualityIndex.swift`, `ClusterMapView.swift`, `NodeListFilter.swift`, `NodeListItemCompact.swift`, `MeshMapMK.swift`, `TraceRouteLog.swift`, `DiscoveryScanView.swift`, `AppLogFilter.swift`

**Coverage note:** the branch's own "check off T029-T031" commit significantly
undercounts this branch — it actually covers 8 tasks (T024–T031). Update
`tasks.md` to reflect this when opening the PR.

1. **T024:** Node List filter → "Hops Away" slider (renamed from wrong "Speed" label) — should announce "All" / "Direct" / "1 hop away" / "N hops away" as its value.
2. **T025:** Settings → Logs → Filter → Categories/Log Levels selection rows — checkmark rows should have `.isSelected` trait when checked.
3. **T026:** Settings → Discovery → start a scan → "Time Remaining" + progress bar should combine into one element announcing "N percent".
4. **T027:** any screen showing the LoRa signal strength gauge (compact) — should announce "Signal strength, Signal <tier>".
5. **T028:** Weather → Air Quality Index gauge view — should announce "Air quality index, AQI N, <tier>".
6. **T029:** Node Detail → Trace Route log — hop signal-strength arrows should have per-tier labels, not just color.
7. **T030:** Node List (compact rows) — signal icon should visually vary shape/symbol per tier (not just color), each with its own label.
8. **T031:** Map view → an active trace route — polyline width/dash pattern should vary by SNR tier, not just hue (test with grayscale/color-blind simulation via Accessibility Inspector's color filters, or Settings → Accessibility → Display & Text Size → Color Filters, to confirm tiers stay distinguishable).

---

## 9. `a11y/pr8-dynamic-type` — T042 (conflicts with medium-polish)

**Files (from its own commit `be09b3c4`, not the noisy `main..branch` diff — this branch needs a rebase first):** Compact Widgets (9 files), `PowerMetrics.swift`

⚠️ **Rebase onto current `main` before testing** — this branch's diff against
`main` currently includes ~90 unrelated file changes from base drift.

⚠️ **Resolve the T042 conflict with `medium-polish` first** (see top of doc) —
don't test/merge both as-is.

Once rebased and the conflict is resolved in favor of one approach:
1. Settings → Accessibility → Display & Text Size → largest Dynamic Type size.
2. View each Compact Widget (Distance, Humidity, Particulate Matter, Pressure, Radiation, Rainfall, Soil, Weather Conditions, Weight, Wind) on the relevant metric screens.
3. Pass: value text scales via `@ScaledMetric` and shrinks (`.minimumScaleFactor(0.5)`, `.lineLimit(1)`) instead of clipping/truncating.

---

## Suggested merge order

1. Merge **one** of `medium-polish` / `pr8-dynamic-type` first (they conflict on T042) — recommend `medium-polish` since it's already in a worktree and ready.
2. Merge the rest in any order, **rebasing each remaining branch onto `main` after every merge** to drop the shared `TextMessageField.swift` commit duplication.
3. After all merges, update `specs/016-accessibility-audit/tasks.md` checkboxes for T024–T028 (values-signals) and T012–T016 (action-buttons), which are currently under-reported.
