# Screenly

A native macOS screen recorder built with Swift, SwiftUI, ScreenCaptureKit, and AVFoundation.

Screenly focuses on a simple recording workflow with high-quality local output, camera overlay controls, and lightweight in-recording controls.

## Features

- Display/window/app recording with optional region capture
- System audio + microphone capture
- Camera overlay with shape/background effects
- Draggable on-screen camera bubble during recording
- Global shortcuts for start/pause/stop/camera/mic
- Local recording metadata + project bundle export (`.screenly`)

## Requirements

- macOS 13+
- Xcode 15+ (or equivalent Swift toolchain)

## Quick Start

```bash
swift build
swift run Screenly
```

On first launch, macOS prompts for Screen Recording, Microphone, and optionally Camera permissions.

## Development

### Build

```bash
swift build
```

### Run

```bash
swift run Screenly
```

## Packaging / Release

- App bundle script: `scripts/package_app_bundle.sh`
- Preflight checks: `scripts/preflight_release.sh`
- Signing + notarization runbook: `scripts/release_sign_notarize.md`
- Launch checklist: `docs/LAUNCH_READINESS_CHECKLIST.md`

### Manual Release (DMG)

Quick helper script:

```bash
./scripts/release_dmg.sh --version v0.1.0
```

Or build + publish in one step:

```bash
./scripts/release_dmg.sh --version v0.1.0 --publish --notes "First public release."
```

1) **Build app bundle**

From repo root:

```bash
./scripts/package_app_bundle.sh
```

This creates:

- `dist/Screenly.app`

(If you have signing identity set, script can sign too.)

2) **(Recommended) Sign + notarize**

Use your existing runbook:

- `scripts/release_sign_notarize.md`

This ensures users can open the app without scary Gatekeeper warnings.

3) **Create DMG**

After `dist/Screenly.app` is ready (and ideally notarized/stapled), run:

```bash
VERSION=v0.1.0
DMG_NAME="Screenly-${VERSION}-macOS-arm64.dmg"

hdiutil create \
  -volname "Screenly" \
  -srcfolder "dist/Screenly.app" \
  -ov \
  -format UDZO \
  "dist/${DMG_NAME}"
```

You’ll get:

- `dist/Screenly-v0.1.0-macOS-arm64.dmg`

4) **Publish on GitHub Release**

If tag doesn’t exist yet:

```bash
git tag -a v0.1.0 -m "Screenly v0.1.0"
git push origin v0.1.0
```

Then create release and upload DMG (GitHub CLI):

```bash
gh release create v0.1.0 "dist/Screenly-v0.1.0-macOS-arm64.dmg" \
  --title "Screenly v0.1.0" \
  --notes "First public release."
```

## Project Layout

- `Sources/Screenly` — app/runtime, recording engine, UI, devices, effects, utilities
- `scripts` — build/release helper scripts
- `docs` — release and launch docs

## Privacy

Screenly is designed for local-first recording.

- Recording content stays on-device by default.
- No telemetry or analytics pipeline is included in this repository.

## Open Source

- License: MIT (`LICENSE`)
- Contributing guide: `CONTRIBUTING.md`
- Code of Conduct: `CODE_OF_CONDUCT.md`
- Security policy: `SECURITY.md`

## Maintainer

MD SHAMIUL ISLAM SHIFAT  
Bangladesh  
shifat.ruet@gmail.com
