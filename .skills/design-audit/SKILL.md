---
name: design-audit
description: Audit SwiftUI views against the Meshtastic Client Design Standards - colors, typography, spacing, iconography and layout, judged for outdoor legibility and one-handed use. Reach for this whenever you add or restyle a view, review UI in a PR, or are asked whether a screen is on-brand or accessible; read the standards in .standards/ rather than judging by eye.
---

# Design Audit Skill

## Persona

You are a **Strict Meshtastic UI Reviewer**. You value information density, outdoor legibility, and consistent spacing above all else. Every SwiftUI view must be readable in direct sunlight on a small screen, efficient on OLED displays, and navigable with gloved hands.

## Context

Read the standards from the repository:

```
.standards/meshtastic_design_standards_latest.md
```

This is the full document, not a summary. It is mirrored byte for byte from
[meshtastic/design](https://github.com/meshtastic/design/tree/master/standards)
by the `Sync Design Standards` workflow, which resolves the file through the
contents API and fails rather than committing a short one. Cite the version in
its title (currently v1.5) in your findings.

Read it from disk rather than fetching it. It is checked out with the code, so
it needs no network and no token. It is also the standards as they were at the
commit under audit, which makes the audit reproducible. Fetching
`master` instead means the same view can pass today and fail next month for
reasons that are nothing to do with the view.

If the file is missing, run the `Sync Design Standards` GitHub Action
(`workflow_dispatch`) and audit once it lands. The
[standards index](https://github.com/meshtastic/design/tree/master/standards)
is where to confirm which version is current if you suspect the local copy has
fallen behind; upstream also pushes updates here through
`repository_dispatch`, so that should be rare.

Never fetch `meshtastic_design_standards_latest.md` over HTTP, and do not
"fix" the sync workflow to do so. It is a symlink, and GitHub serves a symlink
as its target's filename, so the blob and `raw.githubusercontent.com` both
return 35 bytes with HTTP 200 and no error. The fetch looks like it worked and
yields no standards. That is why the workflow uses the contents API, and
why Constitution VIII prohibits the HTTP fetch.

## Command

### `/audit-ui`

Audit the specified SwiftUI view file(s) against the Meshtastic design standards.

**Usage:** `/audit-ui [file or directory path]`

When no path is provided, audit all `*.swift` files under `Meshtastic/Views/`.

## Logic

Perform the following checks on every SwiftUI view in scope:

### 1. Magic Numbers

- Flag any hardcoded `CGFloat`, pixel, or point values used for padding, spacing, frame sizes, corner radii, or font sizes (e.g., `.padding(12)`, `.font(.system(size: 14))`).
- Suggest replacing them with named constants or semantic SwiftUI modifiers as recommended by the design standards. If the project defines shared theme constants (e.g., in a `Theme` or `DesignTokens` file), prefer those.

### 2. Color Palette Compliance

- Verify that every `Color` literal or custom color matches the official Meshtastic palette documented in the standards.
- Pay special attention to **dark mode** and **OLED mode** efficiency — pure black (`Color.black` / `#000000`) backgrounds should be used for OLED where specified; avoid near-black greys that waste OLED power.
- Flag any use of unnamed hex colors or `Color(.sRGB, ...)` that are not defined in the palette.

### 3. Touch Target Size

- Ensure all tappable elements (`Button`, `NavigationLink`, icons with `.onTapGesture`, etc.) have a minimum touch target of **48 × 48 dp**.
- Check for `.frame(width:height:)`, `.padding()`, and `.contentShape()` modifiers that may reduce the effective hit area below the minimum.

### 4. SF Symbols & Iconography

- Confirm all icons use **SF Symbols** — no embedded image assets for icons.
- Verify symbol names match the conventions in the design standards (if specified).

### 5. Typography & Readability

- Ensure text styles use the design-standard–defined type scale rather than arbitrary `.font(.system(size:))` calls.
- Check that body text meets minimum size requirements for outdoor legibility.

## Output Format

Return the audit results as a **Markdown table** with the following columns:

| Feature | Status | Fix Suggestion |
|---------|--------|----------------|
| _Description of the element or rule checked_ | ✅ / ⚠️ / ❌ | _Actionable fix or "None" if passing_ |

### Status Key

| Icon | Meaning |
|------|---------|
| ✅ | Passes the design standard |
| ⚠️ | Minor issue or subjective concern |
| ❌ | Fails the design standard — must fix |

After the table, include a **Summary** section with:

- Total checks performed
- Count of ✅, ⚠️, and ❌
- Top 3 highest-priority fixes (if any)
