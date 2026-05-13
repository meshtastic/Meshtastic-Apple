# Security Checklist: Lockdown Mode

**Purpose**: Validate that the **specification** of the lockdown feature is itself secure, complete, and unambiguous before any implementation work begins. This is a unit-test suite for the requirements — not a pen-test of the eventual code.

**Created**: 2026-05-13
**Feature**: [spec.md](../spec.md)
**Domain**: security

> Each item below is `[ ]` (unverified) → `[x]` (verified) → `[!]` (concern surfaced; resolve in `/speckit.analyze` or `/speckit.clarify`).

## CHK001-006 — Credential handling at rest

- [x] CHK001: Spec mandates that passphrases are stored in a platform-encrypted store (Keychain), not Core Data, not UserDefaults, not files. (NFR-001)
- [x] CHK002: Spec specifies the Keychain accessibility class explicitly (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` or stricter). (NFR-001)
- [x] CHK003: Spec specifies per-peripheral keying so cached credentials for one device don't leak to another. (FR-008, Edge Cases)
- [x] CHK004: Spec says cached entries are deleted when auto-replay fails with `backoff_seconds == 0`. (FR-010, US-4 Acceptance 2)
- [x] CHK005: Spec covers cache invalidation when a node is re-provisioned (auto-replay fails → cache cleared). (Edge Cases)
- [ ] CHK006: Spec covers cache lifetime across **uninstall** of the app — the Keychain entry survives reinstall by default; is that the intended behaviour, or should the entry be `kSecAttrSynchronizable=false` + linked to an app-group that gets wiped? (Open question — surface in `/speckit.analyze`.)

## CHK007-011 — Credential handling in transit

- [x] CHK007: Spec mandates `pkiEncrypted` MUST NOT be set on the outbound `AdminMessage.lockdown_auth` packet. (Architecture: Outbound builder)
- [x] CHK008: Spec requires `MeshPacket.to == myNodeNum` and forbids broadcast (firmware ToRadio gate). (Architecture: Outbound builder)
- [x] CHK009: Spec requires `MeshPacket.from == 0` (proto default) so firmware treats the packet as local PhoneAPI. (Architecture: Outbound builder)
- [x] CHK010: Spec acknowledges no `session_passkey` is needed for `from == 0` admin packets. (Implicit in the outbound builder contract — the spec mirrors the Android spec on this point and the Apple impl carries it forward.)
- [x] CHK011: Spec scopes lockdown to the local BLE connection only (no mesh-routed lock/unlock). (Non-Goals)

## CHK012-016 — Credential handling in memory / logs

- [x] CHK012: Spec mandates `SecureField` + `.textContentType(.password)` for passphrase entry. (NFR-002)
- [x] CHK013: Spec forbids logging passphrase bytes at any log level, including `.debug`. (NFR-002, SC-005)
- [x] CHK014: Spec defines a verification step (`log show` audit) to confirm zero passphrase leakage. (Success Criteria SC-005)
- [ ] CHK015: Spec does not address **crash report** leakage — passphrase fields stored on the coordinator could land in a stack-symbolicated crash dump if the app crashes mid-submit. Recommend marking the field as `private` (already done) and considering a `lazy` wipe after the response (`pendingPassphrase = nil`) — partially covered by invariant 4 in `contracts/coordinator-protocol.md`.
- [x] CHK016: Spec does not write the passphrase to any analytics, telemetry, or remote logging surface. (No new network calls — NFR-001 and Privacy Assessment item 3.)

## CHK017-021 — Session / token handling

- [x] CHK017: Spec resets `sessionAuthorized = false` on every new BLE connection (firmware requires re-auth even if storage is unlocked). (Architecture, FR-014)
- [x] CHK018: Spec covers the BLE-drop-mid-auth case (treat the next connect as a fresh attempt). (Edge Cases)
- [x] CHK019: Spec covers the concurrent-other-client case (firmware pushes unsolicited `LockdownStatus`; client processes it without user action). (Edge Cases)
- [x] CHK020: Spec gates all action-prompting banners on `sessionAuthorized`. (FR-013, Clarifications)
- [ ] CHK021: Spec mentions device clock skew (`valid_until_epoch` lying about expiry) but defers to "firmware-reported state as-is". Verify this is acceptable: if the device clock is **way** off, the displayed expiry could mislead the operator. Consider a UI hint when `validUntilEpoch - now()` is negative but firmware still reports `UNLOCKED`.

## CHK022-024 — Rate limiting / brute force resistance

- [x] CHK022: Spec relies on firmware-side `backoff_seconds` rather than implementing client-side rate limiting (correct — client-side limits would be bypassable by attackers using their own client). (US-1, FR-006)
- [x] CHK023: Spec captures the backoff deadline as an absolute `Date` so backgrounding the app doesn't let the user retry early. (data-model.md)
- [x] CHK024: Spec disables the Submit button during backoff. (FR-006, US-1 Acceptance 4)

## CHK025-028 — Lock Now semantics

- [x] CHK025: Spec covers the race where the firmware reboots before the `LOCKED`-ack status reaches the client (BLE disconnect resolves `pendingLockNow`). (FR-014, US-3 Acceptance 2)
- [x] CHK026: Spec hides/disables the Lock Now control when the device is not currently unlocked. (US-3 Acceptance 4)
- [x] CHK027: Spec requires a confirmation alert before Lock Now (irreversible action — reboots the device). (US-3 Acceptance 1, T017)
- [x] CHK028: Spec sends `lock_now=true` with an empty passphrase so a network observer can't infer anything about the stored passphrase from the lock-now packet shape. (Architecture: Outbound builder)

## CHK029-030 — Failure modes

- [x] CHK029: Spec covers unknown `lock_reason` values by treating them as "locked, prompt or auto-replay" (forward-compat with future firmware reasons). (spec.md `lock_reason` known values list, last bullet)
- [ ] CHK030: Spec does not enumerate what happens if the firmware sends a `LockdownStatus` with `state == STATE_UNSPECIFIED` (proto default 0). The coordinator implementation in T006 should ignore such packets, but the spec is silent. Add a sentence to the spec or document as "ignored" in the contracts file.

---

## Summary of open concerns

| Item | Type | Action |
|------|------|--------|
| CHK006 | Lifecycle | Decide app-uninstall cache behaviour; add to spec Assumptions |
| CHK015 | Defense-in-depth | Already mitigated by invariant 4; document explicitly |
| CHK021 | UX | Add optional UI hint when reported expiry is in the past |
| CHK030 | Forward compat | Define explicit STATE_UNSPECIFIED handling |

These four items should be resolved either in `/speckit.analyze` (if cross-artifact) or by amending `spec.md` directly (if they're spec gaps).
