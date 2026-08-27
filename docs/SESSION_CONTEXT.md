# Framecast Session Context (Handoff)

_Last updated: 2026-08-26_

This file captures what has been built so far and where to continue after restart.

## Repository State

- Project was bootstrapped from docs-only repo into a native Swift macOS app (SwiftPM executable target).
- Build status: `swift build` passing.
- Preflight script status: `./scripts/preflight_release.sh` passing.

## High-Level Progress

Implemented substantial scope from `README.md` / `framecast-coding-agent.md`:

- Phase 1: Screen recording pipeline (display/window/app, start/stop, countdown, permissions)
- Phase 2: Audio pipeline (system audio + microphone selection + live meter)
- Phase 3: Camera setup and recording overlay compositing
- Phase 4: Background effects path (normal/blur/replace) wired into compositing
- Phase 5: Floating recording controller
- Phase 6: Global hotkeys + HUD notifications

Also added:

- Device change handling/fallbacks
- Diagnostics, trends, warning thresholds, safe mode, auto-safe-mode
- Metadata export + diagnostics JSON + `.framecast` project bundle output
- Save directory configuration + persistence
- Menu bar actions for recordings/diagnostics/project bundle
- Region capture controls for display source

## Key Files Added/Modified

### App / Runtime
- `Sources/Framecast/App/FramecastApp.swift`
- `Sources/Framecast/App/AppRuntimeController.swift`
- `Sources/Framecast/App/MenuBarManager.swift`

### Recording Core
- `Sources/Framecast/Recording/RecordingCoordinator.swift`
- `Sources/Framecast/Recording/RecordingState.swift`
- `Sources/Framecast/Recording/RecordingError.swift`
- `Sources/Framecast/Recording/ScreenRecorder.swift`
- `Sources/Framecast/Recording/RecordingDiagnostics.swift`
- `Sources/Framecast/Recording/QualityPreset.swift`
- `Sources/Framecast/Recording/CaptureRegion.swift`

### Devices / Audio / Camera / Effects
- `Sources/Framecast/Devices/ScreenCaptureDiscovery.swift`
- `Sources/Framecast/Devices/ScreenCaptureSource.swift`
- `Sources/Framecast/Audio/AudioInputDevice.swift`
- `Sources/Framecast/Audio/MicrophoneDiscovery.swift`
- `Sources/Framecast/Audio/MicrophoneMeterEngine.swift`
- `Sources/Framecast/Camera/CameraDevice.swift`
- `Sources/Framecast/Camera/CameraDiscovery.swift`
- `Sources/Framecast/Camera/CameraPreviewService.swift`
- `Sources/Framecast/Camera/CameraPreviewView.swift`
- `Sources/Framecast/Camera/CameraFrameProvider.swift`
- `Sources/Framecast/Effects/CameraEffectModels.swift`
- `Sources/Framecast/Effects/CameraOverlayConfiguration.swift`

### UI
- `Sources/Framecast/UI/RecordingSetup/RecordingSetupView.swift`
- `Sources/Framecast/UI/RecordingOverlay/RecordingOverlayPanelManager.swift`
- `Sources/Framecast/UI/HUD/HUDNotificationManager.swift`
- `Sources/Framecast/UI/CameraControls/CameraOverlayEditorView.swift`

### Hotkeys
- `Sources/Framecast/Hotkeys/GlobalShortcutManager.swift`

### Projects / Metadata
- `Sources/Framecast/Projects/RecordingMetadata.swift`
- `Sources/Framecast/Projects/RecordingEvent.swift`
- `Sources/Framecast/Projects/RecordingDiagnosticsReport.swift`
- `Sources/Framecast/Projects/RecordingProjectWriter.swift`

### Utilities / Settings
- `Sources/Framecast/Utilities/FramecastLogger.swift`
- `Sources/Framecast/Utilities/RecordingFileStore.swift`
- `Sources/Framecast/Utilities/JSONEncoder+Framecast.swift`
- `Sources/Framecast/Settings/AppSettingsStore.swift`

### Release/Launch Docs + Scripts
- `docs/LAUNCH_READINESS_CHECKLIST.md`
- `scripts/preflight_release.sh`
- `scripts/package_app_bundle.sh`
- `scripts/release_sign_notarize.md`

## How to Resume Quickly

1. Open repo in VS Code.
2. Run:
   - `swift build`
   - `swift run Framecast`
3. Use manual smoke flow:
   - Start recording, pause/resume, stop
   - Test mic/system audio/camera/effects
   - Test hotkeys: `⌘⇧R/P/S/C/M`
   - Open diagnostics JSON + show project bundle

## Current Known Gaps for True Production Launch

Even though core features are implemented, true launch-ready requires:

- Signed `.app` with real Developer ID identity
- Notarization + staple + Gatekeeper validation
- Full clean-machine QA matrix sign-off
- Long-run soak/performance verification across hardware profiles

Use:
- `docs/LAUNCH_READINESS_CHECKLIST.md`
- `scripts/release_sign_notarize.md`

## Next Recommended Task

Run full local QA matrix and fix issues found.
If clean, proceed with packaging/signing/notarization flow.

