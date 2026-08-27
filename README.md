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
