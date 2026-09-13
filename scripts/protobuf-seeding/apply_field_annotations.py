#!/usr/bin/env python3
"""Apply seeded (meshtastic.field_metadata) label/description into the .proto files.

Companion to apply_enum_annotations.py, for field declarations rather than enum
values. Merges with any existing options, preserves trailing comments, and is
idempotent - a field already carrying the annotation is left alone.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PROTO_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("meshtastic")
PLAN = json.load(open(sys.argv[2] if len(sys.argv) > 2 else "/tmp/fplan.json"))["plan"]

# Anchored to line start with HORIZONTAL whitespace only: `\s` would span newlines
# and let a word from the preceding comment stand in as the type, which silently
# matches enum value lines (`LOGIC_HIGH = 1;`) as if they were fields.
FIELD_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?P<type>(?:optional[ \t]+|repeated[ \t]+)?[\w.]+[ \t]+)"
    r"(?P<name>\w+)[ \t]*=[ \t]*(?P<num>\d+)[ \t]*(?P<opts>\[(?:[^\[\]]|\[[^\]]*\])*\])?[ \t]*;"
    r"(?P<trail>[ \t]*//[^\n]*)?$",
    re.M,
)


def proto_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def match_brace(txt: str, open_idx: int) -> int:
    depth, j = 1, open_idx + 1
    while j < len(txt) and depth:
        if txt[j] == "{":
            depth += 1
        elif txt[j] == "}":
            depth -= 1
        j += 1
    return j


def message_span(txt: str, full: str):
    """(start, end) of the body of the message named by the dotted path, or None."""
    parts = full.split(".")[1:]  # drop the package
    lo, hi = 0, len(txt)
    for depth, part in enumerate(parts):
        pat = re.compile(r"\bmessage\s+" + re.escape(part) + r"\s*\{")
        m = pat.search(txt, lo, hi)
        if not m:
            return None
        open_idx = txt.index("{", m.start())
        end = match_brace(txt, open_idx)
        lo, hi = open_idx + 1, end - 1
    return lo, hi


def render(indent: str, entry: dict) -> str:
    inner = indent + "  "
    parts = [
        f"{inner}{k}: {proto_string(entry[k])}"
        for k in ("label", "description", "keywords")
        if k in entry
    ]
    return "{\n" + "\n".join(parts) + "\n" + indent + "}"


def main() -> None:
    totals: dict[str, int] = {}
    for full, info in PLAN.items():
        for fname in ("config", "module_config"):
            path = PROTO_DIR / f"{fname}.proto"
            txt = path.read_text()
            span = message_span(txt, full)
            if span is None:
                continue
            start, end = span
            body = txt[start:end]
            # Mask nested enum and message bodies so only this message's own field
            # declarations are candidates.
            masked = list(body)
            for nm in re.finditer(r"\b(?:message|enum)\s+\w+\s*\{", body):
                oi = body.index("{", nm.start())
                for k in range(nm.start(), match_brace(body, oi)):
                    if masked[k] != "\n":
                        masked[k] = " "
            body_masked = "".join(masked)
            applied = 0

            def sub(m: re.Match) -> str:
                nonlocal applied
                opts = m.group("opts") or ""
                entry = info["values"].get(m.group("num"))
                if not entry or "field_metadata" in opts:
                    return m.group(0)
                existing = opts.strip()[1:-1].strip() if opts.strip() else ""
                prefix = f"{existing}, " if existing else ""
                applied += 1
                indent = m.group("indent")
                return (
                    f"{indent}{m.group('type')}{m.group('name')} = {m.group('num')} "
                    f"[{prefix}(meshtastic.field_metadata) = {render(indent, entry)}];"
                    f"{m.group('trail') or ''}"
                )

            # Substitute over the masked text, then splice the untouched regions back.
            pieces, last = [], 0
            for m in FIELD_RE.finditer(body_masked):
                pieces.append(body[last:m.start()])
                pieces.append(sub(m))
                last = m.end()
            pieces.append(body[last:])
            new_body = "".join(pieces)
            if applied:
                path.write_text(txt[:start] + new_body + txt[end:])
            totals[full] = totals.get(full, 0) + applied
            break

    for k in sorted(totals):
        if totals[k]:
            print(f"  {totals[k]:3d}  {k}")
    print(f"  TOTAL {sum(totals.values())}")


if __name__ == "__main__":
    main()
