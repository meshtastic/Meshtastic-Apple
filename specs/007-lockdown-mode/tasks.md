---
description: "Task list — Lockdown Mode (007)"
---

# Tasks: Lockdown Mode

**Input**: Design documents in `/specs/007-lockdown-mode/` (plan.md, research.md, data-model.md, contracts/, quickstart.md)

**Tests**: Included — the spec calls out an XCTest target under `MeshtasticTests/`. Unit tests are limited to the coordinator state machine and the passphrase store (UI is exercised via the quickstart, not snapshot tests).

**Organization**: Tasks grouped by user story (US-1 … US-5). Each story can land as an independent commit; US-1 + US-2 together are the MVP.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Independent file / no shared mutation — safe to parallelize.
- **[Story]**: User story this task supports (US-1 … US-5, or **F** = foundational).
- All paths are repo-relative.

## Path conventions (per plan.md)

- App source: `Meshtastic/`
- Tests: `MeshtasticTests/`
- Spec artifacts: `specs/007-lockdown-mode/`

---

## Phase 1: Setup

- [x] T001 [F] Bump `MeshtasticProtobufs` package's `protobufs` submodule (or generated-source pin) to a `meshtastic/protobufs` revision that includes PR #911 (target commit: same hash used by the Android branch — `1c62540` or newer). Regenerate Swift bindings. **Acceptance**: `Meshtastic_LockdownAuth` and `Meshtastic_LockdownStatus` types resolve in the Xcode project; new oneof cases `.lockdownAuth` and `.lockdownStatus` exist.
- [x] T002 [F] [P] Verify the Swift type names in `research.md §R3` against the generated output. Update `research.md` if anything diverges.

---

## Phase 2: Foundational (Blocking)

Must complete before any user-story phase begins.

- [x] T003 [F] Create `Meshtastic/Model/LockdownState.swift` per `data-model.md` (the `LockdownState` enum with all seven cases, `Equatable` conformance).
- [x] T004 [F] Extend `Meshtastic/Helpers/KeychainHelper.swift`: add an optional `accessibility: CFString = kSecAttrAccessibleWhenUnlocked` parameter to `save(...)`; thread through the `kSecAttrAccessible` write. Preserves existing call sites (default unchanged).
- [x] T005 [F] Create `Meshtastic/Helpers/LockdownPassphraseStore.swift`:
  - `struct StoredPassphrase: Codable` (passphrase + 2× UInt32 TTL fields)
  - `final class LockdownPassphraseStore` with `get(peripheralID:) -> StoredPassphrase?`, `save(peripheralID:_:) -> Bool`, `delete(peripheralID:) -> Bool`
  - JSON-encode `StoredPassphrase`, store via `KeychainHelper.standard.save(key: peripheralID.uuidString, value: jsonString, service: "meshtastic.lockdown.passphrase", accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)`
  - `read(...)` decodes JSON back; on decode failure, delete the entry and return nil
- [x] T006 [F] Create `Meshtastic/Helpers/LockdownCoordinator.swift` per `contracts/coordinator-protocol.md`:
  - `@MainActor final class LockdownCoordinator: ObservableObject`
  - `@Published private(set) var state: LockdownState = .none`
  - `@Published private(set) var sessionAuthorized: Bool = false`
  - All public methods (`onConnect`, `onDisconnect`, `handle`, `submitPassphrase`, `lockNow`, `forgetCachedPassphrase`)
  - Internal flags: `currentPeripheralID`, `wasAutoAttempt`, `pendingPassphrase`, `pendingBootsRemaining`, `pendingValidUntilEpoch`, `pendingLockNow`
  - State-transition logic as documented in `data-model.md` (auto-replay on `LOCKED` with cache hit; cache delete on auto-replay `UNLOCK_FAILED` with `backoff == 0`; etc.)
