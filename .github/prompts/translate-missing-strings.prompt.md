---
description: "Translate all missing (empty) strings in Localizable.xcstrings using local-localizer with Apple on-device Intelligence"
---

# Translate Missing Strings

Run the on-device machine translation pipeline to fill in all truly empty strings in `Localizable.xcstrings`. This only translates strings that have **no entry at all** for a locale — existing `needs_review` translations are left untouched.

## Prerequisites

- **macOS 26+** with Apple Silicon
- **Apple Intelligence enabled** (System Settings → Apple Intelligence & Siri)
- **local-localizer** installed at `~/bin/local-localizer`:
  ```bash
  git clone https://github.com/JoshuaSullivan/local-localizer.git ~/local-localizer
  cd ~/local-localizer && swift build -c release
  cp .build/release/local-localizer ~/bin/local-localizer
  ```
  Ensure `~/bin` is on your PATH.

## Supported Locales

Apple Intelligence supports: `da`, `de`, `es`, `fr`, `it`, `ja`, `ko`, `pt-BR`, `zh-Hans`, `zh-Hant`, `zh-Hant-TW`

**Not supported** (require community contributors): `he`, `pl`, `ru`, `se`, `sr`

## Steps

1. **Create a branch** from `main`:
   ```bash
   git checkout main && git pull
   git checkout -b translations/update-missing-strings
   ```

2. **Audit** what's actually missing (optional, for visibility):
   ```bash
   python3 -c "
   import json
   with open('Localizable.xcstrings', encoding='utf-8') as f:
       data = json.load(f)
   locales = ['da', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pt-BR', 'zh-Hans', 'zh-Hant', 'zh-Hant-TW']
   for lang in locales:
       missing = sum(1 for k, v in data['strings'].items() if k and lang not in v.get('localizations', {}))
       print(f'{lang}: {missing} empty')
   "
   ```

3. **Generate per-locale key files** (only truly empty strings):
   ```bash
   python3 -c "
   import json, os
   with open('Localizable.xcstrings', encoding='utf-8') as f:
       data = json.load(f)
   locales = ['da', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pt-BR', 'zh-Hans', 'zh-Hant', 'zh-Hant-TW']
   os.makedirs('/tmp/translate-keys', exist_ok=True)
   for lang in locales:
       keys = [k for k, v in data['strings'].items() if k and lang not in v.get('localizations', {})]
       with open(f'/tmp/translate-keys/{lang}.txt', 'w') as f:
           f.write('\n'.join(keys))
       print(f'{lang}: {len(keys)} keys')
   "
   ```

4. **Run translations** for each locale using `--keys-from` to target only empty strings:
   ```bash
   export PATH="$HOME/bin:$PATH"
   for locale in da de es fr it ja ko pt-BR zh-Hans zh-Hant zh-Hant-TW; do
     echo "━━━ Translating $locale ━━━"
     local-localizer Localizable.xcstrings \
       --locales "$locale" \
       --glossary scripts/glossary.json \
       --tone professional \
       --state needs_review \
       --keys-from "/tmp/translate-keys/${locale}.txt" || echo "⚠️  $locale failed"
   done
   ```

5. **Commit and push**:
   ```bash
   git add Localizable.xcstrings scripts/glossary.json
   git commit -m "Add machine translations for empty strings (needs_review)

   Machine-translated using local-localizer with Apple on-device Intelligence.
   All new strings marked needs_review for native speaker verification."
   git push -u origin translations/update-missing-strings
   ```

## Glossary

The glossary at `scripts/glossary.json` controls:
- **doNotTranslate**: Brand names and technical terms that should never be translated (Meshtastic, LoRa, MQTT, BLE, etc.)
- **tone**: Per-locale tone overrides (`de` and `pt-BR` use `informal`; all others use `professional`)

## Notes

- Translations are written with `state: needs_review` — they ship but should be verified by native speakers.
- The `--keys-from` approach ensures existing `needs_review` or `translated` strings are never overwritten.
- Some keys may warn "not found in catalog" if they were recently removed — this is harmless.
- Apple Intelligence may occasionally flag strings as "unsafe" and skip them — these will need manual translation.
- Danish (`da`) falls back to `one/other` plural rules (no hardcoded plural rule in the tool).
