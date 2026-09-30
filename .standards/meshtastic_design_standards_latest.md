<!-- DO NOT EDIT — This file is auto-generated from https://github.com/meshtastic/design -->
<!-- To make changes, open a PR against meshtastic/design and they will be mirrored here automatically. -->

# Meshtastic Client Design Standards (v1.5)

**Status:** Implementation Guide  
**Primary Audience:** Client Developers, Documentation Authors & UI Agents  
**Core Goal:** Cross-platform alignment prioritizing accessibility, native OS familiarity, consistent theme execution, and clear documentation.

---

## 1. Node Identity: The Circle Standard
Every node must be represented by a **Circular Identifier**. This follows the universal design convention for "contacts" in modern messaging apps.

* **Messaging View:**
    * **Others:** Display the circular avatar (initials or emoji) to the left of their message bubble, following the pattern of iMessage or Signal.
    * **Self:** Do not display an avatar for your own messages; use right-side bubble alignment to indicate the sender.
* **List Views:**
    * Use a circle with the node's computed color or emoji.
    * The node's color must **not** be used as a color-wash or background for the entire list item row. Rows must remain a neutral background to ensure maximum text legibility and high contrast.

---

## 2. Light & Dark Mode Standards
Clients must provide full, uncompromising support for both Light and Dark themes. Screens must be one or the other—never a hybrid of both.

* **Mode Consistency:**
    * **Light Mode:** High-contrast dark text on white or light-gray backgrounds.
    * **Dark Mode:** High-contrast light text on deep charcoal or pure black backgrounds.
* **Contrast Compliance:** Both modes must maintain a minimum **4.5:1 contrast ratio** (WCAG AA). 
* **Seamless Transition:** All UI elements (cards, icons, toggles) must flip their color logic entirely when the system mode changes.

---

## 3. Dynamic Layout & Conditional Visibility
* **Enabled-Only Settings:** Only show configuration options or status fields for modules/features currently enabled on the device.
* **Null Data Suppression:** If data is unavailable (e.g., no GPS lock or 0% battery), hide the field entirely from the list view. Avoid "N/A" or "0" placeholders.

---

## 4. Iconography & Descriptive Text
* **Labeled Navigation:** Every icon in the bottom navigation bar or sidebar **must** be accompanied by a bold text label to ensure clarity.
* **Icon-Text Redundancy:** Status indicators (Battery, Signal) should include text (e.g., `[Icon] 88%`).
* **Tooltips:** Desktop and Web clients must provide hover tooltips for all icon-only buttons.

---

## 5. Vision-Centric Design & Native Patterns
* **Typography:** Default body font size is **16px**. The application must support **Dynamic Type** scaling (up to 200%) without clipping text or breaking the layout.
* **Touch Targets:** Minimum **44x44 pixels** for all interactive elements to accommodate varying levels of motor precision.
* **Native Feel:** Follow iOS (HIG) and Android (Material Design) conventions for standard components like headers, chat bubbles, and tab bars.

---

## 6. Information Architecture
* **Plain Language:** Use subtext to explain technical settings in simple, non-technical terms (e.g., "Hop Limit: The number of times a message will be repeated by other nodes in the mesh").

---

## 7. Color Palette

All Meshtastic clients must use the official brand color palette defined below. The palette is derived from the two brand colors — **Primary `#2C2D3C`** and **Accent `#67EA94`** — and provides a complete system for building accessible UIs in both light and dark modes.

A visual reference is available at [color-palette.svg](color-palette.svg).

### 7.1 Brand Colors

| Role | Hex | RGB |
|------|-----|-----|
| **Primary** (Foreground) | `#2C2D3C` | `44 45 60` |
| **Accent** (Secondary/Highlight) | `#67EA94` | `103 234 148` |

### 7.2 Neutral Scale (derived from Primary)

Use these for backgrounds, surfaces, text, borders, and dividers.

| Name | Hex | RGB | Light Mode Usage | Dark Mode Usage |
|------|-----|-----|------------------|-----------------|
| Neutral 950 | `#0F1017` | `15 16 23` | — | Darkest background (OLED) |
| Neutral 900 | `#1A1B26` | `26 27 38` | — | Default background |
| Neutral 800 | `#2C2D3C` | `44 45 60` | Primary text | Surface / elevated card |
| Neutral 700 | `#3D3E50` | `61 62 80` | — | Elevated surface |
| Neutral 600 | `#555668` | `85 86 104` | — | Secondary text |
| Neutral 500 | `#6E7082` | `110 112 130` | Placeholder text | Placeholder text |
| Neutral 400 | `#9496A6` | `148 150 166` | Disabled / tertiary text | Disabled / tertiary text |
| Neutral 300 | `#B8BAC8` | `184 186 200` | Borders | — |
| Neutral 200 | `#D5D6E0` | `213 214 224` | Dividers | — |
| Neutral 100 | `#ECEDF3` | `236 237 243` | Surface / card | — |
| Neutral 50 | `#F5F6FA` | `245 246 250` | Default background | — |

### 7.3 Neutral Variant Scale

A slightly more chromatic version of the Neutral scale. Used for outlines, surface variants, and elements requiring subtle visual separation from plain neutral backgrounds.

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Neutral Variant 900 | `#1D1E2B` | `29 30 43` | — |
| Neutral Variant 800 | `#303245` | `48 50 69` | Dark mode outlineVariant |
| Neutral Variant 700 | `#444660` | `68 70 96` | Dark mode outline |
| Neutral Variant 600 | `#5C5E78` | `92 94 120` | Light outline |
| Neutral Variant 500 | `#767892` | `118 120 146` | Light outlineVariant |
| Neutral Variant 400 | `#9698B0` | `150 152 176` | — |
| Neutral Variant 300 | `#BDBFCF` | `189 191 207` | — |
| Neutral Variant 200 | `#DADBE7` | `218 219 231` | Light surfaceVariant |
| Neutral Variant 100 | `#EDEEF6` | `237 238 246` | — |
| Neutral Variant 50 | `#F6F7FC` | `246 247 252` | — |

### 7.4 Green Scale (derived from Accent)

