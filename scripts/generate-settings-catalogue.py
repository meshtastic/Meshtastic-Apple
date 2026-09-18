#!/usr/bin/env python3
"""Generate the app-level half of the settings search index.

Settings backed by a protobuf field get their label, description and keywords from
the schema through FieldMetadataRegistry. The rest — app preferences, tools, the
screens that exist only here — have no schema to generate from, so they were
hand-written, and a hand-written catalogue of this size goes stale the moment
someone adds a toggle.

This reads the views instead, the same way scripts/build-docs.sh reads the
documentation pages to build docs/index.json. A test regenerates and compares, so
adding a control without regenerating fails rather than going quietly
unsearchable — the model xcodegen-drift already uses for the project file.

    python3 scripts/generate-settings-catalogue.py            # write the file
    python3 scripts/generate-settings-catalogue.py --check    # exit 1 if stale

Keywords are not extracted. They cannot be derived from a view, and the one place
they earn their keep — "psk" for Channels, which nothing on screen says — is
declared in EXTRA_KEYWORDS below and merged in.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
VIEWS = REPO / "Meshtastic/Views"
OUTPUT = REPO / "Meshtastic/Model/Search/SettingsSearchCatalogue.swift"

# view path (under Meshtastic/Views) -> (destination, screen title, list section,
# requires a radio, requires a developer build)
#
# Only screens with no protobuf behind them. A settings screen backed by a config
# message is indexed from the registry instead, and listing it here would duplicate
# every one of its controls.
#
# The list section is the group the row sits in on the Settings screen, so a result
# carries the breadcrumb a user would have scrolled to. Paths are relative to
# Meshtastic/Views because several of these screens live in their own folders, and
# the Core Data browser is not under Settings at all.
#
# The last two flags are per-screen rather than per-control because every control on
# a given screen shares them. Channels, the QR code, the user record, the ringtone
# and the TAK server all read or write the connected node, so they are dimmed while
# disconnected. The Developers section renders only in debug and TestFlight builds,
# so its screens are hidden outright on an App Store build.
SCREENS: dict[str, tuple[str, str, str, bool, bool]] = {
    # The unlabelled group at the top of Settings.
    "Settings/About.swift": ("about", "About", "general", False, False),
    "Settings/HelpAndDocumentation/DocBrowserView.swift": (
        "helpDocs", "Help & Documentation", "general", False, False),
    "Settings/AppSettings.swift": ("appSettings", "App Settings", "general", False, False),
    "Settings/Discovery/DiscoveryScanView.swift": (
        "localMeshDiscovery", "Local Mesh Discovery", "general", False, False),
    "Settings/Routes.swift": ("routes", "Routes", "general", False, False),
    "Settings/RouteRecorder.swift": ("routeRecorder", "Route Recorder", "general", False, False),
    "Settings/Firmware/Firmware.swift": (
        "firmwareUpdates", "Firmware Updates", "general", False, False),

    "Settings/Channels.swift": ("channels", "Channels", "radioConfiguration", True, False),
    "Settings/ShareChannels.swift": (
        "shareQRCode", "Share QR Code", "radioConfiguration", True, False),

    "Settings/UserConfig.swift": ("user", "User", "deviceConfiguration", True, False),

    "Settings/TAKServerConfig.swift": ("tak", "TAK Server", "configure", True, False),
    "Settings/Config/Module/RtttlConfig.swift": ("ringtone", "Ringtone", "configure", True, False),

    "Settings/AppLog.swift": ("debugLogs", "Logs", "logging", False, False),
    "Settings/AllTraceRoutesLog.swift": ("traceRoutes", "Trace Routes", "logging", False, False),

    "Settings/BackupManagement/BackupManagement.swift": (
        "backupManagement", "Backup Management", "developers", False, True),
    "Debugging/CoreDataBrowser.swift": (
        "coreDataBrowser", "Data Browser", "developers", False, True),
    "Settings/DeviceLinkDirectory.swift": (
        "deviceLinks", "Device Links", "developers", False, True),
    "Settings/AppData.swift": ("appFiles", "App Data", "developers", False, True),
    "Settings/Tools.swift": ("tools", "Tools", "developers", False, True),
}

# Terms a user would search for that appear nowhere on the screen. Kept small and
# deliberate: a label that already says what it is needs no synonyms, and ranking
# weights a keyword below a label anyway.
EXTRA_KEYWORDS: dict[tuple[str, str], list[str]] = {
    ("channels", "Channels"): ["psk", "encryption", "key", "primary", "secondary"],
    ("localMeshDiscovery", "Local Mesh Discovery"): ["lan", "network", "wifi", "scan", "bonjour"],
    ("firmwareUpdates", "Firmware Updates"): ["update", "flash", "ota", "version"],
    ("helpDocs", "Help & Documentation"): ["help", "docs", "manual", "guide"],
    ("traceRoutes", "Trace Routes"): ["hops", "path", "route"],
    ("debugLogs", "Logs"): ["debug", "console", "diagnostics"],
    ("shareQRCode", "Share QR Code"): ["qr", "share", "invite"],
    ("appSettings", "Usage and Crash Data"): ["analytics", "telemetry", "privacy"],
    ("appSettings", "Clear App Data"): ["erase", "delete", "reset"],
    ("appSettings", "App Icon"): ["icon", "appearance"],
    ("routes", "Routes"): ["track", "gpx"],
}

# Sheet and form chrome. These are labelled controls but not settings, and a search
# result reading "Save" that navigates to a screen is worse than no result.
CHROME = {"Close", "Save", "Cancel", "Done", "OK", "Dismiss", "Back"}

SECTION_RE = re.compile(r'Section\((?:header:\s*)?(?:Text\()?\s*"((?:[^"\\]|\\.)*)"')
LABEL_RE = re.compile(r'Label\(\s*"((?:[^"\\]|\\.)*)"')
TEXT_RE = re.compile(r'Text\(\s*"((?:[^"\\]|\\.)*)"')


def swift_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def controls(source: str) -> list[dict]:
    """Every labelled control in a view, in file order, with its section heading."""
    lines = source.split("\n")
    found: list[dict] = []
    section: str | None = None
    seen: set[str] = set()

    def add(label: str | None, description: str | None = None) -> None:
        if not label:
            return
        label = label.strip()
        # Interpolated strings are not display text a catalogue can hold, and a
        # duplicate label on one screen is indistinguishable in results.
        if not label or "\\(" in label or label in seen or label in CHROME:
            return
        if description and ("\\(" in description or len(description) < 25):
            description = None
        seen.add(label)
        found.append({"label": label, "description": description, "section": section})

    for i, line in enumerate(lines):
        heading = SECTION_RE.search(line)
        if heading:
            section = heading.group(1)
            continue

        # Picker("X", selection:) / Toggle("X", isOn:) / TextField("X", text:)
        first_arg = re.search(
            r'(?:Picker|Toggle|TextField)\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*(?:selection|isOn|text|value):',
            line)
        if first_arg:
            add(first_arg.group(1))
            continue

        # Toggle(isOn: $x) { Label("X", …); Text("why") }  — or a bare Text label
        if re.search(r'Toggle\(\s*isOn:', line) and line.rstrip().endswith("{"):
            label, description = None, None
            for probe in lines[i + 1:i + 6]:
                if label is None:
                    hit = LABEL_RE.search(probe)
                    if hit:
                        label = hit.group(1)
                        continue
                hit = TEXT_RE.search(probe)
                if hit:
                    if label is None:
                        label = hit.group(1)
                    else:
                        description = hit.group(1)
                        break
                elif re.match(r"\s*\}", probe):
                    break
            add(label, description)
            continue

        # A Label inside a Button or NavigationLink: an action row, still a thing
        # a user searches for ("Clear App Data").
        row = LABEL_RE.search(line)
        if row and re.search(r"Button|NavigationLink", "\n".join(lines[max(0, i - 3):i + 1])):
            add(row.group(1))

    return found


def render() -> str:
    out: list[str] = [
        "//",
        "//  SettingsSearchCatalogue.swift",
        "//  Meshtastic",
        "//",
        "//  GENERATED by scripts/generate-settings-catalogue.py — do not edit by hand.",
        "//  Run that script after adding or renaming a control on an app-level settings",
        "//  screen; SettingsSearchCatalogueTests fails when this file is stale.",
        "//",
        "import Foundation",
        "",
        "/// The settings with no protobuf behind them.",
        "///",
        "/// Everything the radio stores comes from the schema through FieldMetadataRegistry.",
        "/// These do not — they are app preferences, tools and screens that exist only here —",
        "/// so they are read out of the views themselves rather than written twice.",
        "///",
        "/// `requiresConnection` is false throughout: these work with no radio attached, which",
        "/// is most of why they are worth finding while disconnected.",
        "enum SettingsSearchCatalogue {",
        "",
        "\tstatic let entries: [SettingsSearchEntry] = [",
    ]

    total = 0
    for filename in sorted(SCREENS):
        path = VIEWS / filename
        if not path.exists():
            # Not a skip: a renamed or deleted view would drop an entire screen from
            # the index, and --check would happily accept the smaller catalogue.
            raise SystemExit(
                f"  {filename} is listed in SCREENS but does not exist under {VIEWS.relative_to(REPO)}/.\n"
                "  Update SCREENS if the view was renamed or removed.")
        destination, screen, section, needs_radio, needs_dev = SCREENS[filename]
        items = controls(path.read_text())
        # The screen itself, so "Channels" finds Channels and screen-wide keywords
        # have somewhere to live. Emitted even when no control was extracted - a
        # screen built entirely from custom views still deserves to be findable.
        if not any(item["label"] == screen for item in items):
            items = [{"label": screen, "description": None, "section": None}] + items
        out.append(f"\t\t// MARK: {screen}")
        for item in items:
            total += 1
            parts = [
                f"destination: .{destination}",
                f"screenTitle: String(localized: {swift_string(screen)}, comment: \"Settings screen\")",
            ]
            if item["section"]:
                parts.append(
                    "sectionTitle: String(localized: "
                    f"{swift_string(item['section'])}, comment: \"Settings section\")")
            parts.append(f"listSection: .{section}")
            parts.append(
                f"label: String(localized: {swift_string(item['label'])}, comment: \"Settings control\")")
            if item["description"]:
                parts.append(
                    "subtitle: String(localized: "
                    f"{swift_string(item['description'])}, comment: \"Settings control\")")
            extra = EXTRA_KEYWORDS.get((destination, item["label"]))
            if extra:
                keywords = ", ".join(
                    f"String(localized: {swift_string(k)}, comment: \"Search keyword\")" for k in extra)
                parts.append(f"keywords: [{keywords}]")
            parts.append(f"requiresConnection: {str(needs_radio).lower()}")
            if needs_dev:
                parts.append("requiresDeveloperBuild: true")
            out.append("\t\t.init(")
            for part in parts[:-1]:
                out.append(f"\t\t\t{part},")
            out.append(f"\t\t\t{parts[-1]}),")
        out.append("")

    if out[-1] == "":
        out.pop()
    out += ["\t]", "}", ""]
    sys.stderr.write(f"  {total} controls across {len(SCREENS)} screens\n")
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="exit 1 if the committed file is stale")
    args = parser.parse_args()

    generated = render()
    if args.check:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""
        if current != generated:
            sys.stderr.write(
                f"  {OUTPUT.relative_to(REPO)} is stale — "
                "run scripts/generate-settings-catalogue.py and commit the result\n")
            sys.exit(1)
        sys.stderr.write("  catalogue is current\n")
        return
    OUTPUT.write_text(generated)
    sys.stderr.write(f"  wrote {OUTPUT.relative_to(REPO)}\n")


if __name__ == "__main__":
    main()
