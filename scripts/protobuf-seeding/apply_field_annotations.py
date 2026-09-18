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

SUPPORTED = ("label", "description", "keywords", "unit", "min_value", "max_value")

ARGS = [a for a in sys.argv[1:] if not a.startswith("--only=")]
ONLY = next((set(a.split("=", 1)[1].split(",")) - {""} for a in sys.argv[1:] if a.startswith("--only=")), None)
if ONLY is not None:
    # A typo here would otherwise write empty annotation blocks and report success.
    unknown = sorted(ONLY - set(SUPPORTED))
    if unknown or not ONLY:
        sys.exit(f"--only: {'unsupported ' + ', '.join(unknown) if unknown else 'no attributes given'}; "
                 f"choose from {', '.join(SUPPORTED)}")
PROTO_DIR = Path(ARGS[0]) if len(ARGS) > 0 else Path("meshtastic")
PLAN_PATH = Path(ARGS[1] if len(ARGS) > 1 else "/tmp/fplan.json")
with PLAN_PATH.open(encoding="utf-8") as plan_file:
    PLAN = json.load(plan_file)["plan"]

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


ATTRIBUTES = tuple(k for k in SUPPORTED if ONLY is None or k in ONLY)


def attribute_line(inner: str, key: str, value) -> str:
    if key in ("min_value", "max_value"):
        number = float(value)
        text = str(int(number)) if number == int(number) else repr(number)
        return f"{inner}{key}: {text}"
    return f"{inner}{key}: {proto_string(str(value))}"


def render(indent: str, entry: dict) -> str:
    inner = indent + "  "
    parts = [attribute_line(inner, k, entry[k]) for k in ATTRIBUTES if k in entry]
    return "{\n" + "\n".join(parts) + "\n" + indent + "}"


def merge(opts: str, indent: str, entry: dict) -> str | None:
    """Add the attributes `entry` has and the existing block lacks; None if nothing to add.

    The block is rewritten one attribute per line in its existing order, with the
    missing ones appended, so a single-line original comes out in the multi-line
    style `buf format` writes and the diff is only the lines added.
    """
    m = re.search(r"\(meshtastic\.field_metadata\)\s*=\s*\{", opts)
    if not m:
        return None
    open_idx = opts.index("{", m.start())
    close_idx = match_brace(opts, open_idx) - 1
    body = opts[open_idx + 1:close_idx]
    # Text-format scalars: a quoted string, a number in any spelling the format
    # accepts (1e6, -0.5, .25), or a bare identifier such as true.
    pair_re = re.compile(r'(\w+)\s*:\s*("(?:[^"\\]|\\.)*"|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?|\w+)')
    pairs = pair_re.findall(body)
    # The block is rebuilt from these pairs, so anything the pattern did not
    # recognise would be dropped silently. Refuse rather than lose it.
    leftover = pair_re.sub("", body).strip()
    if leftover:
        sys.exit(f"cannot rebuild a field_metadata block; unrecognised content: {leftover!r}")
    present = {k for k, _ in pairs}
    missing = [k for k in ATTRIBUTES if k in entry and k not in present]
    if not missing:
        return None
    inner = indent + "  "
    lines = [f"{inner}{k}: {v}" for k, v in pairs]
    lines += [attribute_line(inner, k, entry[k]) for k in missing]
    return opts[:open_idx] + "{\n" + "\n".join(lines) + "\n" + indent + "}" + opts[close_idx + 1:]


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
                if not entry:
                    return m.group(0)
                indent = m.group("indent")
                if "field_metadata" in opts:
                    merged = merge(opts, indent, entry)
                    if merged is None:
                        return m.group(0)
                    applied += 1
                    return (f"{indent}{m.group('type')}{m.group('name')} = {m.group('num')} "
                            f"{merged};{m.group('trail') or ''}")
                existing = opts.strip()[1:-1].strip() if opts.strip() else ""
                prefix = f"{existing}, " if existing else ""
                applied += 1
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