Use these for interactive elements, highlights, and success states. Extended to a full tonal range for Material 3 compatibility.

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Green 950 | `#002E13` | `0 46 19` | Darkest green (onPrimaryContainer dark) |
| Green 900 | `#003D1A` | `0 61 26` | Very dark green |
| Green 800 | `#005C2E` | `0 92 46` | Dark green |
| Green 700 | `#2D8F52` | `45 143 82` | **Theme Primary** — buttons in light mode |
| Green 600 | `#3FB86D` | `63 184 109` | Green text on light backgrounds, success |
| Green 500 | `#67EA94` | `103 234 148` | **Brand accent** — dark-mode primary |
| Green 400 | `#8FF0B2` | `143 240 178` | Hover / active accent |
| Green 300 | `#B5F5CE` | `181 245 206` | Light highlight, primaryContainer light |
| Green 200 | `#CCFADD` | `204 250 221` | — |
| Green 100 | `#E5FCEE` | `229 252 238` | Success tint background |
| Green 50 | `#F0FEF5` | `240 254 245` | Lightest green tint |

### 7.5 Accent Blue Scale (Tertiary)

Used for tertiary/info elements and secondary call-to-action. The key color is `#2855A8`.

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Blue 950 | `#001849` | `0 24 73` | Darkest blue |
| Blue 900 | `#002366` | `0 35 102` | onTertiaryContainer dark |
| Blue 800 | `#1A3F8C` | `26 63 140` | Deep blue |
| Blue 700 | `#2855A8` | `40 85 168` | **Theme Accent** — tertiary light mode |
| Blue 600 | `#5C6BC0` | `92 107 192` | Info indicators; **Link color in light mode** |
| Blue 500 | `#7B8AD0` | `123 138 208` | Medium blue |
| Blue 400 | `#9BA8E0` | `155 168 224` | **Link color in dark mode** — hyperlinks, clickable URLs |
| Blue 300 | `#B0BFF0` | `176 191 240` | Dark-mode tertiary |
| Blue 200 | `#D0D8F5` | `208 216 245` | — |
| Blue 100 | `#E0E3F8` | `224 227 248` | Link tint background |
| Blue 50 | `#E8EAF6` | `232 234 246` | Info tint background |

### 7.6 Error Scale

Extended error palette for complete theme support.

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Error 900 | `#410002` | `65 0 2` | onErrorContainer light |
| Error 800 | `#690005` | `105 0 5` | onError dark |
| Error 700 | `#93000A` | `147 0 10` | errorContainer dark |
| Error 600 | `#BA1A1A` | `186 26 26` | **Error light mode** (WCAG-safe on white) |
| Error 500 | `#E05252` | `224 82 82` | Brand error — indicators, non-text usage |
| Error 400 | `#FF897D` | `255 137 125` | — |
| Error 300 | `#FFB4AB` | `255 180 171` | Error dark mode text |
| Error 200 | `#FFDAD6` | `255 218 214` | — |
| Error 100 | `#FDEAEA` | `253 234 234` | Error tint background, errorContainer light |

### 7.7 Semantic Colors

Use these for status indicators, alerts, and feedback.

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Link | `#5C6BC0` light / `#9BA8E0` dark | `92 107 192` / `155 168 224` | Hyperlinks, clickable URLs (Blue 600 light, Blue 400 dark) |
| Link Light | `#E0E3F8` | `224 227 248` | Link tint background |
| Info | `#5C6BC0` | `92 107 192` | Informational indicators |
| Info Light | `#E8EAF6` | `232 234 246` | Info tint background |
| Warning | `#E8A33E` | `232 163 62` | Caution / attention states |
| Warning Light | `#FFF3E0` | `255 243 224` | Warning tint background |
| Error | `#E05252` | `224 82 82` | Errors, destructive actions |
| Error Light | `#FDEAEA` | `253 234 234` | Error tint background |
| Success | `#3FB86D` | `63 184 109` | Success states, confirmations (Green 600) |
| Success Light | `#E5FCEE` | `229 252 238` | Success tint background |

---

## 8. Material 3 Theme Mapping

This section maps the Meshtastic palette to Material 3 color roles. M3 requires 5 tonal palettes (Primary, Secondary, Tertiary, Neutral, Neutral Variant) mapped to specific color roles for light and dark schemes.

### 8.1 Key Color Sources

| M3 Palette | Meshtastic Source | Key Color |
|------------|-------------------|-----------|
| Primary | Green Scale | `#2D8F52` (Green 700) |
| Secondary | Neutral Scale | `#555668` (Neutral 600) |
| Tertiary | Blue Scale | `#2855A8` (Blue 700) |
| Neutral | Neutral Scale | `#2C2D3C` (Neutral 800) |
| Neutral Variant | Neutral Variant Scale | `#303245` (NV 800) |
| Error | Error Scale | `#BA1A1A` (Error 600) |

### 8.2 Light Scheme Role Mapping

| M3 Role | Hex | Source |
|---------|-----|--------|
| `primary` | `#2D8F52` | Green 700 |
| `onPrimary` | `#FFFFFF` | White |
| `primaryContainer` | `#B5F5CE` | Green 300 |
| `onPrimaryContainer` | `#002E13` | Green 950 |
| `secondary` | `#555668` | Neutral 600 |
| `onSecondary` | `#FFFFFF` | White |
| `secondaryContainer` | `#D5D6E0` | Neutral 200 |
| `onSecondaryContainer` | `#2C2D3C` | Neutral 800 |
| `tertiary` | `#2855A8` | Blue 700 |
| `onTertiary` | `#FFFFFF` | White |
| `tertiaryContainer` | `#E8EAF6` | Blue 50 |
| `onTertiaryContainer` | `#001849` | Blue 950 |
| `error` | `#BA1A1A` | Error 600 |
| `onError` | `#FFFFFF` | White |
| `errorContainer` | `#FDEAEA` | Error 100 |
| `onErrorContainer` | `#410002` | Error 900 |
| `background` | `#F5F6FA` | Neutral 50 |
| `onBackground` | `#2C2D3C` | Neutral 800 |
| `surface` | `#F5F6FA` | Neutral 50 |
| `onSurface` | `#2C2D3C` | Neutral 800 |
| `surfaceVariant` | `#DADBE7` | NV 200 |
| `onSurfaceVariant` | `#5C5E78` | NV 600 |
| `outline` | `#767892` | NV 500 |
| `outlineVariant` | `#BDBFCF` | NV 300 |
| `inverseSurface` | `#3D3E50` | Neutral 700 |
| `inverseOnSurface` | `#ECEDF3` | Neutral 100 |
| `inversePrimary` | `#67EA94` | Green 500 |
| `surfaceTint` | `#2D8F52` | Green 700 (= primary) |
| `scrim` | `#000000` | Black |
| `surfaceDim` | `#D5D6E0` | Neutral 200 |
| `surfaceBright` | `#F5F6FA` | Neutral 50 |
| `surfaceContainerLowest` | `#FFFFFF` | White |
| `surfaceContainerLow` | `#F5F6FA` | Neutral 50 |
| `surfaceContainer` | `#ECEDF3` | Neutral 100 |
| `surfaceContainerHigh` | `#E0E1EB` | Interpolated 100↔200 |
| `surfaceContainerHighest` | `#D5D6E0` | Neutral 200 |

