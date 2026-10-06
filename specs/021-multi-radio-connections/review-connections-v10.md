# Review V10: connections and focus (feature/multi-radio)

Branch `feature/multi-radio` at `904b08ce`. V9 (`review-connections-v9.md`) reviewed `1b300de9`;
this pass checks the one fix since (T250), and re-reads `connect(to:)` and its first steps whole,
since ten rounds of fixes have landed in it one at a time.

Files read: `+Position` (the diff and the loop), `MultiRadioConnectLifecycleTests.focusedPositionFailureKeepsLoop`,
and `+Connect` from the top of `connect(to:)` through Step 1.

The full suite passes in the iOS Simulator (iPhone 17 Pro): 3,478 Swift Testing tests in 599
suites and 29 XCTests, with the simulator to itself.

## Where the V9 finding stands

| V9 | What | Now |
|---|---|---|
| K1 | A failed send to the focused radio ended position sharing for every radio | Fixed: with other radios connected the error is logged and the round goes on; with one radio it still ends the loop, as on `main`. |

## Findings

None.

## Checked and found fine

- `sharePhonePosition`: the "other radios connected" test uses the round's own snapshot, so a
  radio joining or leaving mid-round can't change which way it goes; a `catch where` that doesn't
  match rethrows, which keeps `main`'s behaviour for one radio; once the phone has a location
  again the next round sends to every radio. The test reaches the focused send's failure through
  the missing location in the simulator, as its comment says, which exercises the same branch.
- `connect(to:)` read whole: the early refusals (focused already connected, radio already
  alongside, a live attempt for the same radio) come before the attempt is registered, so they
  leave no state behind; the three `defer`s run in the right order (gate released, then the
  attempt removed with its change notification, then the waiting Unlock/Update retried); the
  checks after the gate (cancelled, focus taken meanwhile, no room) run before anything is set;
  the focused-only resets come after them. Step 0 asks the join question on the first try only,
  and a retry's cleanup goes through `cleanUpBeforeRetry`. Step 1 registers the session before
  its first event can be handled. The success path's give-back clearing and remembered-radio
  reconnect run inside the gate, with the reconnects only scheduled.
- Single radio: nothing in T250 changes its behaviour.