- [x] T007 [F] Define the `LockdownSender` protocol (top of `LockdownCoordinator.swift` is fine — it's a tightly-coupled dependency).
- [x] T008 [F] **Architectural deviation from plan**: ToRadio sends actually go through `AccessoryManager` (singleton, `@MainActor ObservableObject`), not `BluetoothManager` (which turned out to be a 27-line scan/connect stub). Created `Meshtastic/Accessory/Accessory Manager/AccessoryManager+Lockdown.swift` making `AccessoryManager` conform to `LockdownSender`. `sendLockdownAuth(...)` builds the `MeshPacket` per the contract (`to = myNodeNum`, `from` unset, `wantAck = true`, `hopLimit = hopStart = 7`, `priority = .reliable`, `decoded.portnum = .adminApp`, payload = `AdminMessage{lockdownAuth: …}.serializedData()`, **no `pkiEncrypted`**) and enqueues via existing `send(toRadio, debugDescription:)`. Lifecycle hooks added in `AccessoryManager+Connect.swift` (`onConnect(peripheralID:)` at the first connect step) and `AccessoryManager.swift#closeConnection` (`onDisconnect()`). Added `var lockdownCoordinator: LockdownCoordinator?` stored property to `AccessoryManager`.
- [x] T009 [F] In `Meshtastic/Accessory/Accessory Manager/AccessoryManager.swift#processFromRadio`, added a `case .lockdownStatus(let status):` branch (before `default:`) that forwards to `lockdownCoordinator?.handle(status)`. (The plan said `MeshPackets.swift` but the actual `FromRadio.payloadVariant` switch lives in `AccessoryManager`.)
- [x] T010 [F] In `Meshtastic/MeshtasticApp.swift`, instantiated `LockdownCoordinator()` in `init()`, called `lockdown.setSender(accessoryManager)`, stored it as `@StateObject private var lockdownCoordinator`, set `accessoryManager.lockdownCoordinator = lockdown`, and added `.environmentObject(lockdownCoordinator)` to the root `WindowGroup` modifier chain.

**Checkpoint**: foundation builds, app launches without lockdown firmware behaving any differently than before (coordinator stays at `.none`).

---

## Phase 3: User Story 1 — Unlock a Locked Node (Priority: P1) 🎯 MVP

**Goal**: A connected node reporting `LOCKED` triggers a passphrase sheet; a correct passphrase unlocks the session.

- [x] T011 [US-1] Create `Meshtastic/Views/Lockdown/LockdownSheet.swift`:
  - `struct LockdownSheet: View` that switches on `coordinator.state` and renders the appropriate sub-view
  - `LockedSheetContent` — `SecureField` for passphrase, optional `TextField`s for "Boots remaining" (UInt) and "Hours valid" (UInt), Submit button (disabled when passphrase empty / > 32 bytes / coordinator's `myNodeNum` not yet known)
  - On Submit, compute `validUntilEpoch = hoursValid > 0 ? UInt32(Date().timeIntervalSince1970) + hoursValid * 3600 : 0` and call `coordinator.submitPassphrase(...)`
- [x] T012 [US-1] In `Meshtastic/Views/ContentView.swift`, observe `@EnvironmentObject var lockdown: LockdownCoordinator`; present `LockdownSheet()` as a `.fullScreenCover` when `state` ∈ `{ .needsProvision, .locked, .unlockFailed, .unlockBackoff }` (and dismiss on `.unlocked` / `.lockNowAcknowledged` / `.none`). Use a derived binding so the cover can't be swipe-dismissed.
- [x] T013 [US-1] In `MeshtasticTests/Helpers/LockdownCoordinatorTests.swift`:
  - `testHandle_locked_withoutCachedPassphrase_transitionsToLocked()`
  - `testHandle_locked_withCachedPassphrase_autoReplaysSilently()` (asserts `sender.sendLockdownAuth` was called and state stayed `.none`-ish, not `.locked`)
  - `testSubmitPassphrase_thenHandleUnlocked_transitionsToUnlocked_andSavesPassphrase()`
  - `testHandle_unlockFailed_withBackoffZero_transitionsToUnlockFailed()`
  - `testHandle_unlockFailed_withBackoffNonZero_transitionsToUnlockBackoff()`
  - `testHandle_stateUnspecified_isIgnored()` (G3 from analysis.md)

**Checkpoint**: with a hardened device available, the quickstart §US-1 flow runs to completion.

---

## Phase 4: User Story 2 — Provision a New Lockdown Passphrase (Priority: P1)

**Goal**: A connected node reporting `NEEDS_PROVISION` triggers a creation sheet; submission persists a passphrase and unlocks the session.

- [x] T014 [US-2] Extend `LockdownSheet.swift` (created in T011) with a `NeedsProvisionSheetContent` variant:
  - Hint text: "First-time setup — pick a passphrase you can re-enter"
  - Same Submit semantics as `LockedSheetContent`, just different title/copy
- [x] T015 [US-2] In `MeshtasticTests/Helpers/LockdownCoordinatorTests.swift`:
  - `testHandle_needsProvision_transitionsToNeedsProvision()`
  - `testSubmitPassphrase_fromNeedsProvision_sendsAuthAndCachesOnUnlocked()`
- [x] T016 [US-2] [P] Add `Localizable.xcstrings` entries for the provisioning UI: title, hint, button labels, validation message.

**Checkpoint**: quickstart §US-2 runs to completion.

---

## Phase 5: User Story 3 — Lock Now (Priority: P2)

**Goal**: An operator can re-lock an unlocked device with a single action from `Settings → Security`.

- [x] T017 [US-3] In `Meshtastic/Views/Settings/Config/SecurityConfig.swift`, add a "Lock Now" row gated on `coordinator.state == .unlocked`. Tapping shows a `.alert` confirming the action; the confirm action calls `coordinator.lockNow()`.
- [x] T018 [US-3] Extend `LockdownCoordinator` to handle the disconnect-as-ack race: in `onDisconnect()`, if `pendingLockNow == true`, transition to `.lockNowAcknowledged` (clearing the flag), then to `.none` after a short delay so the UI can show a confirmation toast before navigating away.
- [x] T019 [US-3] In `MeshtasticApp.swift` (or wherever `BluetoothManager` lives), watch `coordinator.state`; when it transitions to `.lockNowAcknowledged`, call `bluetoothManager.disconnect()`.
- [x] T020 [US-3] In `MeshtasticTests/Helpers/LockdownCoordinatorTests.swift`:
  - `testLockNow_setsPendingLockNow_andSendsEmptyPassphraseAuth()`
  - `testHandle_locked_withPendingLockNow_transitionsToLockNowAcknowledged()`
  - `testOnDisconnect_withPendingLockNow_transitionsToLockNowAcknowledged()`

**Checkpoint**: quickstart §US-4 runs to completion.

---

## Phase 6: User Story 4 — Cached Passphrase Auto-Reconnect (Priority: P2)

**Goal**: A returning user with a cached passphrase reconnects without re-entering it.

> Auto-replay logic already lands in `LockdownCoordinator.handle(_:)` during T006. This phase adds the explicit tests, the cache-failure UX path, and the "Forget Stored Passphrase" affordance.

- [x] T021 [US-4] In `SecurityConfig.swift`, add a "Forget Stored Passphrase" row visible when a cache entry exists for the connected peripheral; calls `coordinator.forgetCachedPassphrase()` and shows a brief confirmation.
- [x] T022 [US-4] In `MeshtasticTests/Helpers/LockdownCoordinatorTests.swift`:
  - `testHandle_unlockFailed_withWasAutoAttempt_clearsCacheAndTransitionsToLocked()`
  - `testHandle_unlockFailed_withWasAutoAttempt_andBackoff_preservesCacheAndTransitionsToBackoff()`
- [x] T023 [US-4] In `MeshtasticTests/Helpers/LockdownPassphraseStoreTests.swift`:
  - `testSaveThenRead_roundtripsPassphraseAndTTL()`
  - `testDelete_removesEntry()`
  - `testRead_returnsNilForUnknownPeripheral()`

**Checkpoint**: quickstart §US-3 (auto-reconnect) and §US-5 (wrong passphrase) run to completion.

---

## Phase 7: User Story 5 — View Session Token Status (Priority: P3)

**Goal**: Display `boots_remaining` and `valid_until_epoch` while unlocked.

- [x] T024 [US-5] In `SecurityConfig.swift`, when `coordinator.state` is `.unlocked(let boots, let until)`, render two rows:
  - "Boots remaining: {boots}"
  - If `until == 0`: "No time limit"; else: "Expires: {Date(timeIntervalSince1970: TimeInterval(until)).formatted(date: .abbreviated, time: .shortened)}"

**Checkpoint**: quickstart §US-5 (TTL display) runs to completion.

---

## Phase 8: Cross-cutting (Banner suppression + privacy + design)

- [x] T025 [P] Gate action-prompting banners on `lockdown.sessionAuthorized` so they don't appear when the user can't act on them. Audit completed (see `analysis.md` G5): the only currently-existing banner of this kind is the **region-unset** block at `Meshtastic/Views/Connect/Connect.swift:195` (gated by `isUnsetRegion`). Update its outer `if isUnsetRegion {` to `if isUnsetRegion && lockdown.sessionAuthorized {` (or, equivalently, suppress the assignment at lines 359-362 when the coordinator state is anything other than `.unlocked`). If new banners are added later, follow the same pattern.
- [x] T026 [P] Privacy audit: `grep -rni "passphrase" Meshtastic/ | grep -v Localizable | grep -v "//.*passphrase"` — confirm no `Logger`/`os_log`/`print` site touches the passphrase value.
- [x] T027 [P] Design-standards pass: SF Symbols (`lock.fill`, `lock.open.fill`, `lock.trianglebadge.exclamationmark`), Dynamic Type, VoiceOver labels, Reduce Motion respect. Reviewed against `https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md`.

---

## Phase 9: Manual verification

- [ ] T028 Run the full `quickstart.md` flow on a real iPhone against a hardened firmware build. Capture screenshots of each sheet variant; attach to the PR.

---

## Dependency graph (compact)

```
T001 ──┐
       ├─▶ T003 ─▶ T006 ─▶ T011 ─▶ T012 ─▶ T013   (US-1)
T002 ──┘            │      │
                    │      └─▶ T014 ─▶ T015 ─▶ T016   (US-2)
                    │      └─▶ T017 ─▶ T018 ─▶ T019 ─▶ T020   (US-3)
                    │      └─▶ T021 ─▶ T022 ─▶ T023   (US-4)
                    │      └─▶ T024   (US-5)
T004 ─▶ T005 ───────┘
T007 (in T006) ─▶ T008 ─▶ T009 ─▶ T010
T025, T026, T027 — parallel, no source dependencies
T028 — last, depends on US-1 through US-5
```

## MVP scope

US-1 + US-2 + foundational (T001–T010) is the minimum viable slice — unlocks and provisions hardened nodes. US-3 (Lock Now), US-4 (forget cache), and US-5 (TTL display) can land separately.