### 8.3 Dark Scheme Role Mapping

| M3 Role | Hex | Source |
|---------|-----|--------|
| `primary` | `#67EA94` | Green 500 |
| `onPrimary` | `#0F1017` | Neutral 950 |
| `primaryContainer` | `#2D8F52` | Green 700 |
| `onPrimaryContainer` | `#B5F5CE` | Green 300 |
| `secondary` | `#B8BAC8` | Neutral 300 |
| `onSecondary` | `#1A1B26` | Neutral 900 |
| `secondaryContainer` | `#3D3E50` | Neutral 700 |
| `onSecondaryContainer` | `#D5D6E0` | Neutral 200 |
| `tertiary` | `#B0BFF0` | Blue 300 |
| `onTertiary` | `#001849` | Blue 950 |
| `tertiaryContainer` | `#2855A8` | Blue 700 |
| `onTertiaryContainer` | `#E8EAF6` | Blue 50 |
| `error` | `#FFB4AB` | Error 300 |
| `onError` | `#690005` | Error 800 |
| `errorContainer` | `#93000A` | Error 700 |
| `onErrorContainer` | `#FDEAEA` | Error 100 |
| `background` | `#1A1B26` | Neutral 900 |
| `onBackground` | `#ECEDF3` | Neutral 100 |
| `surface` | `#1A1B26` | Neutral 900 |
| `onSurface` | `#ECEDF3` | Neutral 100 |
| `surfaceVariant` | `#444660` | NV 700 |
| `onSurfaceVariant` | `#BDBFCF` | NV 300 |
| `outline` | `#767892` | NV 500 |
| `outlineVariant` | `#444660` | NV 700 |
| `inverseSurface` | `#ECEDF3` | Neutral 100 |
| `inverseOnSurface` | `#2C2D3C` | Neutral 800 |
| `inversePrimary` | `#2D8F52` | Green 700 |
| `surfaceTint` | `#67EA94` | Green 500 (= primary) |
| `scrim` | `#000000` | Black |
| `surfaceDim` | `#0F1017` | Neutral 950 |
| `surfaceBright` | `#3D3E50` | Neutral 700 |
| `surfaceContainerLowest` | `#0F1017` | Neutral 950 |
| `surfaceContainerLow` | `#1A1B26` | Neutral 900 |
| `surfaceContainer` | `#242533` | Interpolated 900↔800 |
| `surfaceContainerHigh` | `#2C2D3C` | Neutral 800 |
| `surfaceContainerHighest` | `#3D3E50` | Neutral 700 |

### 8.4 Fixed Colors

Fixed colors remain constant regardless of light/dark mode. Use for elements that must maintain visual identity across themes.

| M3 Role | Hex | Source |
|---------|-----|--------|
| `primaryFixed` | `#B5F5CE` | Green 300 |
| `primaryFixedDim` | `#8FF0B2` | Green 400 |
| `onPrimaryFixed` | `#002E13` | Green 950 |
| `onPrimaryFixedVariant` | `#2D8F52` | Green 700 |
| `secondaryFixed` | `#D5D6E0` | Neutral 200 |
| `secondaryFixedDim` | `#B8BAC8` | Neutral 300 |
| `onSecondaryFixed` | `#1A1B26` | Neutral 900 |
| `onSecondaryFixedVariant` | `#555668` | Neutral 600 |
| `tertiaryFixed` | `#E0E3F8` | Blue 100 |
| `tertiaryFixedDim` | `#B0BFF0` | Blue 300 |
| `onTertiaryFixed` | `#001849` | Blue 950 |
| `onTertiaryFixedVariant` | `#2855A8` | Blue 700 |

### 8.5 Dynamic Color (Android 12+)

On Android 12 and above, the system provides dynamic color palettes derived from the user's wallpaper. When dynamic color is available, clients **should** use it as the default to respect user personalization. The static palette above serves as the fallback when dynamic color is unavailable or disabled.

---

## 9. Color Usage Rules

* **Accent on white:** Never use the raw accent `#67EA94` for text on white or light backgrounds — it does not meet WCAG AA contrast. Use `Green 600` (`#3FB86D`) or `Green 700` (`#2D8F52`) instead.
* **Semantic consistency:** Use Info/Warning/Error/Success colors consistently across all views. Do not repurpose semantic colors for decorative use.
* **Node colors:** Individual node-computed colors are separate from this palette. They may use any hue but must still meet the 4.5:1 contrast ratio against their background.
* **Dark mode mapping:** Swap light-mode backgrounds for their dark-mode counterparts from the neutral scale. Do not simply invert colors.
* **Message text legibility:** Message bubble text must use `onSurface` (or equivalent high-contrast token) — never the node's computed foreground color, which may fail contrast when alpha-blended over surfaces.
* **Error accessibility:** Use Error 600 (`#BA1A1A`) for error text in light mode. The brand error `#E05252` (Error 500) is reserved for non-text indicators, containers, and decorative elements where 3:1 contrast (SC 1.4.11) is sufficient.

---

## 10. Units, Measurement & Locale

Meshtastic devices transmit all telemetry and position data in **metric SI units**. The client must never expose raw metric values to users who expect imperial or other regional units. Instead, the client must delegate unit conversion and formatting to the **operating system's locale and measurement system APIs**, which handle this automatically based on the user's device settings.

Users must never need to manually convert units — the client adapts automatically.

### 10.1 Device Data Is Always Metric

All data received from a Meshtastic device over BLE, TCP, or serial arrives in the canonical metric units defined by the protobuf schema. These units must be preserved exactly as-is for internal storage and retransmission. Conversion to display units happens **only at the presentation layer**, immediately before rendering to the screen.

