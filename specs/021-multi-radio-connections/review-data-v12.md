# Review V12: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `fb719385`. This pass re-checks the fixes for `review-data-v11.md`
(R11-1 → T354, R11-2 → T355, R11-3 → T356–T359) and the data and service side of the connection
fixes since `cf26aa79` (T350 Analyze Current Preset, T352 Disconnect on the first radio, T359 the
one window's presentation order, which now gates the Choose Radios sheet). I read the tasks.md
and HANDOFF.md changes first and re-read every claim below in the files.

Tests: not run this round, as asked; HANDOFF records the full suite passing (3,499 Swift Testing
tests plus the XCTests) and a Mac build for each fix. No tracked file changed.

## Status of review V11

| | Status |
|---|---|
| R11-1 Remove Node on the first radio's link | Fixed: `removeNode` sends on the session of the radio it's addressed to and throws when that radio isn't connected, before the node is deleted from the store; every caller passes the window's radio. With one radio it's the connected radio, as on `main`. |
| R11-2 Client History on the first radio's link | Fixed: sent on the session of its `fromUser`, on that radio's slot (`channelSlot(toReach:fromRadio:)`), failing when it's off. |
| R11-3 a DM from a window whose radio is off, with no history | Fixed: `DirectMessageQuery.conversationRadios` always includes the window's radio, so its (empty) thread shows and a reply fails; one radio's conversation is unchanged (one radio in the list, so no filter). |
| R11-3 metadata request, Exchange User Info | Fixed: the metadata request checks the radio it's sent from (the RX/TX light, with none named, still the first radio's flag); Exchange User Info no longer falls back to the first radio. |
| R11-3 presentation order (device check) | Done as T359; see R12-1. |

Also checked: T350 passes the scan's radio from `startCurrentPresetScan(radio:)` to
`startScan(radio:)`; T352's `connectedRadioAfterFirst` becomes the preferred radio only on a user
disconnect of the first radio with another connected. It doesn't touch the backfill owner, which
is recorded once at launch. A drop leaves `PreferredRadio` as it was, so a DM in the one window
keeps the dropped radio's thread and a reply fails, as R11-3 wanted.

## Findings

### R12-1. If the Choose Radios sheet is asked for but doesn't appear, it's held as up for good

- `Views/Settings/ServiceRadioPickers.swift` `ServiceRadioChoiceGate.update(needsChoice:)` sets
  `isUp = true` and `isShowing = true` together, and `isUp` goes back to false only in the sheet's
  `onDismiss`; `update(needsChoice: false)` sets `isShowing = false` but leaves `isUp`.
  `ContentView.swift` then treats `isChoosingServiceRadios` (that `isUp`) as the sheet being up:
  `updateGates()` holds the window radio's lock-down and firmware gates back while it's true, and
  `isGateUp` keeps the other radios' prompts and passphrase sheet off.
- A sheet asked for while something else in the window is already presenting (a sheet opened from
  Settings, Tools, a node or a message, a confirmation dialog) isn't shown, and SwiftUI doesn't
  show it later or call its `onDismiss`. If that happens, `isUp` stays true from then on: the
  sheet never comes up, choosing the radios in App Settings sets `isShowing` false with no dismiss,
  and the window radio's lock-down screen and firmware gate, and the other radios' prompts, don't
  come up until the app is relaunched.
- Scenario: iPhone, A connected; add B for the first time and, while it downloads its node list,
  open a channel link (the save sheet). B finishes, the Choose Radios sheet is asked for behind the
  save sheet and doesn't appear, then or after the save sheet closes. Later A is locked down (or
  needs a firmware update): its screen doesn't show, and neither does a prompt about B.
- Fix direction: clear `isUp` when `isShowing` goes false without a dismiss (or derive it from
  `isShowing`), so a sheet that never appeared can't hold the others back. T359's device check
  covers the orders it lists, not a sheet that was never shown.
- Sure: high that `isUp` can't be cleared without a dismiss; medium that SwiftUI drops the sheet
  in that situation (it does for sibling presentations; this one is an ancestor's).

## Checked and found fine

- The order T359 sets up, traced through: the Choose Radios sheet waits for onboarding and the
  gates and comes up after them; a gate asked for while the sheet or another radio's prompt is up
  comes up after, through `onClose`, the prompt's `onChange` and the passphrase sheet's
  `onDismiss`; a gate already up stays up; with one radio only onboarding and the gates are used,
  as before. The Mac's Connect window uses the gate with nothing to wait for.
- Removing a node with the window's radio off: the send throws before the store is touched, so the
  node stays.
