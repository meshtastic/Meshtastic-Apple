#!/usr/bin/env python3
"""Seed (meshtastic.enum_value_metadata) annotations from the Apple app's enums.

One-time scaffolding. The app currently holds the English display text for every
proto-backed enum in switch statements under Meshtastic/Enums/. This lifts that
text into the schema so the schema becomes the source of truth and the switches
can be deleted.

Reads:  Meshtastic/Enums/*.swift  (app enums: case -> rawValue, case -> strings)
Writes: an annotation plan as JSON, keyed by proto enum full name and value number.

The join is by RAW VALUE, which is the proto field number - verified aligned for
every enum in MAPPING. Names are deliberately not used for matching: the app
spells cases differently (degrees0 vs DEGREES_0, txtmsg vs TEXTMSG).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
ENUM_DIR = REPO / "Meshtastic/Enums"

# app enum -> (proto enum full name, proto file)
# "label_from" names the app property holding the short display name; when an
# enum has both `name` and `description`, description becomes the long text.
MAPPING = {
    "DeviceRoles":         ("meshtastic.Config.DeviceConfig.Role", "config", "name"),
    "RebroadcastModes":    ("meshtastic.Config.DeviceConfig.RebroadcastMode", "config", "name"),
    "RegionCodes":         ("meshtastic.Config.LoRaConfig.RegionCode", "config", "description"),
    "ModemPresets":        ("meshtastic.Config.LoRaConfig.ModemPreset", "config", "description"),
    "CompassOrientations": ("meshtastic.Config.DisplayConfig.CompassOrientation", "config", "description"),
    "DisplayModes":        ("meshtastic.Config.DisplayConfig.DisplayMode", "config", "description"),
    "OledTypes":           ("meshtastic.Config.DisplayConfig.OledType", "config", "description"),
    "ScreenUnits":         ("meshtastic.Config.DisplayConfig.DisplayUnits", "config", "description"),
    "GpsMode":             ("meshtastic.Config.PositionConfig.GpsMode", "config", "description"),
    "BluetoothModes":      ("meshtastic.Config.BluetoothConfig.PairingMode", "config", "description"),
    "InputEventChars":     ("meshtastic.ModuleConfig.CannedMessageConfig.InputEventChar", "module_config", "description"),
    "SerialModeTypes":     ("meshtastic.ModuleConfig.SerialConfig.Serial_Mode", "module_config", "description"),
    "SerialBaudRates":     ("meshtastic.ModuleConfig.SerialConfig.Serial_Baud", "module_config", "description"),
}


def enum_body(src: str, name: str) -> str | None:
    """The brace-matched body of `enum <name>`, or None."""
    m = re.search(rf"\benum\s+{re.escape(name)}\s*[:{{]", src)
    if not m:
        return None
    i = src.index("{", m.start())
    depth, j = 1, i + 1
    while j < len(src) and depth:
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
        j += 1
    return src[i + 1:j - 1]


def string_property(body: str, prop: str) -> dict[str, str]:
    """case name -> literal, for `var <prop>: String { switch self { ... } }`."""
    m = re.search(rf"var\s+{re.escape(prop)}\s*:\s*String\s*\{{", body)
    if not m:
        return {}
    i = body.index("{", m.start())
    depth, j = 1, i + 1
    while j < len(body) and depth:
        if body[j] == "{":
            depth += 1
        elif body[j] == "}":
            depth -= 1
        j += 1
    block = body[i + 1:j - 1]

    out: dict[str, str] = {}
    # `case .foo, .bar:` then a `return "literal"` before the next case
    for cm in re.finditer(r"case\s+((?:\.\w+\s*,\s*)*\.\w+)\s*:", block):
        names = re.findall(r"\.(\w+)", cm.group(1))
        tail = block[cm.end():]
        nxt = re.search(r"\n\s*(?:case\s+\.|default\s*:)", tail)
        seg = tail[:nxt.start()] if nxt else tail
        # Both spellings: the original `"X".localized`, and `String(localized: "X")`
        # for enums already migrated to the string catalog.
        lit = (re.search(r'return\s+"((?:[^"\\]|\\.)*)"', seg)
               or re.search(r'return\s+String\(localized:\s*"((?:[^"\\]|\\.)*)"', seg))
        if lit:
            for n in names:
                out[n] = lit.group(1)
    return out


def main() -> None:
    sources = {p.name: p.read_text() for p in ENUM_DIR.glob("*.swift")}
    plan: dict[str, dict] = {}
    problems: list[str] = []

    for app_enum, (proto_name, proto_file, label_prop) in MAPPING.items():
        body = None
        for src in sources.values():
            body = enum_body(src, app_enum)
            if body:
                break
        if not body:
            problems.append(f"{app_enum}: not found in Meshtastic/Enums/")
            continue

        cases = {m.group(1): int(m.group(2))
                 for m in re.finditer(r"case\s+(\w+)\s*=\s*(-?\d+)", body)}
        if not cases:
            problems.append(f"{app_enum}: no `case x = n` raw values")
            continue

        labels = string_property(body, label_prop)
        longs = string_property(body, "description") if label_prop != "description" else {}

        values: dict[str, dict] = {}
        for case, num in sorted(cases.items(), key=lambda kv: kv[1]):
            entry = {}
            if case in labels:
                entry["label"] = labels[case]
            if case in longs and longs[case] != entry.get("label"):
                entry["description"] = longs[case]
            if entry:
                entry["_case"] = case
                values[str(num)] = entry

        missing = sorted(set(cases) - set(labels))
        if missing:
            problems.append(f"{app_enum}: no {label_prop} for {', '.join(missing)}")

        plan[proto_name] = {"file": proto_file, "app_enum": app_enum, "values": values}

    print(json.dumps({"plan": plan, "problems": problems}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
