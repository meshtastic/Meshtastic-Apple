# Cross-Artifact Analysis: Lockdown Mode

**Created**: 2026-05-13
**Inputs analyzed**:
- `spec.md`
- `plan.md`
- `research.md`
- `data-model.md`
- `contracts/coordinator-protocol.md`
- `quickstart.md`
- `tasks.md`
- `checklists/requirements.md`
- `checklists/security.md`

**Scope**: Detect contradictions, missing coverage, dangling references, and duplications across the artifacts before implementation begins.

---

## ✅ Consistent

| Topic | Where stated | Verdict |
|---|---|---|
| Wire format: `AdminMessage.lockdown_auth` (104) outbound, `FromRadio.lockdown_status` (18) inbound | spec / plan / contracts / tasks | Identical across all four. |
| State machine: 7 cases (`none`, `needsProvision`, `locked(reason)`, `unlocked(boots, until)`, `unlockFailed`, `unlockBackoff(secs, deadline)`, `lockNowAcknowledged`) | spec / data-model / contracts | Identical. |
| Per-peripheral cache keyed by `CBPeripheral.identifier` (UUID) | spec FR-008 / data-model "Persistence layout" / tasks T005 | Consistent. |
| `ObservableObject` + `@Published` (not `@Observable`) | research R2 / plan Technical Context / contracts coordinator surface | Consistent. iOS 16.4 baseline cited as the reason. |
| Outbound MeshPacket invariants (`to=myNodeNum`, `from`-unset, `wantAck`, `hopLimit=hopStart=7`, `priority=.reliable`, no `pkiEncrypted`) | spec Architecture / contracts LockdownSender / tasks T008 | Consistent and emphasized in all three. |
| Lock-Now race resolution (next inbound `LOCKED` *or* disconnect resolves `pendingLockNow`) | spec FR-014 + US-3 / data-model invariants / tasks T018 | Consistent. |
| Auto-replay rules (cache hit on `LOCKED` → silent send; cache delete on `UNLOCK_FAILED, backoff=0` from auto attempt) | spec US-4 / data-model invariants / tasks T022 / security checklist CHK004 | Consistent. |

---

## ⚠️  Gaps / open items

### G1. App-uninstall cache lifetime (CHK006)

**Where**: `checklists/security.md` raises it; not addressed elsewhere.
**Issue**: iOS Keychain entries written with default flags **survive** app uninstall. Subsequent reinstall recovers them. For a security feature this is a deliberate decision either way.
**Recommendation**: Add a one-sentence assumption to `spec.md` Assumptions section: "Passphrase cache survives app uninstall by design (Keychain default); a fresh install on the same device auto-reconnects to previously-paired hardened nodes."
**Severity**: Low — current behaviour is reasonable; just needs to be explicit.

### G2. Passphrase wipe in coordinator on response (CHK015)

**Where**: `contracts/coordinator-protocol.md` invariant 4 covers it ("non-nil only between submit and the next handle"); spec.md is silent.
**Issue**: A reader of the spec alone wouldn't know the pendingPassphrase string lives in memory for ~milliseconds and is wiped on response.
**Recommendation**: Add to NFR-002: "Passphrase strings held in memory by the coordinator MUST be cleared as soon as the `LockdownStatus` response (success or failure) is processed; never persisted in the coordinator beyond that window."
**Severity**: Low — already specified in the contract; just promote to spec NFR for visibility.

### G3. `state == STATE_UNSPECIFIED` handling (CHK030)

**Where**: All four spec/plan/data-model/contracts artifacts are silent.
**Issue**: Forward-compat hole — if the firmware ever emits a `LockdownStatus` with the default-zero `state`, the coordinator behaviour is undefined.
**Recommendation**: Add to `contracts/coordinator-protocol.md` (or `data-model.md`): "`STATE_UNSPECIFIED` MUST be ignored — coordinator returns without mutating state." Add corresponding test to T013 list.
**Severity**: Medium — silent drop is the only safe behaviour, but it should be documented and tested.

### G4. Device clock skew UX hint (CHK021)

**Where**: `spec.md` Edge Cases mentions clock skew, defers to firmware-reported state.
**Issue**: If the user sees "Expires: 2 hours ago" but the device claims unlocked, that's confusing.
**Recommendation**: Optional polish — add a small ⚠ glyph next to the expiry row when `validUntilEpoch < now()` (purely UI cue, no behavioural change). Add as a US-5 enhancement task or punt to a follow-up issue.
**Severity**: Low — polish, not correctness.

### G5. Existing banners to audit (T025)

