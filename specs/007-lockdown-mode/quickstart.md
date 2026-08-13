# Quickstart: Manual smoke test for Lockdown Mode

Lockdown can only be exercised against a real BLE device — the iOS Simulator has no CoreBluetooth peripheral. You will need:

- An iPhone or iPad running the Meshtastic-Apple debug build with this feature branch
- A Meshtastic node flashed with a `MESHTASTIC_LOCKDOWN` firmware build (firmware PR #10349 or later)
- (Optional) a USB-C cable + `meshtastic` Python CLI to introspect the device out-of-band

## Setup

1. Flash the node with a hardened firmware build:
   ```
   cd firmware/
   pio run -e <board>_lockdown -t upload
   ```
2. Open `Meshtastic.xcodeproj` in Xcode, select your device, Run.

## US-1 — Unlock a locked node (P1)

1. From a fresh boot of the node (factory-reset or hard reboot), open the app.
2. Connect to the node from the Connect tab.
3. **Expected**: after `wantConfig` completes, the lockdown sheet appears with `NEEDS_PROVISION` content (hint: "First-time setup — pick a passphrase you can re-enter").

## US-2 — Provision a passphrase (P1)

1. In the provisioning sheet enter `test-passphrase-1234`.
2. Leave both "Boots remaining" and "Hours valid" empty (firmware defaults).
3. Tap Submit.
4. **Expected**: sheet dismisses within ~2 s, app navigates to wherever the user was, and `Settings → Config → LoRa` shows the device's actual region/preset (not the redacted-default values).

## US-3 — Cached auto-reconnect (P2)

1. After US-2 succeeds, force-quit the app from the app switcher.
2. Reopen the app and observe the auto-connect flow.
3. **Expected**: no sheet appears; the app reaches the same authorized state silently.

To confirm the cache is correctly keyed by peripheral UUID:
```
# On a Mac with the device tethered (or a second iPhone), run:
xcrun simctl keychain show com.meshtastic.Meshtastic    # development cert only
```

## US-4 — Lock Now (P2)

1. While unlocked, navigate to `Settings → Security`.
2. Tap the new "Lock Now" row.
3. Confirm the alert.
4. **Expected**:
   - The app briefly shows the `.lockNowAcknowledged` state and disconnects from the peripheral.
   - The node's status LED reboots (visible on hardware that has one).
   - Reconnecting from the Connect tab triggers a silent auto-replay; the app re-enters `.unlocked` without a sheet.

## US-5 — Wrong passphrase + backoff (P1 edge)

1. Force-reboot the node to drop the cached session.
2. Reconnect.
3. **Expected**: auto-replay succeeds (cached passphrase from US-2 still works).
4. Now manually clear the cache: `Settings → Security → Forget Stored Passphrase` (or wipe via `xcrun simctl keychain`).
5. Reconnect; **expected**: passphrase sheet appears.
6. Enter `wrong-passphrase` three times rapidly.
7. **Expected** on the third attempt: firmware returns `UNLOCK_FAILED` with `backoff_seconds > 0`; sheet switches to a countdown view; Submit button disabled until countdown elapses.
8. Wait for countdown; submit the correct passphrase.
9. **Expected**: `.unlocked`.

## US-5 — Session TTL display (P3)

1. While unlocked, re-submit the passphrase via `Settings → Security → Re-authenticate` (or simply reconnect) with **Boots remaining = 3** and **Hours valid = 1** in the optional fields.
2. After unlock, view `Settings → Security`.
3. **Expected**: the session row shows "Boots remaining: 3" and "Expires: <localized timestamp ~1 hour from now>".
4. Set `Hours valid = 0` instead; expected display: "No time limit".

## Privacy sanity check (NFR-002, SC-005)

After running the full flow:
```
log show --predicate 'subsystem == "gvh.MeshtasticClient"' --info --debug --last 1h \
    | grep -i 'passphrase\|lockdown'
```
Expected: zero matches containing the actual passphrase string. The only acceptable log lines are state-machine transitions and `LockdownStatus { state: …, lockReason: … }` (no `passphrase` field).
