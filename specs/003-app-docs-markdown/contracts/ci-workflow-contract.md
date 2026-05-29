# CI Workflow Contract

## Workflow 1: `docs-deploy.yml` (continuous / beta)

**Trigger**: `push` to `main` branch  
**Runner**: `macos-15`  
**Output**: Deploys built docs to `/beta/` path on GitHub Pages

### Steps (in order)

| Step | Action | Key outputs |
|------|--------|-------------|
| Checkout | `actions/checkout@v4` (full history) | Workspace |
| Install cmark-gfm | `brew install cmark-gfm` | `cmark-gfm` binary |
| Build docs | `bash scripts/build-docs.sh --output _site/beta` | HTML files, `index.json`, CSS in `_site/beta/` |
| Copy snapshots | `bash scripts/copy-snapshots.sh --output _site/beta/assets/screenshots` | PNGs |
| Check bundle size | Built into `build-docs.sh` — exits non-zero if > 10 MB, warning at 8 MB | Pass/fail |
| Mark beta pages | `build-docs.sh` injects `<div class="pre-release-banner">Pre-release — subject to change</div>` when `--beta` flag set | HTML with banner |
| Upload Pages artifact | `actions/upload-pages-artifact@v3` | Artifact |
| Deploy | `actions/deploy-pages@v4` | Live GitHub Pages update |

### Failure modes

| Failure | Behaviour |
|---------|-----------|
| `cmark-gfm` install fails | Workflow fails; no deployment |
| Bundle size > 10 MB | `build-docs.sh` exits 1; workflow fails; no deployment |
| Bundle size > 8 MB (warn) | `build-docs.sh` emits `::warning::` annotation; workflow continues |
| Snapshot copy finds 0 PNGs | `copy-snapshots.sh` emits `::warning::` annotation; continues (docs deploy without screenshots) |

---

## Workflow 2: `docs-release.yml` (versioned release)

**Trigger**: `push` tags matching `v*.*.*`  
**Runner**: `macos-15`  
**Output**: Deploys built docs to `/vX.Y.Z/` path; updates `_data/versions.yml`; updates `/latest/` redirect

### Steps (in order)

| Step | Action | Key outputs |
|------|--------|-------------|
| Checkout | `actions/checkout@v4` (full history) | Workspace |
| Extract version | `VERSION=${GITHUB_REF_NAME#v}` | e.g. `2.8.0` |
| Install cmark-gfm | `brew install cmark-gfm` | `cmark-gfm` binary |
| Build docs | `bash scripts/build-docs.sh --output _site/v${VERSION}` | HTML files, `index.json`, CSS |
| Copy snapshots | `bash scripts/copy-snapshots.sh --output _site/v${VERSION}/assets/screenshots` | PNGs |
| Check bundle size | Built into `build-docs.sh` | Pass/fail |
| Update versions manifest | Append entry to `docs/_data/versions.yml`, commit + push to `main` | Updated manifest |
| Create `/latest/` redirect | Write `_site/latest/index.html` with `<meta http-equiv="refresh" content="0; url=/v${VERSION}/">` | Redirect page |
| Update site root redirect | Overwrite `_site/index.html` to redirect to `/v${VERSION}/` | Site root |
| Upload Pages artifact | `actions/upload-pages-artifact@v3` | Artifact |
| Deploy | `actions/deploy-pages@v4` | Live GitHub Pages update |

### `_data/versions.yml` entry format

```yaml
- version: "X.Y.Z"
  path: "/vX.Y.Z/"
  label: "X.Y.Z (Latest)"
  is_latest: true        # Only set on the most recent stable release
  is_prerelease: false
```

---

## `build-docs.sh` Interface

```
Usage: scripts/build-docs.sh --output <dir> [--beta]

Options:
  --output <dir>   Directory to write generated HTML, index.json, and assets
  --beta           Inject pre-release banner into all pages

Exit codes:
  0   Success (size within limits)
  1   Hard failure (cmark-gfm not found, or bundle size > DOCS_SIZE_LIMIT_BYTES)

Environment variables:
  DOCS_SIZE_WARN_BYTES    Default: 8388608  (8 MB) — emits ::warning:: annotation
  DOCS_SIZE_LIMIT_BYTES   Default: 10485760 (10 MB) — exits 1

Output structure:
  <dir>/
  ├── index.json           Keyword index
  ├── user/*.html          User Guide pages
  ├── developer/*.html     Developer Guide pages
  └── assets/
      └── docs.css         Light/dark CSS
```

## `copy-snapshots.sh` Interface

```
Usage: scripts/copy-snapshots.sh --output <dir>

Options:
  --output <dir>   Directory to copy PNG files into

Behaviour:
  Copies all *.png files from MeshtasticTests/__Snapshots__/SwiftUIViewSnapshotTests/
  to <dir>/. Emits ::warning:: if 0 PNGs found. Never exits non-zero.
```