**Where**: `tasks.md` T025 says "Audit existing `Meshtastic/Views/**/*.swift` for action-prompting banners ... List captured in this task's PR description."
**Issue**: The task is open-ended. A concrete pre-implementation grep would let reviewers verify the audit was complete.
**Recommendation**: Run the grep now and embed the list in T025 description before implementation. Suggested patterns: `"unset"`, `"please configure"`, `"required"`, `Banner`, `Callout`.
**Severity**: Low — sharpens the task definition.

---

## 🔁 Duplications

### D1. Outbound MeshPacket invariants restated in 3 places

**Where**: `spec.md` Architecture, `contracts/coordinator-protocol.md` LockdownSender doc-comment, `tasks.md` T008.
**Analysis**: Intentional — the firmware ToRadio gate is strict, and the repetition prevents drift. **Keep.**

### D2. State transitions described twice

**Where**: `spec.md` "User Scenarios & Testing" describes the user-facing flow; `data-model.md` describes the same as a state diagram.
**Analysis**: Different audiences (UX vs implementer). **Keep.**

---

## 🪢 Dangling references

| Reference | Found in | Resolved? |
|---|---|---|
| `meshtastic/protobufs` PR #911 | spec / plan / research / tasks | Yes — public PR, merged. |
| Firmware PR #10349 (`MESHTASTIC_LOCKDOWN`) | spec / quickstart | Yes — public PR. |
| ATAK plugin PR #2 (POC) | spec.md Input | Yes — public, merged. |
| Meshtastic design standards URL | spec / tasks T027 | Yes — public. |
| `KeychainHelper` | research R1 / plan / tasks T004 | Yes — exists at `Meshtastic/Helpers/KeychainHelper.swift`. |
| `LocationsHandler` / `MapDataManager` as `ObservableObject` precedents | research R2 | Yes — verified by `grep`. |
| `.specify/memory/constitution.md` | plan Constitution Check | Exists but unfilled; flagged in plan. |

No broken references.

---

## 📊 Task → Requirement coverage

Every Functional / Non-Functional requirement maps to ≥ 1 task.

| Requirement | Tasks |
|---|---|
| FR-001 (detect `lockdown_status`) | T009 |
| FR-002 (locked sheet) | T011 + T012 |
| FR-003 (provision sheet) | T014 |
| FR-004 (send `lockdown_auth`) | T008 + T006 |
| FR-005 (optional TTL fields) | T011 |
| FR-006 (UNLOCK_FAILED + backoff) | T013 (test) + T011 (UI) + T006 (state) |
| FR-007 (Lock Now) | T017 + T006 |
| FR-008 (encrypted cache) | T005 |
| FR-009 (auto-replay) | T006 + T022 (test) |
| FR-010 (clear on failed auto-replay) | T006 + T022 (test) |
| FR-011 (TTL display) | T024 |
| FR-012 (full-screen blocker) | T012 |
| FR-013 (banner suppression) | T025 |
| FR-014 (per-connection reset + lock-now disconnect race) | T006 + T018 |
| NFR-001 (Keychain) | T004 + T005 |
| NFR-002 (no logs, SecureField) | T011 + T026 |
| NFR-003 (≤ 5 s submit→unlocked) | T028 (manual verification) |
| NFR-004 (a11y) | T027 |

No orphan tasks. No unaddressed requirements.

---

## 📈 User-story → task coverage

| User Story | Foundational tasks | Story-specific tasks |
|---|---|---|
| US-1 (Unlock locked) | T001–T010 | T011, T012, T013 |
| US-2 (Provision) | T001–T010 | T014, T015, T016 |
| US-3 (Lock Now) | T001–T010 | T017, T018, T019, T020 |
| US-4 (Cached replay) | T001–T010 (logic in T006) | T021, T022, T023 |
| US-5 (TTL display) | T001–T010 | T024 |
| Cross-cutting | — | T025, T026, T027 |
| Verification | — | T028 |

Every user story has at least one independently testable task and at least one paired unit test (US-1/2/3/4) or a checklist gate (US-5).

---

## Recommendations before `/speckit.implement`

1. **Apply G1, G2, G3 edits to `spec.md`** (small additions to Assumptions and NFR-002, plus `STATE_UNSPECIFIED` handling).
2. **Pre-fill T025** with the banner-audit list (run a grep, capture results in the task description).
3. **Optionally apply G4** as a US-5 polish item or punt.
4. **Defer the `.specify/memory/constitution.md` work** — not blocking this feature.

If all of the above are addressed (or deliberately deferred), proceed to `/speckit.implement`.
