---
title: Translate the App
parent: User Guide
nav_order: 14
---

# Translate the App

Contributing translations to the Meshtastic Apple app helps make the project accessible to a wider audience. The process is designed to be simple: a script generates machine translations on your Mac using Apple Intelligence, marks them for review, and opens a pull request automatically. A native speaker then reviews and approves the strings in Xcode before they ship.

## Requirements

Before you start, make sure you have:

- **macOS 26 or later** with Apple Silicon
- **Apple Intelligence enabled** — System Settings → Apple Intelligence & Siri
- **[local-localizer](https://github.com/JoshuaSullivan/local-localizer)** installed (see below)
- **GitHub CLI** installed — `brew install gh` and `gh auth login`

### Install local-localizer

```bash
git clone https://github.com/JoshuaSullivan/local-localizer.git ~/local-localizer
cd ~/local-localizer && swift build -c release
mkdir -p ~/bin && cp .build/release/local-localizer ~/bin/local-localizer
```

Make sure `~/bin` is on your PATH (add `export PATH="$HOME/bin:$PATH"` to your shell profile if needed).

## Add or complete a locale

Clone the repository, then run the translation script with your locale code:

```bash
git clone https://github.com/meshtastic/Meshtastic-Apple.git
cd Meshtastic-Apple
scripts/translate-locale.sh <locale>
```

For example:

```bash
scripts/translate-locale.sh fr          # French
scripts/translate-locale.sh de formal   # German, formal register
scripts/translate-locale.sh ja polite   # Japanese, polite register
scripts/translate-locale.sh zh-Hant-TW  # Traditional Chinese (Taiwan)
```

The script will:

1. Count how many strings are missing or need updating for the locale
2. Generate a glossary that keeps Meshtastic brand terms (LoRa, MQTT, BLE, TAK, etc.) untranslated
3. Run local-localizer using on-device Apple Intelligence — no internet or API key needed
4. Mark every new string as **Needs Review** so native speakers know to check them
5. Commit the result and open a pull request automatically

The translation step runs entirely on your device and takes roughly 10–20 minutes for a complete locale.

## Tone options

| Tone | When to use |
|---|---|
| `professional` | Default — clear and neutral, suitable for most languages |
| `formal` | Recommended for German (`de`), French (`fr`), Italian (`it`), Spanish (`es`) — selects the polite second-person form (Sie / vous / Lei / usted) |
| `polite` | Recommended for Japanese (`ja`) and Korean (`ko`) — selects polite verb forms |
| `informal` | Casual register |
| `neutral` | Plain, no register preference |

## Reviewing translated strings

Once the PR is open, any native speaker can review the translations directly in Xcode:

1. Open `Meshtastic.xcworkspace`
2. Select `Localizable.xcstrings` in the project navigator
3. Filter by your locale and set the state filter to **Needs Review**
4. Read each string in context, edit if needed, and mark it **Reviewed**
5. Push your changes to the PR branch

## Automatic documentation translation

On devices running iOS 26 or later, the in-app documentation is automatically translated into your device language when you open **Help & Docs**. The translation pipeline works as follows:

1. The app reads the bundled English markdown source files.
2. Text segments are translated using Apple's Translation framework, falling back to on-device Foundation Models if your language is not supported.
3. Translated markdown is cached locally so subsequent visits load instantly.

After all pages are translated in the background, the app anonymously uploads the translated files to the [meshtastic/translations](https://github.com/meshtastic/translations) repository for community review and improvement.

> **Tip — English users**
> If your device language is English, no translation occurs and the bundled English documentation is displayed directly.

Thank you for helping expand the reach of Meshtastic!