| Quantity | Device Unit | Notes |
|----------|------------|-------|
| Altitude | meters (m) | Integer, from GPS |
| Distance (sensor) | millimeters (mm) | Environment telemetry |
| Ground Speed | km/h | Position telemetry |
| Wind Speed | m/s | Environment telemetry |
| Wind Gust | m/s | Environment telemetry |
| Temperature | °C | Environment & soil telemetry |
| Barometric Pressure | hPa | Environment telemetry |
| Rainfall (1 h / 24 h) | mm | Environment telemetry |
| Weight | kg | Environment telemetry |
| Heading / Bearing | degrees (°) | 0–360, from GPS |
| Radiation | µR/hr | Environment telemetry |
| Coordinates | degrees × 10⁷ | Signed 32-bit integer |

> **Key point:** The phone or desktop client never defines what unit to display. It tells the OS "this value is X meters" and the OS returns "Y feet" or "X meters" depending on the user's settings.

### 10.2 Let the OS Handle Conversion

Every major platform provides measurement formatting APIs that automatically convert and format values based on the user's locale and measurement system preference. Clients **must** use these APIs rather than implementing manual conversion logic.

| Platform | API | Behavior |
|----------|-----|----------|
| **Apple (Swift)** | `Measurement` + `MeasurementFormatter` or `.formatted(.measurement(...))` | Automatically converts m→ft, °C→°F, km/h→mph, etc. based on device locale |
| **Android (Kotlin)** | `MeasureFormat` / `LocaleData.getMeasurementSystem()` | Respects system locale for unit selection and number formatting |
| **Web (JS/TS)** | `Intl.NumberFormat` with `style: 'unit'` | Uses browser locale for unit display and number formatting |

**How it works:**
1. Wrap the raw device value in the platform's measurement type, specifying the **source unit from the device** (e.g., meters, Celsius, km/h).
2. Pass it to the formatter — the OS reads the user's locale/measurement-system setting and outputs the correct display unit and formatted string.
3. Display the result. No manual `if metric … else imperial` branching is needed for most quantities.

### 10.3 Display Conversion Table

This table shows what the user sees after OS-level conversion. Clients do not implement these conversions manually — the OS APIs listed in Section 10.2 produce these results automatically.

| Quantity | Metric Locale | Imperial Locale |
|----------|--------------|-----------------|
| Large distance | km | mi |
| Small distance | m | ft |
| Altitude | m | ft |
| Ground speed | km/h | mph |
| Wind speed | m/s or km/h | mph |
| Temperature | °C | °F |
| Rainfall | mm | in |
| Weight | kg | lbs |
| Sensor distance | mm | in |

**Auto-scaling:** For distances, use the platform's "natural scale" option (e.g., `.naturalScale` on Apple, `MeasureFormat.FormatWidth.SHORT` on Android). This lets the OS pick the most readable magnitude — 500 m stays as "500 m", 2,500 m becomes "2.5 km" or "1.6 mi".

### 10.4 Universal Units (No Conversion)

Some units are internationally standardized and must be displayed as-is regardless of locale:

| Quantity | Display Unit | Reason |
|----------|-------------|--------|
| Barometric Pressure | hPa | Standard meteorological unit worldwide |
| Heading / Bearing | ° (degrees) | Universal navigation convention |
| Radiation | µR/hr | Standard dosimetry unit |
| Coordinates | decimal degrees | Universal geographic convention |
| Percentage values (humidity, battery, soil moisture) | % | Universal |

### 10.5 Implementation Rules

1. **Construct measurements with the correct source unit.** Always specify the unit the device actually sends. `CLLocation.speed` returns m/s — wrap it as `metersPerSecond`, not `kilometersPerHour`. Protobuf `groundSpeed` is km/h — wrap it as `kilometersPerHour`. Getting the source unit wrong produces silently incorrect display values.

2. **Never force-unwrap locale queries.** Locale keys (e.g., temperature-unit preference) may return nil on some OS versions or device configurations. Always provide a sensible default — Celsius for temperature, metric for distances.

3. **Charts and graphs must also respect locale.** Axis labels, tooltips, annotations, and legend values must display in the user's preferred unit, not the internal metric unit.

4. **Number formatting must be locale-aware.** Use locale-sensitive number formatters for decimal separators (`.` vs `,`), digit grouping (`,` vs `.` vs ` `), and precision. Never hardcode decimal separators or thousand separators.

5. **Do not hardcode unit label strings.** Instead of string-concatenating `"kg"` or `"mm"`, use the platform's measurement formatter which returns the correct localized unit symbol automatically.

### 10.6 Date, Time & Calendar

* Always use the OS locale for date and time formatting.
* Use relative time (e.g., "5 min ago") for recency indicators where appropriate.
* Honor the user's 12-hour / 24-hour clock preference — never hardcode one or the other.
* Respect the user's calendar system (Gregorian, Buddhist, Japanese, etc.).

---

## 11. Documentation

Documentation is part of the product. A setting that isn't documented, or that is explained in language the reader can't parse, fails the same goal as a button with no label. This section covers the documentation site, the written material in this repository, and the text inside the clients.

This is what new and edited writing follows. Mechanics owned by the site's build tooling are out of scope, such as front matter keys and component import paths.

The section holds itself to its own rules, with one exception. Ruling a word out means naming it, so currently, simply, please, and e.g. appear here as examples rather than as usage.

### 11.1 Where client documentation lives

Android and Apple app documentation, and the screenshots it references, is written in the client repositories and synced into the documentation site automatically.

