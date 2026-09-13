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

    def record(var, label=None, desc=None):
        # Reject interpolated strings. They are not display text that can live in a
        # schema - "\(messageByteCount) / \(max) bytes" is a live character counter,
        # and "\(txPower)dBm Transmit Power" changes with the value.
        if label and "\\(" in label:
            label = None
        if desc and "\\(" in desc:
            desc = None
        e = out.setdefault(var, {})
        if label and "label" not in e:
            e["label"] = label
        if desc and "description" not in e:
            e["description"] = desc

    for i, line in enumerate(lines):
        # Picker("X", selection: $var) / Toggle("X", isOn: $var) / TextField("X", text: $var)
        m = re.search(r'(Picker|Toggle)\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*(?:selection|isOn):\s*\$(\w+)', line)
        if m:
            desc = None
            for k in range(i + 1, min(i + 14, len(lines))):
                if re.search(r'^\s*\}\s*$', lines[k]):
                    t = TEXT_RE.search(lines[k + 1]) if k + 1 < len(lines) else None
                    if t and len(t.group(1)) > 25:
                        desc = t.group(1)
                    break
            record(m.group(3), m.group(2), desc)
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
            desc = texts[0] if texts else None
            record(m.group(1), label, desc)
            continue

        # UpdateIntervalPicker(pickerLabel: "X", ... selectedInterval: $var) - often multiline
        m = re.search(r'UpdateIntervalPicker\(', line)
        if m:
            blob = "\n".join(lines[i:i + 6])
            lm = re.search(r'pickerLabel:\s*"((?:[^"\\]|\\.)*)"', blob)
            vm = re.search(r'selectedInterval:\s*\$(\w+)', blob)
            if lm and vm:
                record(vm.group(1), lm.group(1), None)
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
            desc = None
            for k in range(i + 1, min(i + 10, len(lines))):
                tm = TEXT_RE.search(lines[k])
                if tm and len(tm.group(1)) > 25:
                    desc = tm.group(1)
                    break
            record(m.group(2), label or m.group(1), desc)
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
                desc = None
                for k in range(i + 1, min(i + 20, len(lines))):
                    tm = TEXT_RE.search(lines[k])
                    if tm and len(tm.group(1)) > 40:
                        desc = tm.group(1)
                        break
                record(vm.group(1), lm.group(1), desc)
            continue

        # Stepper("literal", value: $var) - skipped when the title is interpolated,
        # since "\(txPower)dBm Transmit Power" has no stable label to lift.
        m = re.search(r'Stepper\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*value:\s*\$?(\w+)', line)
        if m and "\\(" not in m.group(1):
            record(m.group(2), m.group(1), None)

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

                # Prefer a control bound to a variable the save closure actually reads.
                entry = None
                for ident in re.findall(r"\b(\w+)\b", rhs):
                    if ident in ctrl and ctrl[ident].get("label"):
                        entry = dict(ctrl[ident])
                        break
                # Otherwise fall back to a control named after the proto property. The
                # save closure often reads through a local (`lc.region = savedRegion...`)
                # while the control still binds `$region`.
                if not entry:
                    for cand, info in ctrl.items():
                        if norm(cand) == norm(prop) and info.get("label"):
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
