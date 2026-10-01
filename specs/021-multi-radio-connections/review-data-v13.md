# Review V13: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `29e68b26`. This pass re-checks the fix for `review-data-v12.md`
(R12-1 → T362) and the data and service side of the connection fixes since `049c59d4` (T360, a
dropped radio coming back as the first radio; T361, Remove This Radio handing the preferred radio
on). I read the tasks.md and HANDOFF.md changes first and re-read every claim below in the files.
Nothing else in my area changed.

Tests: not run this round, as asked; HANDOFF records the full suite passing (3,505 Swift Testing
tests plus the XCTests) and a Mac build for each fix. No tracked file changed.

## Status of review V12

| | Status |
|---|---|
| R12-1 a Choose Radios sheet asked for but never shown held the others back for good | Fixed for the sheet itself: two seconds after asking without it appearing, the gate lets the others go and asks again two seconds later, and a choice made in App Settings meanwhile lets them go too. It keeps asking every few seconds until it shows, so once whatever was up closes it comes up. But letting the others go at that moment has a side effect: R13-1. |

## Findings

### R13-1. When the Choose Radios sheet can't show, it hands over to presentations that can't show either

- `Views/Settings/ServiceRadioPickers.swift:160-166`: when the sheet hasn't appeared after two
  seconds, `release()` sets `isUp` false and calls `onClose`. In `ContentView.swift:89-93` that
  runs `updateGates()`, which raises the window radio's lock-down or firmware cover if one is
  due, and sets `isGateUp` false, which makes another radio's attention alert and passphrase sheet
  live again (`ContentView.swift:126, 132`).
- The sheet didn't appear because something else in the window was up (a sheet from Settings,
  Tools, a node or a message), and that's normally still up two seconds later. So whatever was
  held back is asked for at a moment when, by R12-1's own reasoning, it can't be shown either.
- Unlike the Choose Radios sheet, none of those try again. Their flags stay set until they're
  dismissed or their state changes: `isShowingLockdownGate` and `isShowingFirmwareGate` until the
  radio is unlocked or updated, `radioAttentionPrompt` until the radio's attention clears or it
  disconnects (`AccessoryManager+RadioAttention.swift:97-122`, `AccessoryManager.swift:712`).
  While a cover's flag is set, `isGateUp` stays true. While a prompt's is set,
  `isAskingAboutAnotherRadio` is true. Either way the Choose Radios gate's `waits` is true, so its
  retry stops (`update` returns on `isWaiting`). `updateGates()` also holds the window radio's
  gates back while a prompt is set.
- So the outcome R12-1 described, nothing more coming up until relaunch, now happens one step
  later, whenever something else was waiting behind the sheet. That is the situation T359's order
  exists for, and the one T362's device check describes ("A's lock-down screen or B's prompt still
  come up afterwards").
- Scenario: iPhone, A connected. Add B for the first time, and while it downloads its node list,
  open a channel link (the save sheet). B finishes, and the Choose Radios sheet is asked for
  behind the save sheet. Meanwhile A gets locked, and its lock-down screen waits for the sheet.
  Two seconds later the gate lets go, and the lock-down cover is asked for behind the save sheet.
  When the user closes the save sheet, neither the lock-down screen nor the Choose Radios sheet
  comes up, and A stays locked with no way to enter its passphrase in the window. The same
  happens if, instead of A locking, a third radio C needs the user (its alert is asked for
  behind the save sheet and stays pending).
- A dropped alert or passphrase sheet holding the gates back was already possible since T359 (a
  prompt raised while an app sheet is up). T362's hand-over makes it happen in exactly the case
  it handles.
- Fix direction: while retrying, keep `isUp` true and only toggle `isShowing`, so nothing else is
  asked for until the sheet has shown and closed. A choice made in App Settings still lets the
  others go, from a screen that's free. The same "ask again until it appears" for the alert and
  the covers would close the rest.
- Sure: high that the hand-over asks for the others while the screen is still taken, and that
  none of them retries. Medium that SwiftUI drops them, the same premise as R12-1, which T362
  accepts.

### R13-2. Minor

- `RadioWindow.swift:94-103`, `AccessoryManager+Connect.swift:197`: on iPhone with the user's
  pick being A (the one window's stored radio), when A has dropped and B comes back as the first
  radio (T360), the window is `.firstRadio`, which is B, for the length of B's handshake. It
  shows B's messages and settings, and a DM thread switches to B's thread. Once B's connect
  finishes, `reconnectRememberedRadios` starts A's reconnect loop and the window goes back to A,
  reconnecting. The launch fallback does the same today. It's cosmetic: nothing is sent through
  a radio the window doesn't show. It's worth knowing for the device check, where the window
  will be seen switching twice.
- `AccessoryManager+RadioRemoval.swift:60-75`: T361 hands the preferred radio on after
  `removeRadioData` has run, so while the store is cleaned up `PreferredRadio` still names the
  radio being removed. The kept channel messages go to the lowest-numbered remaining radio's slot
  rather than the new preferred one's, and `reaggregate` breaks ties without a first radio. This
  is the same as before T361 and doesn't change what any window shows (channel history is
  matched by key). Handing on first would make the two agree.

## Checked and found fine

- R12-1's fix on its own: `hasAppeared` is reset before each try. A try that shows ends its task
  at the two-second check. A choice made while the sheet is up dismisses it once, through
  `onDismiss`. A choice made in App Settings before it appeared lets the others go, and the
  task's later check calls `release()` a second time, which only recomputes the same state. Two
  overlapping tries collapse into one (the second sees `isShowing`). On the Mac the Connect
  window's gate has nothing to wait for or hand over to, so its retry is all there is.
- T360, B coming back as the first radio:
  - The connect sets `activeConnection` and `activeDeviceNum` together from B's known number
    (`+Connect.swift:303-305`), so the window never briefly reads the old preferred radio's data.
  - `PreferredRadio` moves to B at Step 5 and on its MyInfo, as for any first connect.
  - The old preferred radio is marked to come back (`setRadioAutoConnect`) only when the user
    didn't disconnect it. For a removed radio that's a no-op, since its MyInfo is gone.
  - The backfill owner isn't touched.
  - Services keep their chosen radios: choices are by node number, and `session(for:)` finds B
    whether it's first or alongside.
  - The sharing snapshot refreshes at Step 7 when B is the CarPlay & Siri radio.
  - Step 8's prune and unread badges run as for any connect with no other radio connected.
- T361: `connectedRadioAfterFirst` is the radio the one window shows after the first radio is
  disconnected, so the preferred radio and the window agree. With no radio left the preference
  is cleared as before. The service choices of the removed radio were already cleared and known
  radios refreshed just above, so a service in use asks again with two or more radios left.
- Single radio against `main`: T360's path needs a radio alongside that dropped, so it never runs
  with one radio. T361's hand-over finds no other radio and clears the preference as before. The
  bounded first connect is only bounded when a bound is passed, and existing callers pass none.
