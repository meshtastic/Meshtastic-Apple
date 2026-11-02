#!/usr/bin/env python3
"""Refresh the bundled API seeds the app falls back to offline.

Each seed is written exactly as served, and only when its parsed content differs from the
bundled copy. A response that fails its guard leaves the bundled copy alone, so a degraded
API never replaces a good seed. DeviceHardware.json is synced by download_images.py instead,
since it travels with the device images.

Exits 1 when a fetch or guard fails, so the workflow run shows it.
"""

import json
import os
import sys
import urllib.request

RESOURCES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Meshtastic", "Resources")
REQUEST_TIMEOUT = 30


def event_firmware_ok(doc):
    return doc.get("version") == 2 and isinstance(doc.get("editions"), list) and len(doc["editions"]) > 0


def urls_ok(doc):
    # msh.to's own catalog, not api's resource/deviceLinks: the app decodes this
    # { Routes, Marketplaces } shape (MshToUrlsFile).
    return isinstance(doc.get("Routes"), list) and len(doc["Routes"]) > 0 and isinstance(doc.get("Marketplaces"), dict)


SEEDS = [
    ("event_firmware.json", "https://api.meshtastic.org/resource/eventFirmware", event_firmware_ok),
    ("urls.json", "https://msh.to/api/urls", urls_ok),
]


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Meshtastic-Apple seed sync"})
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
        return response.read()


def read_bundled(path):
    """The bundled seed's parsed content, or None when it is missing or not JSON."""
    try:
        with open(path, "rb") as existing:
            return json.loads(existing.read())
    except (OSError, ValueError):
        return None


def sync(file_name, url, guard):
    path = os.path.join(RESOURCES_DIR, file_name)
    try:
        body = fetch(url)
        doc = json.loads(body)
    except Exception as error:  # noqa: BLE001 - any fetch or parse failure keeps the seed
        print(f"{file_name}: fetch failed ({error}); keeping the bundled copy", file=sys.stderr)
        return False
    if not isinstance(doc, dict) or not guard(doc):
        print(f"{file_name}: degraded response from {url}; keeping the bundled copy", file=sys.stderr)
        return False

    if read_bundled(path) == doc:
        print(f"{file_name}: up to date")
        return True
    with open(path, "wb") as out:
        out.write(body)
    print(f"{file_name}: updated from {url}")
    return True


def main():
    results = [sync(*seed) for seed in SEEDS]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
