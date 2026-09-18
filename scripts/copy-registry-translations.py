#!/usr/bin/env python3
"""Copy existing translations onto the generated field-metadata catalog keys.

The registry (Meshtastic/Model/FieldMetadataRegistry.swift) emits every label,
description, unit and keyword as String(localized: "meshtastic.<field>.<attr>",
defaultValue: "<English>"). Those keys are new to Localizable.xcstrings and carry
English only. The screens they will replace use the English text itself as the
key - "Enabled", "Echo", "Alert when receiving a bell" - and those keys have been
translated for years, into as many as seventeen languages.

Switching a screen from literal keys to registry keys would therefore drop every
translation it has today. This copies each translation across where the English
text is identical, once, so the two key styles start level. It never touches an
`en` unit, never overwrites a translation a registry key already has, and keeps
each unit's review state as it found it: a string that needed review under its
old key still needs review under the new one.

    python3 scripts/copy-registry-translations.py            # apply
    python3 scripts/copy-registry-translations.py --dry-run  # report only
    python3 scripts/copy-registry-translations.py --catalog path/to/Localizable.xcstrings

Two literal keys can share an English text and disagree on a translation. Where
they do, that language is not copied for that text and the disagreement is
reported, rather than letting whichever key came last win.

Anything reworded upstream, so that the English no longer matches, is out of
reach here and goes through scripts/translate-locale.sh like any other new string.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "Localizable.xcstrings"
REGISTRY_PREFIX = "meshtastic."


def dump(catalog: dict) -> bytes:
    """Serialize the way Xcode does, so the diff is the units added and nothing else.

    Xcode keeps its own key order (not code-point order: an em dash sorts after CJK),
    writes an empty object as an opening brace, a blank line and a closing brace, uses
    " : " as the separator, leaves non-ASCII unescaped and ends without a newline.
    `json.loads` preserves the order it read, so re-emitting in that order reproduces
    the file byte for byte; the script checks that before changing anything.
    """
    def emit(value, depth: int = 0) -> str:
        pad = "  " * depth
        if isinstance(value, dict):
            if not value:
                return "{\n\n" + pad + "}"
            items = [f"{pad}  {json.dumps(k, ensure_ascii=False)} : {emit(v, depth + 1)}"
                     for k, v in value.items()]
            return "{\n" + ",\n".join(items) + "\n" + pad + "}"
        if isinstance(value, list):
            if not value:
                return "[\n\n" + pad + "]"
            return "[\n" + ",\n".join(f"{pad}  {emit(v, depth + 1)}" for v in value) + "\n" + pad + "]"
        return json.dumps(value, ensure_ascii=False)

    return emit(catalog).encode("utf-8")


def units(entry: dict) -> dict[str, dict]:
    """language -> stringUnit, for units that carry a value."""
    return {
        lang: loc["stringUnit"]
        for lang, loc in (entry.get("localizations") or {}).items()
        if loc.get("stringUnit", {}).get("value")
    }


def english(key: str, entry: dict) -> str:
    return units(entry).get("en", {}).get("value") or key


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="report without writing")
    parser.add_argument("--catalog", type=Path, default=CATALOG, help="a catalog other than the app's")
    args = parser.parse_args()
    catalog_path: Path = args.catalog

    raw = catalog_path.read_bytes()
    catalog = json.loads(raw)
    if dump(catalog) != raw:
        sys.exit(f"  {catalog_path.name} is not in the formatting this script writes; "
                 "open it in Xcode and save once, then rerun")
    strings = catalog["strings"]

    # Translations available per English text, from the literal keys. Every candidate
    # is kept so a disagreement between two keys can be seen rather than resolved by
    # whichever key happened to come last.
    candidates: dict[str, dict[str, list[dict]]] = {}
    for key, entry in strings.items():
        if key.startswith(REGISTRY_PREFIX):
            continue
        for lang, unit in units(entry).items():
            if lang != "en":
                candidates.setdefault(english(key, entry), {}).setdefault(lang, []).append(unit)

    by_english: dict[str, dict[str, dict]] = {}
    conflicts: list[str] = []
    for text, per_lang in candidates.items():
        for lang, found in per_lang.items():
            values = {unit["value"] for unit in found}
            if len(values) > 1:
                conflicts.append(f"{lang}: {text[:60]!r} -> {sorted(values)}")
                continue
            by_english.setdefault(text, {})[lang] = found[0]

    keys_touched = 0
    copied: Counter[str] = Counter()
    states: Counter[str] = Counter()
    for key, entry in strings.items():
        if not key.startswith(REGISTRY_PREFIX):
            continue
        source = by_english.get(english(key, entry))
        if not source:
            continue
        localizations = entry.setdefault("localizations", {})
        added = 0
        for lang, unit in source.items():
            # Only a localization that already carries a value is left alone; an empty
            # placeholder for the language is filled like a missing one.
            if localizations.get(lang, {}).get("stringUnit", {}).get("value"):
                continue
            localizations[lang] = {"stringUnit": {"state": unit.get("state", "translated"),
                                                  "value": unit["value"]}}
            copied[lang] += 1
            states[unit.get("state", "translated")] += 1
            added += 1
        if added:
            entry["localizations"] = dict(sorted(localizations.items()))
            keys_touched += 1

    registry_total = sum(1 for k in strings if k.startswith(REGISTRY_PREFIX))
    print(f"  registry keys: {registry_total}   gaining translations: {keys_touched}")
    print(f"  units copied: {sum(copied.values())}   by state: {dict(states)}")
    print("  by language: " + ", ".join(f"{lang} {n}" for lang, n in sorted(copied.items())))
    print(f"  disagreements between literal keys, not copied: {len(conflicts)}")
    for line in conflicts[:20]:
        print(f"    {line}")
    if args.dry_run:
        print("  dry run - nothing written")
        return
    catalog_path.write_bytes(dump(catalog))
    print(f"  wrote {catalog_path}")


if __name__ == "__main__":
    main()
