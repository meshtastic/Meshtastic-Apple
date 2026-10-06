# Review V23: quick check of the V22 fixes

Branch `feature/multi-radio` at `913831f4`. Fixes in `fa0d717e`; catalog in `913831f4`. Read only;
nothing built or run.

| V22 | Fix | Verdict |
|---|---|---|
| V22-1 | `ChannelMessageQuery.inSegments(_:radio:)`: this radio's own rows match a stretch's key with no time bounds; other radios' rows keep the bounds. | Fixed. Messages queued at connect after an outside change show again. With one radio it's still the slot query. |
| V22-2 | `updateChannelKeys`: the stored key isn't updated while the radio is paused (`store = updateStored && !isPaused`), so nothing is recorded during a scan. | Fixed. A completed restore leaves no row. An interrupted one records home → scan at the next refresh. Messages during the scan still get the computed key. |
| V22-3 | `sharesMessagesWithOtherRadios` also checks other radios' change rows (`channelKey` and `previousChannelKey`). | Fixed. It fetches only change rows, which are few, and only while the dialog shows. |
| Note | String catalog committed (`913831f4`). | Done. |

No new findings.
