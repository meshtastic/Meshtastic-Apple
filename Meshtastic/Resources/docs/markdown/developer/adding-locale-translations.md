# Adding or Completing Locale Translations

This guide describes exactly how to add missing machine translations for a locale in `Localizable.xcstrings` using [local-localizer](https://github.com/JoshuaSullivan/local-localizer) — an on-device Apple Intelligence tool that requires no API keys or network access.

## Prerequisites

- macOS 26 or later with Apple Silicon
- Apple Intelligence enabled (System Settings → Apple Intelligence & Siri)
- Xcode 26 toolchain
- The locale you are targeting must already have **some** existing translated strings to use as a tone reference

---

## Step 1 — Create a feature branch

```bash
git checkout main && git pull
git checkout -b translations/<locale-name>
# e.g. git checkout -b translations/chinese-traditional
```

---

## Step 2 — Audit what is missing

Run this script to count how many strings are missing or in `needs_review` for the target locale:

```bash
python3 - <<'EOF'
import json

LANG = "zh-Hant-TW"   # <-- change to your target locale

with open("Localizable.xcstrings", encoding="utf-8") as f:
    data = json.load(f)

strings = data.get("strings", {})
missing, total = [], 0
for key, val in strings.items():
    if not key:
        continue
    total += 1
    locs = val.get("localizations", {})
    if LANG not in locs:
        missing.append(key)
    else:
        loc = locs[LANG]
        if "stringUnit" in loc and loc["stringUnit"].get("state") not in ("translated",):
            missing.append(key)

print(f"Total keys : {total}")
print(f"Missing    : {len(missing)}")
EOF
```

---

## Step 3 — Sample existing translations to assess tone

Before generating new strings it is important to understand the register and style of what is already there. Run:

```bash
python3 - <<'EOF'
import json

LANG = "zh-Hant-TW"

with open("Localizable.xcstrings", encoding="utf-8") as f:
    data = json.load(f)

samples = []
for key, val in data["strings"].items():
    if not key:
        continue
    locs = val.get("localizations", {})
    if LANG in locs:
        unit = locs[LANG].get("stringUnit", {})
        if unit.get("state") == "translated":
            samples.append((key, unit.get("value", "")))
    if len(samples) >= 30:
        break

for k, v in samples:
    print(f"EN: {k}")
    print(f"{LANG}: {v}\n")
EOF
```

Use the output to decide the appropriate `--tone` value (`professional`, `formal`, `informal`, `polite`, `neutral`).

---

## Step 4 — Create a glossary file

Create `scripts/<locale>-glossary.json` to:
- Prevent brand and technical terms from being translated
- Set the tone for the locale

Example for `zh-Hant-TW`:

```json
{
  "doNotTranslate": [
    "Meshtastic",
    "LoRa",
    "MQTT",
    "BLE",
    "GPS",
    "TAK",
    "CoT",
    "PKC",
    "SNR",
    "GPIO",
    "DFU",
    "API",
    "Wi-Fi",
    "Bluetooth",
    "IAQ",
    "ATAK",
    "WinTAK",
    "mPWRD-OS",
    "iOS",
    "macOS",
    "CarPlay",
    "SiriKit"
  ],
  "tone": {
    "default": "professional",
    "zh-Hant-TW": "professional"
  }
}
```

Adjust the `doNotTranslate` list and `tone` based on the locale. For European languages, `formal` selects the polite second-person form (Sie/vous/Lei/usted). For Japanese/Korean, use `polite`.

---

## Step 5 — Install local-localizer

```bash
git clone https://github.com/JoshuaSullivan/local-localizer.git ~/Source/local-localizer
cd ~/Source/local-localizer
swift build -c release
mkdir -p ~/bin
cp .build/release/local-localizer ~/bin/local-localizer
```

> Make sure `~/bin` is on your `PATH`, or call the binary with its full path.

---

## Step 6 — Do a dry run

Always verify the work plan before translating:

```bash
cd /path/to/Meshtastic-Apple
~/bin/local-localizer Localizable.xcstrings \
  --locales zh-Hant-TW \
  --glossary scripts/zh-Hant-TW-glossary.json \
  --dry-run
```

Check that:
- The key count matches your audit from Step 2
- No unexpected keys are listed (e.g. keys you expected to be skipped)

---

## Step 7 — Run the translation

```bash
~/bin/local-localizer Localizable.xcstrings \
  --locales zh-Hant-TW \
  --glossary scripts/zh-Hant-TW-glossary.json
```

> **Do not pass `--state translated`.** The default state is `needs_review`, which is correct for machine translations — it signals to native speakers that the strings need human review before shipping.

This runs entirely on-device using Apple Intelligence. Expect roughly 1–2 seconds per string. For ~500 strings, allow 10–20 minutes. The process writes results to the file incrementally so it is safe to interrupt and resume.

---

## Step 8 — Verify results

After completion, verify full coverage and that all new strings are `needs_review`:

```bash
python3 - <<'EOF'
import json

LANG = "zh-Hant-TW"

with open("Localizable.xcstrings", encoding="utf-8") as f:
    data = json.load(f)

missing, needs_review, translated = [], 0, 0
for key, val in data["strings"].items():
    if not key:
        continue
    locs = val.get("localizations", {})
    if LANG not in locs:
        missing.append(key)
    else:
        loc = locs[LANG]
        if "stringUnit" in loc:
            state = loc["stringUnit"].get("state")
            if state == "translated":
                translated += 1
            elif state == "needs_review":
                needs_review += 1
            else:
                missing.append(key)
        elif "variations" in loc:
            translated += 1  # plural variations are always fine

print(f"Confirmed translated : {translated}")
print(f"Needs review         : {needs_review}")
print(f"Still missing        : {len(missing)}")
if missing:
    print("Missing keys:", missing)
EOF
```

Expected output: `Still missing: 0`. If any keys remain, add them manually (common for plural-only variation entries or strings containing unsupported characters).

---

## Step 9 — Verify pre-existing strings are unchanged

Confirm that the pre-existing `translated` strings were not downgraded to `needs_review` by comparing against the previous commit:

```bash
python3 - <<'EOF'
import json, subprocess

LANG = "zh-Hant-TW"

old = json.loads(subprocess.check_output(["git", "show", "HEAD:Localizable.xcstrings"]))
with open("Localizable.xcstrings", encoding="utf-8") as f:
    new = json.load(f)

regressions = []
for key, val in old["strings"].items():
    locs = val.get("localizations", {})
    if LANG in locs:
        old_state = locs[LANG].get("stringUnit", {}).get("state")
        new_state = new["strings"].get(key, {}).get("localizations", {}).get(LANG, {}).get("stringUnit", {}).get("state")
        if old_state == "translated" and new_state != "translated":
            regressions.append(key)

print(f"Regressions (translated → other): {len(regressions)}")
if regressions:
    print(regressions[:20])
EOF
```

---

## Step 10 — Commit and open a PR

```bash
git add Localizable.xcstrings scripts/<locale>-glossary.json
git commit -m "Add <Language> (<locale>) localisation strings

Add <N> missing <Language> translations to Localizable.xcstrings covering
all user-visible strings. Translations generated using local-localizer with
Apple on-device Foundation Models. All machine-translated strings are marked
needs_review for native speaker review."

git push -u origin translations/<locale-name>
gh pr create --base main \
  --title "Add <Language> (<locale>) localisation strings" \
  --body "..."
```

### PR description checklist
- State how many strings were added and how many were already translated
- Note that all machine translations are `needs_review`
- Link to local-localizer and mention on-device (no API key, no network)
- Invite native speakers to review

---

## Notes and caveats

- **Always have a native speaker review.** `needs_review` state in Xcode flags the strings for review before shipping.
- **Plural variation entries** (keys with `%lld` generating `one`/`other`/`few` etc.) are handled automatically by local-localizer for `.xcstrings` files. Chinese/Japanese/Korean only need `other`.
- **Do not use `--overwrite`** unless you specifically want to re-translate already-confirmed `translated` strings.
- **Format specifiers** (`%@`, `%lld`, `%d`) are preserved by local-localizer's built-in placeholder protection.
- **The glossary file** should be committed alongside the translation so the same settings can be used for future re-runs when new strings are added.
