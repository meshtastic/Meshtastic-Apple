"""Replace weak or wrong labels with self-describing ones.

A schema label is read without the screen around it, so "Enabled" - which is what
the app shows inside a titled section - does not survive the trip. Several also
collided: NetworkConfig had three fields labelled "Enabled" and MQTTConfig two,
which would be indistinguishable as search results on the same screen.
"""
import re

FIXES = {
    ("BluetoothConfig", 1): "Bluetooth Enabled",
    ("NetworkConfig", 1): "WiFi Enabled",
    ("NetworkConfig", 6): "Ethernet Enabled",
    ("NetworkConfig", 10): "Enabled Protocols",
    ("PowerConfig", 2): "Shutdown on Power Loss",
    ("DetectionSensorConfig", 1): "Detection Sensor Enabled",
    ("ExternalNotificationConfig", 1): "External Notification Enabled",
    ("ExternalNotificationConfig", 9): "Output pin buzzer GPIO",
    ("ExternalNotificationConfig", 10): "Vibra Motor Alert",
    ("MQTTConfig", 1): "MQTT Enabled",
    ("MQTTConfig", 10): "Map Reporting",
    ("MapReportSettings", 3): "Report Location",
    ("NeighborInfoConfig", 1): "Neighbor Info Enabled",
    ("PaxcounterConfig", 1): "PAX Counter Enabled",
    ("RangeTestConfig", 1): "Range Test Enabled",
    ("SerialConfig", 1): "Serial Enabled",
    ("StoreForwardConfig", 1): "Store and Forward Enabled",
    ("TelemetryConfig", 8): "Power Measurement Enabled",
}
# Labels that are really prose: demote to description if none is set.
DEMOTE = {("ExternalNotificationConfig", 10), ("MapReportSettings", 3)}


def match_brace(t, i):
    d, j = 1, i + 1
    while j < len(t) and d:
        d += 1 if t[j] == "{" else -1 if t[j] == "}" else 0
        j += 1
    return j


def spans(t, name):
    for m in re.finditer(r"\bmessage\s+" + re.escape(name) + r"\s*\{", t):
        i = t.index("{", m.start())
        yield i + 1, match_brace(t, i) - 1


changed = 0
for path in ("meshtastic/config.proto", "meshtastic/module_config.proto"):
    with open(path, encoding="utf-8") as handle:
        t = handle.read()
    for (msg, tag), new in FIXES.items():
        for lo, hi in spans(t, msg):
            body = t[lo:hi]
            pat = re.compile(
                r"(^[ \t]*(?:optional |repeated )?[\w.]+[ \t]+\w+ = " + str(tag)
                + r" \[\(meshtastic\.field_metadata\) = \{)(.*?)(\n?[ \t]*\}\];)",
                re.S | re.M,
            )
            m = pat.search(body)
            if not m:
                continue
            attrs = m.group(2)
            lm = re.search(r'label: "((?:[^"\\]|\\.)*)"', attrs)
            if not lm:
                continue
            old = lm.group(1)
            if (msg, tag) in DEMOTE and "description:" not in attrs:
                attrs = attrs.replace(
                    f'label: "{old}"', f'label: "{new}"\n      description: "{old}"', 1
                )
            else:
                attrs = attrs.replace(f'label: "{old}"', f'label: "{new}"', 1)
            t = t[:lo] + body[:m.start()] + m.group(1) + attrs + m.group(3) + body[m.end():] + t[hi:]
            print(f"  {msg}#{tag}: {old[:40]!r} -> {new!r}")
            changed += 1
            break
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(t)
print(f"  {changed} labels fixed")
