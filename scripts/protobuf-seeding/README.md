# Protobuf metadata seeding

One-time scaffolding used to lift this app's English display strings into the Meshtastic
schema, so `(meshtastic.field_metadata)` and `(meshtastic.enum_value_metadata)` become the
source of truth instead of switch statements here. Produced
[meshtastic/protobufs#1081](https://github.com/meshtastic/protobufs/pull/1081) — 140 fields
and 122 enum values.

Kept in the repository so that annotation diff can be re-run and checked rather than read
line by line, and so the extraction can be repeated if the app grows settings before the
schema catches up. Once the schema is the source of truth these are not part of any build.

## Running

From the repository root, with the `protobufs` submodule checked out:

```bash
# enum values: RegionCode, ModemPreset, Role, ... -> enum_value_metadata
python3 scripts/protobuf-seeding/seed_enum_annotations.py . > /tmp/plan.json
python3 scripts/protobuf-seeding/apply_enum_annotations.py protobufs/meshtastic /tmp/plan.json

# fields: the controls on each config screen -> field_metadata
python3 scripts/protobuf-seeding/seed_field_annotations.py . > /tmp/fplan.json
python3 scripts/protobuf-seeding/apply_field_annotations.py protobufs/meshtastic /tmp/fplan.json

buf format -w --path protobufs/meshtastic/config.proto --path protobufs/meshtastic/module_config.proto
```

The `seed_*` scripts only read and print a plan; the `apply_*` scripts write. Both appliers
are idempotent — a field or value already carrying the annotation is left alone — so a
partial run can be repeated safely.

That is why the plans are slightly larger than what #1081 contains: 141 fields and 123 enum
values planned, 140 and 122 applied. The difference is the worked examples already annotated
by hand in #952 (`hop_limit`, `ModemPreset.LONG_FAST`), which the appliers leave untouched.

## How the joins work

**Enum values** join by value number, which is aligned with each app enum's raw value.
Names are deliberately not used: the app spells them differently (`degrees0` vs
`DEGREES_0`, `txtmsg` vs `TEXTMSG`). The app-enum-to-proto-enum mapping is the `MAPPING`
table at the top of `seed_enum_annotations.py`, 13 entries.

**Fields** are harder, because nothing in a view says which proto field a control edits.
The link comes from the save closure:

```swift
var lc = Config.LoRaConfig()                      // names the message
lc.hopLimit = UInt32(hopLimit)                    // proto property <- view state
Picker("Number of hops", selection: $hopLimit)    // the label
```

Matching to the proto field is by normalised name — lowercased, punctuation stripped — so
`sx126x_rx_boosted_gain` meets `sx126XRxBoostedGain` without the extractor needing to know
protoc-gen-swift's naming rules.

## What they deliberately skip

Both seeders report what they could not match rather than guessing. As of the run that
produced #1081 that was 33 fields, in four groups: interpolated labels with no stable
literal (`"\(txPower)dBm Transmit Power"`), controls inside nested custom views
(`bandwidth`, `coding_rate`), fields with no user interface (`private_key`, `admin_key`),
and `position_flags`, whose ten toggles take their labels from the `PositionFlags` enum
values instead. Those are the exemption list in spec 019 FR-015a.

`keywords` is never seeded. It cannot be derived from the app, and generating synonyms
mechanically would be guessing.

## Caveat

These parse Swift and proto with regular expressions, which is fine for a one-time lift
against a known-shaped codebase and would not be fine as a build step. `apply_field_annotations.py`
in particular had to be anchored to line starts and taught to mask nested bodies, because
an earlier version matched enum value lines as though they were fields. Always check
`protoc` still parses and `buf format` is clean after a run.
