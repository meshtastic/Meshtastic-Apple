---
title: Translate the App
parent: User Guide
nav_order: 14
---

# Translate the App

## Automatic documentation translation

On devices running iOS 26 or later, the in-app documentation is automatically translated into your device language when you open **Help & Documentation**.

**Here's how it works:** The very first person to use a particular language + app version combination translates all pages on-device and automatically contributes their translations back to the community. Every user after them gets those translations instantly — no waiting for on-device translation.

1. You open **Help & Documentation** in a non-English language.
2. If community translations already exist for your language and app version, they're downloaded instantly.
3. If not, Apple's Translation framework translates every page on-device (~10 seconds per page).
4. Your translations are anonymously uploaded to the [meshtastic/translations](https://github.com/meshtastic/translations) repository.
5. The next user in your language gets instant translated docs from the community cache.

No sign-up, no manual work — it just happens in the background while you use the app. You can disable this by toggling off **Participate in Distributed Translations** in App Settings.

> **Tip — English users**
> If your device language is English, no translation occurs and the bundled English documentation is displayed directly.

---

## Contributing app translations

Contributing translations helps make Meshtastic accessible to a wider audience. Native speakers can review machine-translated strings for their language directly in Xcode — look for strings marked **Needs Review** and improve anything that sounds unnatural. Missing strings are filled with Xcode's translation agent, and anyone with Xcode 27 can run it for a language.

### Review machine translations

All on-device translations are uploaded to the [meshtastic/translations](https://github.com/meshtastic/translations) repository. They're a great starting point, but machine translations aren't perfect! If you're a native speaker and spot something that could be improved:

1. Browse to your language + app version at [apple-apps/](https://github.com/meshtastic/translations/tree/main/apple-apps)
2. Edit the `.md` file directly on GitHub
3. Submit a pull request

Your improvements will be served to every user of that language going forward — no coding required.

---

## Generate new translations

New strings are translated with the translation agent built into Xcode 27. It reads each string's comment, the code that uses it and the existing translations, and follows Apple's style guide for the language. The maintainers run it for every language when a release branch is cut.

### Requirements

- **Xcode 27 or later**, running
- **[Claude Code](https://claude.com/product/claude-code)** installed and signed in

### Translate a language

```bash
git clone https://github.com/meshtastic/Meshtastic-Apple.git
cd Meshtastic-Apple
scripts/translate-catalog.sh <locale>            # fill strings with no translation
scripts/translate-catalog.sh <locale> --review   # redo strings marked Needs Review
```

The first run asks you, in Xcode, to let the agent open the project.

The script:

1. Translates the strings in batches, 300 at a time, until none are left
2. Passes the [translation guide](https://github.com/meshtastic/Meshtastic-Apple/blob/main/scripts/translation-guide.md) with every batch: terms to leave in English, the tone for each language, and words already settled
3. Never changes a string already marked **Reviewed**, and marks new ones **Machine Translated**
4. Copies only that language back into `Localizable.xcstrings`, since Xcode re-sorts the whole file when it saves

It doesn't commit anything. Check `git diff`, read the notes it saves on choices worth checking, and open a pull request with one language in it. When you settle a term, add it to the translation guide so later runs use it too.

You can also open `Localizable.xcstrings` in Xcode, select a language and choose **Generate Translations**, using the coding agent set up in Xcode's Intelligence settings. That doesn't use the translation guide, and Xcode re-sorts the whole file, so the script is the better choice for a pull request.

### Reviewing translated strings

Any native speaker can review the translations in Xcode:

1. Open `Meshtastic.xcodeproj`
2. Select `Localizable.xcstrings` in the project navigator
3. Pick your language and filter to **Machine Translated** or **Needs Review**
4. Read each string in context, edit it if needed, and mark it **Reviewed**
5. Open a pull request with your changes

Thank you for helping expand the reach of Meshtastic!
