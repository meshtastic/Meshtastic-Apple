#!/usr/bin/env python3
"""Apply the seeded annotations from seed_enum_annotations.py into the .proto files.

Rewrites `VALUE = N;` into `VALUE = N [(meshtastic.enum_value_metadata) = {...}];`,
merging with any existing `[deprecated = true]` and preserving trailing comments.
Idempotent: a value that already carries the annotation is left alone.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PROTO_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("meshtastic")
PLAN_PATH = Path(sys.argv[2] if len(sys.argv) > 2 else "/tmp/plan.json")
with PLAN_PATH.open(encoding="utf-8") as plan_file:
    PLAN = json.load(plan_file)["plan"]

# The app appends this to a label because it has no other way to say so; the
# schema carries `deprecated` mirrored from the standard option instead.
DEPRECATED_SUFFIX = re.compile(r"\s*\(Deprecated\)\s*$", re.I)


def proto_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def enum_span(txt: str, name: str):
    """(start, end) of the body of `enum <name>`, or None."""
    m = re.search(r"\benum\s+" + re.escape(name) + r"\s*\{", txt)
    if not m:
        return None
    i = txt.index("{", m.start())
    depth, j = 1, i + 1
    while j < len(txt) and depth:
        if txt[j] == "{":
            depth += 1
        elif txt[j] == "}":
            depth -= 1
        j += 1
    return i + 1, j - 1


def render(indent: str, entry: dict) -> str:
    inner = indent + "  "
    parts = []
    for key in ("label", "description", "keywords"):
        if key in entry:
            parts.append(f"{inner}{key}: {proto_string(entry[key])}")
    return "{\n" + "\n".join(parts) + "\n" + indent + "}"


def main() -> None:
    totals = {}
    for full, info in PLAN.items():
        short = full.split(".")[-1]
        path = PROTO_DIR / f"{info['file']}.proto"
        txt = path.read_text()
        span = enum_span(txt, short)
        if span is None:
            print(f"  !! {short}: not found in {path.name}", file=sys.stderr)
            continue
        start, end = span
        body = txt[start:end]
        applied = 0

        def sub(m: re.Match) -> str:
            nonlocal applied
            indent, name, num, opts, trail = (
                m.group("indent"), m.group("name"), m.group("num"),
                m.group("opts") or "", m.group("trail") or "",
            )
            entry = info["values"].get(num)
            if not entry or "enum_value_metadata" in opts:
                return m.group(0)
            entry = dict(entry)
            if "label" in entry:
                entry["label"] = DEPRECATED_SUFFIX.sub("", entry["label"])
            existing = opts.strip()[1:-1].strip() if opts.strip() else ""
            prefix = f"{existing}, " if existing else ""
            applied += 1
            block = render(indent, entry)
            return f"{indent}{name} = {num} [{prefix}(meshtastic.enum_value_metadata) = {block}];{trail}"

        pattern = re.compile(
            r"(?P<indent>[ \t]*)(?P<name>[A-Z][A-Z0-9_]*)\s*=\s*(?P<num>\d+)\s*"
            r"(?P<opts>\[[^\]]*\])?\s*;(?P<trail>[ \t]*//[^\n]*)?",
        )
        new_body = pattern.sub(sub, body)
        if applied:
            path.write_text(txt[:start] + new_body + txt[end:])
        totals[short] = applied

    for k, v in totals.items():
        print(f"  {v:3d}  {k}")
    print(f"  TOTAL {sum(totals.values())}")


if __name__ == "__main__":
    main()
