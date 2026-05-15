---
title: Translate the App
parent: User Guide
nav_order: 14
---

# Translate the App

Contributing translations to the Meshtastic Apple app helps make the project accessible to a wider audience. The app uses [string catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) in Xcode to manage translations.

## Automatic Documentation Translation

On devices running iOS 26 or later, the in-app documentation is automatically translated into your device language when you open the **Help & Docs** section. The translation pipeline works as follows:

1. The app reads the bundled English markdown source files.
2. Text segments are translated using Apple's Translation framework. If the Translation framework does not support your language, the app falls back to on-device FoundationModels.
3. Translated markdown is cached locally so subsequent visits load instantly.
4. The translated markdown is converted to HTML on-device and displayed in the docs viewer.

After all documentation pages have been translated in the background, the app automatically uploads the translated markdown files to the [meshtastic/translations](https://github.com/meshtastic/translations) repository. This allows the community to review and improve machine-generated translations.

> **Tip — English users** If your device language is English, no translation occurs and the bundled English documentation is displayed directly.

## How to Contribute UI Translations

If you would like to update the translations for an existing locale or add a new language, follow these steps:

1. Fork the [Meshtastic-Apple repository](https://github.com/meshtastic/Meshtastic-Apple/tree/main) to your GitHub account.
2. Clone the project and open `Meshtastic.xcworkspace` in Xcode.
3. Select the `Localizable.xcstrings` file in the project navigator.
4. Follow the [steps for adding or updating translations](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) in Apple's documentation.
5. Create a pull request on the project with your changes.

Your contribution will be reviewed, and upon approval, your translation will be included in the next release of the Meshtastic Apple app.

> **Tip — New language?** If you are adding a language not yet present in the project, open the Xcode project settings, go to **Info → Localizations**, and add the new locale before editing `Localizable.xcstrings`.

Thank you for helping expand the reach of Meshtastic!