| Synced path | Written in |
|-------------|-----------|
| `docs/software/android/`, `static/img/android/docs/` | [meshtastic/Meshtastic-Android](https://github.com/meshtastic/Meshtastic-Android) |
| `docs/software/apple/`, `static/img/apple/` | [meshtastic/Meshtastic-Apple](https://github.com/meshtastic/Meshtastic-Apple) |

Open pull requests against the client repository, not the documentation repository. Editing these paths in the docs repo is reverted by the next sync, and a CI guard fails pull requests that touch them. The guard covers renames and deletions as well as edits. Moving a generated file out of a synced path leaves the next sync to recreate the original.

The sync runs weekly and takes each client's latest release rather than its default branch. A merged client change reaches the site once it ships in a release. The maintainer override label exists for reverts and for sync-script changes that have to land with their output, not for patching generated documentation by hand.

When generated client documentation is wrong, fix it in the client repository. A correction applied downstream is discarded within the week.

Some client repositories keep their own documentation style guide covering the same prose. Where one exists, the two are kept in agreement rather than one overriding the other.

### 11.2 Voice

Write for a reader who is competent but new to this topic. Readers range from someone who bought a preassembled node to a developer reading protobuf definitions.

Address the reader as you. Their node, their settings, and their region are theirs, so write "your node" and "your region" rather than working around the pronoun.

Don't open a section or a paragraph with "You". Lead with the subject, which is the system, the value, or the action, and let the pronoun arrive where it belongs. Compare "The app displays distances in the units your device is set to use" with "You see distances in your device's units". Both carry the same information, but the first reads as documentation and the second as instruction.

Use the imperative for the step itself: "Flash the firmware", "Select **Save**". A step needs no pronoun, though a condition attached to one still takes it: "If your region has a duty-cycle limit, select a lower preset".

Describe what the software does in the third person, with the node, client, or firmware as the subject. "The node repeats the message", not "your node repeats your messages". What the firmware does is not the reader's doing, and reference material explains it regardless of who is reading.

Don't use "the user" to mean the reader. Many readers are operators configuring nodes for other people. "The user must set the region" leaves them unsure who is meant, and it pushes the sentence into the passive.

Active voice, one idea per sentence. Refer to the project as Meshtastic, not "we". Keep the register plain: no marketing language and no exclamation points.

Contractions are house voice. Write you'll, doesn't, and it's; the full forms read stiff and put distance between the page and the reader. Warnings are the exception: there, write do not and cannot. A negative contraction is the easiest thing on a page to skim past. Misreading one costs a wiped configuration, or a node that has to be recovered over serial.

Write in the timeless present. The node sends a position, not will send: the page describes how the system behaves, and that stays true whenever it is read. Keep will for something genuinely later than the sentence, such as a file that is removed on the next sync.

Don't date the page from inside it. Currently, now, at this time, soon, new, and as of this writing describe the moment of writing rather than the system. The page outlives that moment. A sentence carrying one of them is wrong within a release or two and nothing flags it. Where a fact really is bounded by a version, name the version, as covered in 11.14.

Don't describe a feature that hasn't shipped. A page announcing work in progress generates support questions about behavior no one can reproduce.

Drop simply, just, easy, easily, quickly, obviously, and of course wherever they characterize how hard or how fast the reader's task is. Telling a stuck reader that a step is easy only tells them they are the problem. The same words are ordinary filler elsewhere, as in "the beacon simply goes out on the primary channel". That sentence describes behavior rather than the reader. Delete the word for tightness, but it isn't the defect this rule is about.

Leave out please. A procedure asks for a step because the task requires it, and the politeness reads as an apology for the instruction. Leave out scare quotes, which ask the reader to infer a meaning the sentence declines to state. Where a term is wrong or approximate, use the right one.

Jokes and pop-culture references date faster than the rest of the page. They are also the first thing to fail for a reader who learned English somewhere else.

Don't give hardware or software intent. A node doesn't want, try, or think.

Voice stays the same across the site; tone answers the reader's situation. A feature overview and a troubleshooting page are recognizably the same writer. Someone on the troubleshooting page has already lost an hour, so that page carries the calmest, most concrete writing on the site. Clear beats entertaining everywhere.

### 11.3 Plain language

Jargon is necessary here, but introduce it rather than assume it. Define a technical term the first time it appears on a page, link to its reference page, or both. Expand acronyms on first use per page, as in pre-shared key (PSK). Readers arrive from search results, so first use is per page and not per site.

Explain the consequence and not only the definition. Someone configuring hop limit needs to know what changes if they get it wrong.

Requirement words carry exact weight, because readers act on the difference between them. Must is an obligation and must not a prohibition. Should is a recommendation that leaves a real alternative, can states a capability, and may states permission. Don't use shall, which is ambiguous outside legal drafting and translates badly. Don't soften an obligation to should because the sentence sounds gentler, and don't harden a recommendation to must because it sounds firmer.

Write for example and such as rather than e.g., and that is rather than i.e. The two abbreviations are routinely swapped for each other, and they read poorly aloud. A reader translating the page has to recognize them first. Inside a table cell or parentheses, where space is tight, e.g. is acceptable.

Keep wording literal and inclusive: use allowlist and blocklist for the mechanism rather than the older color-coded pair. Use singular they for a reader or an operator whose gender isn't known, which is also the shortest way to write the sentence. Don't borrow a disability as a figure of speech, so final check rather than sanity check. Don't reach for violent metaphor either: the client stops responding, it doesn't hang or die. Literal wording reads as neutral description to every reader and survives translation, which figurative language does not.

Use the serial comma in a list of three or more, as in Android, Apple, and Web. Without it the last two items can read as a pair rather than as separate entries.

Use the same glosses in the documentation and in the matching in-app subtext, so both teach the concept in the same words.

| Term | Gloss |
|------|-------|
| Node | A device running Meshtastic firmware that takes part in the mesh |
| Mesh | The set of nodes that relay each other's messages |
| Hop limit | The number of times a message is repeated by other nodes in the mesh |
| Channel | A named, encrypted group that messages are sent to |
| Primary channel | The channel used for a node's default traffic and its name in the mesh |
| Pre-shared key | The key that encrypts a channel; anyone holding it can read that channel |
| Modem preset | The tradeoff between range and speed for LoRa transmissions |
| Region | The regulatory setting that determines legal frequencies and power for a location |
| Telemetry | Periodic sensor and status readings a node reports, such as battery or temperature |
| Traceroute | A request that reports the path a message took through the mesh |
| MQTT | An internet bridge that can extend a mesh beyond radio range |

### 11.4 Terminology

Inconsistent terminology is the most common source of cross-platform confusion. A concept keeps the same name in the firmware, every client, and the documentation.

| Concept | Use | Not |
|---------|-----|-----|
| A device on the mesh | node | peer, unit, station, mote |
| The hardware in someone's hand | node, or device | radio, which means the LoRa transceiver itself |
| Software that connects to a node | client, or the specific one: Android, Apple, Web, CLI | app, except for one specific mobile client |
| Software running on the node | firmware | OS, software |
| The Linux native daemon | meshtasticd | Linux client, daemon build |
| A one-to-one message | direct message | private message, whisper |
| A message to a channel | broadcast | group message, public message |
| A LoRa speed and range profile | modem preset; Long Fast in prose, `LONG_FAST` in code | mode, bandwidth setting |
| The regulatory locale setting | region | country, frequency, band |
| Wireless pairing to a client | Bluetooth; `BLE` is fine in developer docs | BT |
| Version identifiers | firmware version and app version, kept distinct | version, release |

Use the on-screen label exactly as it appears when documenting a control, in the same capitalization: "Select **Save**". If a label is wrong or unclear, fix the UI rather than paraphrasing it in the docs. Use one name per concept per page; repetition is correct in technical writing.

Protobuf fields keep their schema form, so write `hop_limit` for the field and Hop Limit for the control, and don't silently convert between them. Leave mesh, node, and channel lowercase in prose. The compounds app documentation and app version are established names and stay as they are; the rule against app covers naming the client itself.

Spell words the American way: color, behavior, gray, meter, organize, honors. Meshtastic's source English is American. A corpus carrying both forms splits search results for a reader who types the other one. It also produces two translation memory entries in Crowdin for a single word. This governs prose; quoted UI labels, code, and a vendor's own product name keep whatever spelling they already have.

Product and technology names take their official casing, because mixed casing across pages makes search and translation unreliable.

| Use | Not |
|-----|-----|
| LoRa | Lora, LORA, lora |
| LoRaWAN | Lorawan, LoraWAN |
| nRF52840 | NRF52840, nrf52840 |
| ESP32-S3 | ESP32S3, esp32s3 |
| Wi-Fi | WiFi, wifi, WIFI |
| Node-RED | Node-red, node-red |
| Bluetooth | BT, bluetooth |
| MQTT | mqtt, Mqtt |
| meshtasticd | Meshtasticd, MeshtasticD |
| GPS | gps, Gps |

Wi-Fi takes the dash, matching the Wi-Fi Alliance and the Android client's word list.

Apply casing to prose only. URLs, file paths, code identifiers, protobuf field names, enum values, and configuration keys are literal strings and stay as they are. So do a vendor's own product names, even where they disagree with the table.

### 11.5 Page structure

Readers arrive from search and scan before they read, so the opening has to let them confirm they are in the right place.

State the purpose in the first sentence after the title, without preamble and without restating the title. Put prerequisites before the steps rather than partway through: required hardware, firmware version, and prior configuration go up front.

One H1 per page, from the title or front matter. Don't skip heading levels, since level conveys structure to screen readers and to the table of contents. Use sentence case. Keep headings descriptive and unique within a page, and avoid "Notes" and "Miscellaneous".

Keep sentences to roughly 25 words and one idea, and paragraphs to about five sentences and one topic; break anything longer into lists or tables. A one-sentence paragraph is fine where the point stands alone. Front-load: the rule comes before its exceptions, and the main point before the qualification. A reader who stops halfway should still have the part that matters.

Prefer a table wherever content has a repeating shape, such as settings, values, platform differences, or unit mappings. Close with next steps where a task continues elsewhere.

Give each fact one home and link to it. Content repeated across pages drifts.

Don't point at other parts of a page with above and below. A screen reader linearizes the page, a phone reflows it, and a search result can drop a reader into the middle. Neither word reliably describes where anything sits. Write earlier or the following, name the section, or link to it. The literal sense is unaffected: a signal below the noise floor is still below the noise floor.

Settings and configuration pages follow a consistent shape. Open with what the group controls, then an alphabetized table of settings with acceptable values and defaults. A short description of each setting follows, then details and examples where they're needed. A settings page documents settings; where hardware or prior setup is required, state the requirement and link to it rather than explaining it inline.

### 11.6 Instructions

Number sequential steps and keep unordered lists for options that have no order. One action per step; if a step contains "and then", split it.

State the location before the action, as in "In **Settings > Radio Configuration**, select **Region**". A reader who can't find the control can't perform the step. Say where the procedure starts rather than assuming a screen.

State the expected result for any step whose outcome isn't immediately visible, such as a reboot or a reconnect. Say roughly how long it takes. End a procedure by saying how to confirm it worked, naming the indicator to look for. Where a step commonly fails, give the likely cause and the recovery.

Flag anything that erases configuration, regenerates keys, or breaks existing pairings in the step before it happens, not after.

### 11.7 Cross-platform coverage

Documentation is where cross-platform inconsistency becomes visible, and it shouldn't paper over it.

Cover every supported client for a feature, or say which clients support it. Silent omission reads as undocumented and generates duplicate issues. Name gaps plainly: "Not available on the Web client" is actionable, a missing tab isn't.

Use platform tabs for per-client instructions, and keep the platform order the same on every page. List the CLI first where it exists, since it's the most stable reference. Give every tab a heading one level deeper than the section that contains it, so tabs inside an H2 take H3 headings. Jumping to H4 skips a level and breaks the outline, and tab blocks copied between pages are where that happens. Tab content with no heading isn't navigable by screen reader at all.

Keep tabs in sync when a procedure changes. A stale tab is worse than a missing one because it looks authoritative.

Prefer select over tap or click in shared prose, keeping tap for mobile-specific content and click for desktop. Name a control rather than describing where it sits, since position breaks across platforms, window sizes, and right-to-left layouts. Note where clients diverge because of firmware version rather than platform.

### 11.8 Code and CLI examples

Tag the language on every fenced block, using `shell` for command-line examples rather than `bash`, `sh`, or `console`, so command blocks render the same everywhere.

Examples are copy-pasteable and complete: no omitted flags, no assumed earlier command, no `...` standing in for real syntax. Leave out the shell prompt so the command can be copied cleanly, and keep one command per line rather than chaining unrelated commands with `&&`.

Mark placeholders with angle brackets and uppercase, as in `<YOUR_CHANNEL_NAME>`, and say what each one means and where to get the value. Never publish real PSKs, API keys, MQTT credentials, node IDs, or personal coordinates, including expired or test ones; use obviously fake values.

Show expected output where that's how a reader verifies success, marked clearly as output. Keep protobuf field names verbatim from the schema, and state the version for any command whose syntax has changed between releases.

### 11.9 Screenshots, diagrams, and media

Screenshots go stale, can't be translated, can't be searched, and can't be read aloud. Use them to orient a reader, not as the only place information exists.

Put anything a reader might copy, search, or hear into text or a table. Setting names, values, and command syntax never live only inside an image.

Provide both light and dark variants of UI screenshots, and show the one matching the reader's theme. A light-only screenshot on a dark page breaks the mode consistency rule in section 2. Capture default themes and default configuration unless the screenshot exists to show a specific setting. Redact node names, real coordinates, map positions, keys, phone numbers, email addresses, and other people's nodes before publishing. Crop to the relevant region, and capture at native resolution or 2x rather than upscaling.

Use webp for screenshots and photos, which cuts page weight for readers on metered or slow connections, and keep SVG for diagrams and logos. Social preview images are PNG at 1200 x 630, since webp is unreliable for social cards. Give video embeds `preload="metadata"` or `preload="none"` so a page doesn't spend the reader's bandwidth before they press play. Store images in the site's shared image directory rather than beside the page, so they can be reused and audited.

Every image needs alt text, as covered in 11.10.

Diagrams use the palette in section 7 and stay legible in both light and dark mode. Don't rely on a light page background for contrast. Prefer Mermaid or SVG over raster: they stay sharp, diff cleanly in review, and their text stays selectable and translatable. Pair color with a label, shape, or pattern rather than carrying meaning by color alone.

### 11.10 Accessibility

The accessibility requirements in sections 2, 4, and 5 apply to written content as directly as they apply to UI.

Every image needs alt text describing what the image conveys, not the fact that it's an image; leave out "image of" and "screenshot of". Empty alt text is for genuinely decorative images, and it has to be written out explicitly. `![](/img/example.webp)` with no alt attribute is unlabeled rather than intentionally silent. Correct copied headings and tab labels instead of pasting them, since duplicated platform headings are a recurring source of wrong labels and mismatched tab values.

Link text describes its destination. Avoid "click here", "here", "this link", and "read more"; a bare URL is fine only when the URL itself is the information. Don't place two links with similar text next to each other, because they're indistinguishable in a screen reader's link list.

Tables need a real header row and no merged cells, and aren't for visual layout. Pair color-coded status with text, as the icon and text rule in section 4 requires. Name a control rather than describing it by position or appearance.

Keep heading order intact so assistive technology can build an accurate outline. Caption video and audio and summarize any instruction they give. Keep structure simple: deeply nested lists and multi-paragraph table cells are hard to navigate without sight.

### 11.11 Admonitions

Admonitions are the most overused feature in documentation, and overuse cancels them out. A page carrying five callouts effectively carries none, because readers learn within seconds to scan past the styling. Their value comes from being rare.

Default to none. Write the information as body text. Promote it only where a reader skimming the page would suffer a real consequence from missing it. A real consequence is lost configuration, an unrecoverable device, hours spent on a wrong assumption, or a breach of local radio regulations. Useful to know is not a consequence.

At most one admonition per H2 section. On a short page that means zero or one in total. A long reference page should rarely pass three or four, and never two in the same section. A page that seems to need more is misorganized, or its callouts are decorative. Both are fixed by rewriting the content rather than by adding another box.

| Type | Semantic color (7.7) | For |
|------|---------------------|-----|
| `note` | Info | Context that doesn't change the procedure |
| `info` | Info | Version requirements, scope limits, platform availability |
| `tip` | Success | An optional shortcut or better alternative |
| `warning` | Warning | Misconfiguration that degrades the mesh or blocks connectivity |
| `danger` | Error | Irreversible data loss, key regeneration, hardware damage, regulatory violation |

Two types turn up that aren't in this table. Docusaurus treats `caution` as a deprecated alias rendering as a warning, and `important` as an undocumented legacy alias rendering as info. The framework already fixes the mapping, so write `warning` and `info` directly. Change them as pages are touched; the copies frozen in `versioned_docs/` stay as they are, because a frozen snapshot is never edited.

These rules cover pages authored here. The synced client documentation in 11.1 is written for two renderers at once. Its source cannot use `:::` at all, and carries a blockquote form instead. The client repository's own guide governs that form, and whether it reaches the site as a callout depends on that repository's sync conversion.

Don't stack or nest them. Consecutive callouts read as a wall of boxes and get skipped together, so merge them or move the detail into body text. Required actions belong in the numbered procedure, never only inside a callout.

Don't open a page or a section with an admonition to emphasize prose. If something matters enough to lead with, it's the topic, and it belongs in the opening sentence where it will be read.

Don't use a callout for ordinary emphasis, to restate a step, or to hold content with no better home. Keep `danger` for irreversible or unlawful outcomes, and match severity honestly, because marking routine notes as warnings inflates the scale until real warnings stop registering.

When reviewing a page with several callouts, ask which of them could be body text rather than whether another is missing.

Bold is for UI labels and genuine emphasis, not whole sentences and not as a substitute for a heading. Code formatting is for field names, values, paths, and commands, not emphasis. Don't use capitals for emphasis.

### 11.12 Units, dates, and locale

Documentation follows the unit rules in section 10 rather than contradicting them.

State the canonical unit when describing a device value or protobuf field. Values arrive in metric SI units, and reference material has to say what the device sends. In user-facing prose give metric first with the imperial equivalent in parentheses, as in about 2 km (1.2 mi). Don't imply a client displays a fixed unit, since display units follow the reader's OS locale. Leave hPa, degrees, microroentgens per hour, and percentages unconverted.

Spell the month in prose: March 14, 2026, and not 03/14/26. The all-numeric forms swap day and month between American and European readers, and a date is worth more characters than the ambiguity costs. Keep ISO 8601 where the string is data rather than prose. That covers log excerpts, timestamp examples, file names, and the date stamps on specs and audits in this repository. State the time zone, or use UTC, wherever a timestamp appears.

Spell out zero through nine in prose and use numerals from 10 up. Numerals override that rule for any measurement or value carrying a unit, as in 3 dB and 915 MHz. They also override it for a value the reader types or selects, and for anything taking a percent sign. Identifiers keep their numerals too, such as a section number, a heading level, or a firmware version. Don't hardcode a locale's number formatting in examples, and note that separators are locale-dependent where it could confuse.

Range depends on terrain, antenna, and preset, so state the conditions with any distance figure or leave the figure out.

### 11.13 Translation

Documentation is translated through Crowdin, and client strings are localized separately. Source English has to be written so it can be translated without guesswork.

Keep sentences short and simple; long sentences with nested clauses compound translation errors. Avoid idiom, slang, humor, and cultural reference: out of the box and your mileage may vary don't survive translation. Describe the mechanism rather than reaching for metaphor.

Don't assemble sentences from fragments in UI strings, because a runtime concatenation can't be reordered for another language's grammar; use complete strings with named placeholders. Keep translatable text out of images, which aren't translated. Code, CLI commands, protobuf field names, enum values, and log output aren't translated either, so mark them with code formatting to make that clear.

Avoid directional wording that breaks in right-to-left layouts. Don't reuse one string in two grammatical contexts, since a word that works as both noun and verb in English usually needs two translations. Allow for expansion: translated strings often run 30 to 40 percent longer than English, and layouts have to take that without clipping.

Keep markdown structure plain. Inline HTML or JSX inside translated prose is a known build breaker. Translation round-trips corrupt tags: spaces appear inside closing tags, opening tags duplicate, and containers unbalance until the page fails to build.

### 11.14 Accuracy and versioning

Wrong documentation does more damage than missing documentation, because readers act on it.

The documentation is versioned. The current set describes the release in development, and each older line keeps a frozen snapshot. The version selector already tells a reader which release a page belongs to. Let it do that work.

A feature added in 2.8 appears in the 2.8 set and is absent from 2.7. That is the whole story, and "new in 2.8" on every such page says nothing while the entire set is new. The same holds for a setting that was removed, a default that changed, and a field that was renamed: each snapshot describes its own release.

Give a version inline only where the selector cannot express the fact. There are four such cases:

- The change landed in a patch release, so readers on an earlier patch of the same line do not have it.
- Older nodes on the mesh behave differently, such as a field that firmware 2.7 and earlier ignores. That is a fact about other people's devices, and no snapshot carries it.
- The requirement is a client app version rather than a firmware version, since the documentation is versioned by firmware.
- The behavior exists only in nightly builds and in no released build of the current line.

Write these in the sentence that needs them, not as a banner at the head of the page. Name the specific version, and keep firmware and app versions distinct.

Deprecation is the other version fact a snapshot cannot carry, because a removal that has not happened yet appears nowhere. Where a setting is on its way out, say so on the page that still documents it and name the replacement. Record the release that removes it once that release is known. Readers on an older line keep their own snapshot, so a removal does not strand them.

Update the documentation in the same change as the behavior. A UI or firmware change that alters documented behavior isn't finished until the docs match. Re-check screenshots and step sequences whenever the relevant UI moves, since steps drift before prose does.

Don't document internal or undocumented behavior as a stable contract unless it's intentionally supported. Date-stamp specs and audits in this repository and name the standards version they were graded against. Fix broken links when you find them; a dead link in a procedure stops the reader.

### 11.15 In-product text

In-product text follows the same rules as documentation and extends the plain language requirement in section 6.

Labels name the concept rather than the field, so Hop Limit and never `hop_limit` or a raw enum value. Subtext is one plain sentence saying what the setting does and what changes if it's altered. Match the wording the documentation uses for the same concept.

Button labels are verbs that match the outcome: Save, Send, Pair, Remove. Don't use OK for a destructive or consequential action.

Error messages say three things: what happened, why, and what to do next. "Couldn't connect to the node. It may be out of Bluetooth range. Move closer and try again." Never surface a bare error code, a stack trace, or a protobuf name.

Empty states explain the state and offer an action, as in "No nodes yet. Nodes appear here as they're heard on the mesh", rather than an empty screen or a dash. Destructive confirmations name the object and the consequence: "Remove Cabin Repeater? Message history with this node will be deleted", not "Are you sure?".

Don't leave a dead end. Every error, empty, and blocked state either offers a next action or says what it is waiting for. Keep strings translatable, as covered in 11.13.

### 11.16 Quick checks

These are the rules a reviewer can check without judgment. The rest of the section needs reading.

- [ ] Every image has alt text, and decorative images carry an explicit empty alt.
- [ ] Every code fence declares its language, and command-line examples use `shell`.
- [ ] At most one admonition per H2 section, and neither the `caution` nor the `important` alias.
- [ ] On-screen labels are quoted exactly as they appear, in bold.
- [ ] Headings are sentence case, with one H1 and no skipped levels.
- [ ] Product and technology names use their official casing.
- [ ] Prose uses American spelling.
- [ ] Running prose spells out for example and that is, rather than e.g. and i.e.
- [ ] No currently, now, soon, or new dating the page from inside it.
- [ ] Dates in prose spell the month.

---
### Agent Implementation Checklist (v1.5)
- [ ] Are **Circular IDs** used only for the *other* party in chat views?
- [ ] Are **List Rows** neutral (no colored backgrounds for the whole row)?
- [ ] Does the UI strictly follow **Light OR Dark** mode without mixing?
- [ ] Does the UI **hide** fields where data is unavailable (Null Data Suppression)?
- [ ] Are all navigation icons accompanied by **Text Labels**?
- [ ] Do interactive elements meet the **44x44px** hit target?
- [ ] Is the body text at least **16px** by default?
- [ ] Are all UI colors drawn from the **official palette** (Sections 7.2–7.6)?
- [ ] Is accent green **never used as text** on light backgrounds?
- [ ] Do all foreground/background pairings meet **WCAG AA 4.5:1** contrast?
- [ ] Are **semantic colors** (Link, Info, Warning, Error, Success) used consistently and not repurposed?
- [ ] Is the **Link** color using `Blue 600` (`#5C6BC0`) in light mode and `Blue 400` (`#9BA8E0`) in dark mode? No single value passes 4.5:1 on both grounds: Blue 400 measures 2.14:1 on Neutral 50, Blue 600 measures 3.52:1 on Neutral 900.
- [ ] Is **Success** using `Green 600` (`#3FB86D`) — not `Green 500` (`#67EA94`)?
- [ ] Does the M3 theme use **Section 8** role mappings (or dynamic color on Android 12+)?
- [ ] Are **Fixed colors** (Section 8.4) used for theme-invariant elements?
- [ ] Does message text use **`onSurface`** — never raw node foreground colors?
- [ ] Is the **Neutral Variant** scale (Section 7.3) used for outline and surfaceVariant roles?
- [ ] Are all device values stored and transmitted in their **canonical metric units** (Section 10.1)?
- [ ] Are display values converted using **OS measurement APIs** — not manual if/else branching or hardcoded unit strings (Section 10.2)?
- [ ] Is every measurement object constructed with the **correct source unit** matching the data source (Section 10.5)?
- [ ] Are locale lookups performed with **safe unwrapping** — no force-unwraps (Section 10.5)?
- [ ] Do **charts and graph axes** display values in the user's locale unit (Section 10.5)?
- [ ] Are **number formats** locale-aware — decimal separators, grouping, precision (Section 10.5)?
- [ ] Are universal units (hPa, °, µR/hr) displayed **without conversion** (Section 10.4)?
- [ ] Is date/time formatting delegated to the **OS locale** — no hardcoded formats (Section 10.6)?
