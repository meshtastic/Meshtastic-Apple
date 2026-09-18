#!/usr/bin/env python3
"""Seed (meshtastic.field_metadata) label/description from the Apple app's config views.

Unlike the enum values, a field's display text is not in one property - it sits
inside the view as a Label(...)/Picker(...) argument, and nothing in the view says
which proto field it edits. That link is in the save closure:

    var lc = Config.LoRaConfig()          <- names the proto message
    lc.hopLimit = UInt32(hopLimit)        <- proto property <- @State var
    ...
    Picker("Number of hops", selection: $hopLimit)   <- the label

So: walk the save closure to map proto property -> state var, then find the control
bound to $stateVar and take its label. Matching to the proto field is by normalised
name (lowercased, punctuation stripped) so sx126x_rx_boosted_gain meets
sx126XRxBoostedGain without reimplementing protoc-gen-swift's naming.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
VIEWS = REPO / "Meshtastic/Views/Settings/Config"
PROTO_DIR = REPO / "protobufs/meshtastic"


# Copy-edits applied to helper text lifted from the views before it becomes the
# source string every client translates. Keyed by the exact text in the view so a
# rerun is stable. Three kinds: typos; "Default is X" clauses, which assert firmware
# behaviour the schema should not carry (the firmware is the truth for defaults and
# the app can show them itself); and a unit written into the sentence where the
# field already carries `unit`, which would render the unit twice. Text that is
# not a description of one field maps to None and is dropped.
REWRITES: dict[str, str | None] = {
    "Automatically toggles to the next page on the screen like a carousel, based the specified interval.":
        "Automatically moves to the next screen page, like a carousel, on this interval.",
    "Mininum time between detection broadcasts. Default is 45 seconds.":
        "Minimum time between detection broadcasts.",
    "How often to send detection sensor state to mesh regardless of detection. Default is Never.":
        "How often to send the detection sensor state to the mesh, whether or not anything was detected.",
    "How often air quality metrics are sent out over the mesh. Default is 30 minutes.":
        "How often air quality metrics are sent over the mesh.",
    "How often device metrics are sent out over the mesh. Default is 30 minutes.":
        "How often device metrics are sent over the mesh.",
    "How often environment metrics are sent out over the mesh. Default is 30 minutes.":
        "How often environment metrics are sent over the mesh.",
    "How often power metrics are sent out over the mesh. Default is 30 minutes.":
        "How often power metrics are sent over the mesh.",
    "How often to broadcast neighbor info. Default is 4 hours.":
        "How often to broadcast neighbor info.",
    "How often should we try to get a GPS position.":
        "How often to try to get a GPS position.",
    "The minimum distance change in meters to be considered for a smart position broadcast.":
        "The minimum change in distance before a smart position broadcast is considered.",
    "When using in GPIO mode, keep the output on for this long. ":
        "In GPIO mode, how long to keep the output on.",
    "The fastest that position updates will be sent if the minimum distance has been satisfied":
        "The shortest interval between position updates once the minimum distance has been met.",
    "The maximum interval that can elapse without a node broadcasting a position":
        "The longest a node will go without broadcasting a position.",
    "Units displayed on the device screen":
        "Units shown on the device screen.",
    "Set the GPIO pins for RXD and TXD.": None,     # section text, not a description of one pin
    # The fields carry unit "dBm"; a default is the firmware's to state.
    "RSSI threshold for WiFi device counting. Default is \u221280 dBm.":
        "RSSI threshold for counting WiFi devices.",
    "RSSI threshold for BLE device counting. Default is \u221280 dBm.":
        "RSSI threshold for counting BLE devices.",
}


# Bare units a screen shows beside a numeric field.
UNITS = {"dBm", "kHz", "MHz", "ms", "mA", "m", "s", "%"}


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def _match_brace(txt: str, open_idx: int) -> int:
    """Index just past the `}` matching the `{` at open_idx."""
    depth, j = 1, open_idx + 1
    while j < len(txt) and depth:
        if txt[j] == "{":
            depth += 1
        elif txt[j] == "}":
            depth -= 1
        j += 1
    return j


def proto_fields():
    """{normalised message name: {normalised field name: (proto_field, number, message_full)}}"""
    out = {}

    def walk(body: str, prefix: str) -> None:
        # Blank out nested message/enum bodies so this level's own fields are
        # what remains, then recurse into each nested block with its real path.
        own = list(body)
        for m in re.finditer(r"\b(message|enum)\s+(\w+)\s*\{", body):
            open_idx = body.index("{", m.start())
            end = _match_brace(body, open_idx)
            for k in range(m.start(), end):
                own[k] = " "
            if m.group(1) == "message":
                walk(body[open_idx + 1:end - 1], f"{prefix}.{m.group(2)}")

        fields = {}
        for fm in re.finditer(
            r"(?:optional\s+|repeated\s+)?[\w.]+\s+(\w+)\s*=\s*(\d+)\s*[;\[]", "".join(own)
        ):
            fields[norm(fm.group(1))] = (fm.group(1), int(fm.group(2)), prefix)
        if fields:
            name = prefix.rsplit(".", 1)[-1]
            out.setdefault(norm(name), {}).update(fields)

    for fname in ("config", "module_config"):
        txt = (PROTO_DIR / f"{fname}.proto").read_text()
        txt = re.sub(r"/\*.*?\*/", "", txt, flags=re.S)
        txt = re.sub(r"//[^\n]*", "", txt)
        for m in re.finditer(r"^message\s+(\w+)\s*\{", txt, re.M):
            open_idx = txt.index("{", m.start())
            end = _match_brace(txt, open_idx)
            walk(txt[open_idx + 1:end - 1], f"meshtastic.{m.group(1)}")
    return out


LABEL_RE = re.compile(r'Label\(\s*"((?:[^"\\]|\\.)*)"')
TEXT_RE = re.compile(r'Text\(\s*"((?:[^"\\]|\\.)*)"')


def controls(src: str) -> dict:
    """state var -> {label, description} from the control bound to $var."""
    out: dict[str, dict] = {}
    lines = src.split("\n")

    def record(var, label=None, desc=None, unit=None, lo=None, hi=None):
        # Reject interpolated strings. They are not display text that can live in a
        # schema - "\(messageByteCount) / \(max) bytes" is a live character counter,
        # and "\(txPower)dBm Transmit Power" changes with the value.
        if label and "\\(" in label:
            label = None
        if desc and "\\(" in desc:
            desc = None
        if desc in REWRITES:
            desc = REWRITES[desc]
        e = out.setdefault(var, {})
        if label and "label" not in e:
            e["label"] = label
        if desc and "description" not in e:
            e["description"] = desc
        if unit and "unit" not in e:
            e["unit"] = unit
        if lo is not None and "min_value" not in e:
            e["min_value"] = lo
        if hi is not None and "max_value" not in e:
            e["max_value"] = hi

    def block_end(start: int) -> int:
        """Index of the line where the control starting at `start` closes.

        Counts braces and parentheses from the control's own line, so a Picker with a
        multi-line ForEach closure, or an UpdateIntervalPicker call split over five
        lines, both resolve to the line their last `}` or `)` sits on.
        """
        depth = 0
        for k in range(start, min(start + 40, len(lines))):
            depth += lines[k].count("{") + lines[k].count("(")
            depth -= lines[k].count("}") + lines[k].count(")")
            if depth <= 0:
                return k
        return start

    def sibling_description(after: int) -> str | None:
        """The helper text a screen shows under a control.

        Nearly every description in these views is a grey `.callout` Text that follows
        the control as a sibling - after the control's modifiers, and sometimes after
        the closing brace of an HStack or VStack that wraps the control. Modifier
        lines, blank lines and bare closing braces are skipped; the search stops at
        the next control or section so one control's text is never attributed to the
        one before it. Only text styled as helper text counts, so a neighbouring
        control's title is never mistaken for a description.
        """
        for k in range(after, min(after + 16, len(lines))):
            ln = lines[k]
            if re.match(r"^\s*(\.|//|$)", ln) or re.match(r"^\s*\}\s*$", ln):
                continue
            if re.match(r"^\s*(Section\b|if\b|\}\s*else|Toggle\(|Picker\(|TextField\(|Stepper\(|Slider\(|"
                        r"UpdateIntervalPicker\(|HStack|VStack|NavigationLink|Button\(|Label\()", ln):
                return None
            t = TEXT_RE.search(ln)
            if not t:
                return None
            text = t.group(1)
            # A bare unit beside a numeric field ("dBm") is not the helper text; the
            # helper text follows the row. Any other short text ends the search.
            if text in UNITS:
                continue
            if len(text) <= 25 or "\\(" in text:
                return None
            tail = "\n".join(lines[k + 1:k + 4])
            styled = re.search(r"\.font\(\.callout\)|\.foregroundColor\(\.gray\)|\.foregroundStyle\(\.secondary\)", tail)
            return text if styled else None
        return None

    def bounds(text: str):
        """(lo, hi) from `in: a...b`, or from a `ForEach(a..<b)` option list.

        A ForEach whose `.tag(` remaps the element is skipped: LoRa's spread factor
        shows 7..<13 but stores 12 as 0, so the visible range is not the stored one.
        An identity tag - `.tag($0)`, or `.tag(pin)` for `pin in` - changes nothing
        and keeps the bounds.
        """
        m = re.search(r"in:\s*(-?\d+(?:\.\d+)?)\.\.\.(-?\d+(?:\.\d+)?)", text)
        if m:
            return float(m.group(1)), float(m.group(2))
        m = re.search(r"ForEach\((\d+)\.\.<(\d+)\)\s*(?:\{\s*(\w+)\s+in)?", text)
        if not m:
            return None, None
        loop_var = m.group(3) or "$0"
        for tag in re.findall(r"\.tag\(([^)]*)\)", text):
            if tag.strip() != loop_var:
                return None, None
        return float(m.group(1)), float(m.group(2)) - 1

    def unit_nearby(start: int, end: int) -> str | None:
        """A bare unit shown beside a numeric field, e.g. `Text("dBm")` in the same row."""
        # The unit sits after the field's own modifiers, which can run to several
        # lines, so look a little further down than the row itself.
        blob = "\n".join(lines[max(0, start - 3):end + 8])
        m = re.search(r'Text\(\s*"(' + "|".join(map(re.escape, sorted(UNITS))) + r')"\s*\)', blob)
        return m.group(1) if m else None

    for i, line in enumerate(lines):
        # Picker("X", selection: $var) / Toggle("X", isOn: $var) / TextField("X", text: $var)
        m = re.search(r'(Picker|Toggle)\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*(?:selection|isOn):\s*\$(\w+)', line)
        if m:
            end = block_end(i)
            lo, hi = bounds("\n".join(lines[i:end + 1]))
            record(m.group(3), m.group(2), sibling_description(end + 1), lo=lo, hi=hi)
            continue

        # Toggle(isOn: $var) { Label("X", ...) ; Text("desc") }
        # Some toggles carry the label in a Text instead of a Label, with no Label at
        # all - Toggle(isOn: $adcOverride) { Text("ADC Override") }. In that case the
        # first Text is the label, not the description.
        m = re.search(r'Toggle\(\s*isOn:\s*\$(\w+)\s*\)\s*\{', line)
        if m:
            label = desc = None
            texts = []
            for k in range(i + 1, min(i + 6, len(lines))):
                if label is None:
                    lm = LABEL_RE.search(lines[k])
                    if lm:
                        label = lm.group(1)
                        continue
                tm = TEXT_RE.search(lines[k])
                if tm:
                    texts.append(tm.group(1))
                    if label is not None:
                        break
                elif re.search(r'^\s*\}', lines[k]):
                    break
            if label is None and texts:
                label, texts = texts[0], texts[1:]
            desc = texts[0] if texts else sibling_description(block_end(i) + 1)
            record(m.group(1), label, desc)
            continue

        # UpdateIntervalPicker(pickerLabel: "X", ... selectedInterval: $var) - often multiline
        m = re.search(r'UpdateIntervalPicker\(', line)
        if m:
            blob = "\n".join(lines[i:i + 6])
            lm = re.search(r'pickerLabel:\s*"((?:[^"\\]|\\.)*)"', blob)
            vm = re.search(r'selectedInterval:\s*\$(\w+)', blob)
            if lm and vm:
                record(vm.group(1), lm.group(1), sibling_description(block_end(i) + 1), unit="s")
            continue

        # TextField("placeholder", text:/value: $var) - the real label is usually a
        # sibling Label above, since the first argument is often a placeholder.
        m = re.search(r'TextField\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*(?:text|value):\s*\$(\w+)', line)
        if m:
            label = None
            for k in range(max(0, i - 4), i):
                lm = LABEL_RE.search(lines[k])
                if lm:
                    label = lm.group(1)
            record(m.group(2), label or m.group(1), sibling_description(i + 1),
                   unit=unit_nearby(i, i))
            continue

        # Slider(value: <binding>, ...) { Text("X") } minimumValueLabel: { ... }
        # The label is in a trailing closure, not an argument, and the binding may be a
        # computed Binding property rather than $state - so record it unprefixed too.
        m = re.search(r'Slider\(', line)
        if m:
            blob = "\n".join(lines[i:i + 14])
            vm = re.search(r'value:\s*\$?(\w+)', blob)
            lm = re.search(r'\)\s*\{\s*\n\s*Text\(\s*"((?:[^"\\]|\\.)*)"', blob)
            if vm and lm:
                lo, hi = bounds(blob)
                record(vm.group(1), lm.group(1), sibling_description(block_end(i) + 1), lo=lo, hi=hi)
            continue

        # Stepper("literal", value: $var) - skipped when the title is interpolated,
        # since "\(txPower)dBm Transmit Power" has no stable label to lift.
        m = re.search(r'Stepper\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*value:\s*\$?(\w+)', line)
        if m:
            lo, hi = bounds(line)
            label = None if "\\(" in m.group(1) else m.group(1)
            record(m.group(2), label, sibling_description(i + 1), lo=lo, hi=hi)

    return out


def main() -> None:
    fields = proto_fields()
    plan: dict[str, dict] = {}
    unmatched: list[str] = []

    for path in sorted(VIEWS.rglob("*.swift")):
        src = path.read_text()
        ctrl = controls(src)

        for sm in re.finditer(r"var\s+(\w+)\s*=\s*(Config|ModuleConfig)\.(\w+)\(\)", src):
            local, _, message = sm.group(1), sm.group(2), sm.group(3)
            tail = src[sm.end():sm.end() + 6000]
            for am in re.finditer(
                rf"\b(?:self\.)?{re.escape(local)}((?:\.\w+)+)\s*=\s*([^\n]+)", tail
            ):
                path_parts = am.group(1).lstrip(".").split(".")
                rhs = am.group(2)
                owner = message if len(path_parts) == 1 else path_parts[-2]
                prop = path_parts[-1]

                fm = fields.get(norm(owner), {}).get(norm(prop))
                if not fm:
                    unmatched.append(f"{path.name}: {owner}.{prop} (no proto field)")
                    continue
                proto_field, number, full = fm

                # Prefer a control bound to a variable the save closure actually reads -
                # but among those, the one whose name best matches the proto field, not
                # simply the first. A save line often gates on a screen-level flag:
                #
                #   tmc.positionMinIntervalSecs =
                #       UInt32(enabled && positionDedupEnabled ? positionMinInterval... : 0)
                #
                # `enabled` comes first and has a control labelled "Enabled", so taking
                # the first match labels five different settings "Enabled".
                target = norm(proto_field)

                def affinity(ident: str) -> int:
                    n = norm(ident)
                    if n == target:
                        return 3
                    if target.startswith(n) or n.startswith(target):
                        return 2
                    return 1 if n in target or target in n else 0

                entry = None
                candidates = [
                    i for i in dict.fromkeys(re.findall(r"\b(\w+)\b", rhs))
                    if i in ctrl and ctrl[i].get("label")
                ]
                if candidates:
                    best = max(candidates, key=affinity)
                    entry = dict(ctrl[best])
                # Otherwise fall back to a control named after the proto property. The
                # save closure often reads through a local (`lc.region = savedRegion...`)
                # while the control still binds `$region`.
                # A Stepper whose title is interpolated ("\(txPower)dBm Transmit Power")
                # has no label to lift but may still carry bounds or a description. Only
                # this exact-name match may take an unlabelled control, and only when it
                # has something else to say; the heuristics above still need a label.
                if not entry:
                    for cand, info in ctrl.items():
                        carries_metadata = any(
                            info.get(k) is not None for k in ("description", "unit", "min_value", "max_value")
                        )
                        if norm(cand) == norm(prop) and (info.get("label") or carries_metadata):
                            entry = dict(info)
                            break
                # Last resort: a control whose LABEL names the field. Catches controls in
                # nested views bound to a @Binding parameter, where neither the binding
                # name nor the save closure mentions the field - Picker("Bandwidth",
                # selection: $selection) inside CustomBandwidthPicker, for instance.
                if not entry:
                    for info in ctrl.values():
                        if info.get("label") and norm(info["label"]) == norm(proto_field):
                            entry = dict(info)
                            break
                if not entry:
                    unmatched.append(f"{path.name}: {full}.{proto_field} (no labelled control)")
                    continue

                bucket = plan.setdefault(full, {"values": {}})
                bucket["values"].setdefault(str(number), {**entry, "_field": proto_field})

    print(json.dumps({"plan": plan, "unmatched": sorted(set(unmatched))},
                     indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
