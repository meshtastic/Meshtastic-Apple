# Review V14: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `ebf1a07e`. This pass re-checks the fixes for `review-data-v13.md`
(R13-1 → T367, R13-2 → T366) and the parts of the other fixes since `29e68b26` that touch my
area. T368 has the other radios' prompts take turns too. T364 stops every radio coming back
before Clear App Data or a restore. T363 ends reconnect loops. I read the tasks.md and HANDOFF.md
changes first and re-read every claim below in the files. Nothing else in my area changed.

Tests: not run this round, as asked; HANDOFF records the full suite passing (3,513 Swift Testing
tests plus the XCTests) and a Mac build for each fix. No tracked file changed.

## Status of review V13

| | Status |
|---|---|
| R13-1 the Choose Radios sheet handing over to presentations that can't show | Fixed (T367, with T368 for the rest). Nothing is asked for while the window presents something. A Choose Radios sheet that didn't come up keeps its turn and is asked for again once the window is free. Another radio's prompt or passphrase sheet that didn't come up is asked for again too. |
| R13-2 Remove This Radio handing on the preferred radio after the clean-up | Fixed (T366): handed on first and passed to `removeRadioData`. |
| R13-2 the one window showing B, then A again | Left as is, on the device checklist. |

## Findings

None this round.

## Checked and found fine

- R13-1's scenario traced through again:
  - The save sheet is open while B finishes and A locks. The window probe sees the save sheet, so
    the Choose Radios gate waits (`isWindowFree`), the lock-down cover waits (`updateGates`), and
    no prompt is asked for.
  - When the save sheet closes, the next check finds the window free and A's lock-down screen
    comes up. The Choose Radios gate waits for it (`isShowingGate`) and comes up after it closes.
  - The other radios' prompts come after the Choose Radios sheet (`gateUp`).
  - Nothing is asked for while something else is up, so nothing is handed over into a window that
    can't show it.
- The Choose Radios gate:
  - A sheet that didn't come up keeps `holdsTurn` and `isUp`. Its re-ask waits only for the
    window to be free, because its own `isUp` takes the other terms out of `waits`, so it and a
    prompt can't wait for each other.
  - Its turn ends only when a sheet that came up is dismissed (`isVisible`) or the choice is made
    elsewhere.
  - A stale try's task can cut a newer try short, but that one is asked for again.
  - The Mac's Connect window, with nothing to wait for, retries on its own as before.
- `OtherRadioPresentation`:
  - One at a time, the passphrase sheet first, only with the window free and no gate up.
  - It isn't taken down while it's up: the retry needs the window free, and a visible alert or
    sheet counts as presenting.
  - Unlock in the alert brings up the passphrase sheet once the alert has gone.
  - The next waiting radio's prompt comes 600 ms after the last one closes. If the check loop
    misses that gap, a prompt asked for too early is asked for again two seconds after it was
    first asked.
- The prompts now show only while the window takes turns (`takesTurns`: two radios known, or
  more than one connected). A prompt is about a radio with a session that the window doesn't
  show, so that's nearly always true. The exception is a radio joining for the first time whose
  connect hasn't finished, with the window's own radio dropping meanwhile. A lock-down radio's
  connect doesn't wait for the passphrase (its status comes after the config), so once it
  finishes the radio counts as known and its prompt comes up. That's a delay of seconds, not a
  lost prompt.
- `WindowPresentationProbe` walks the whole view controller tree, so a sheet the app opened
  anywhere in the window counts, as do confirmation dialogs and an active search field. The only
  long-lived sheets in the app (map legend, filters, settings forms, help) are ones the user opens
  and closes. With several radios the window radio's lock-down or firmware screen waits while
  one is open, as T368 intends. Two gates due at once now come up one after the other.
- T366: the preferred radio is handed on before `removeRadioData`. Kept channel messages go to
  the new preferred radio's slot, and reaggregated nodes prefer its observations. The reset
  callers pass nothing and get `PreferredRadio.nodeNum` as before. Removing a radio that isn't
  the preferred one keeps the preferred radio first.
- T364, the store side: Clear App Data and Restore Backup now stop the reconnect loops and
  connects alongside before the store is cleared. `droppedRadioSeen` needs a loop, so discovery
  can't bring one back meanwhile. During a restore `mayConnectAsFirst` refuses while
  `isDatabaseResetting`. Nothing connects into a store being replaced.
- T363: ending a radio's reconnect loop once it's connected first, and on Disconnect, touches no
  data.
- Single radio and the Mac against `main`: with one radio `takesTurns` is false and no prompt
  exists, so the gates follow the radio's state exactly as before and the probe isn't consulted.
  On the Mac the radio windows have no Choose Radios sheet and no other radios' prompts, and the
  gates don't wait for the probe.
