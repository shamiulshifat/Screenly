# Screenly
Screen recorder app for mac

## Current implementation status

Current implementation progress:

- native Swift macOS app scaffold (SwiftUI + ScreenCaptureKit + AVFoundation)
- explicit recording state machine and coordinator
- display/window/application source discovery and grouped picker
- start/stop/pause/resume screen recording pipeline with timestamp compensation
- H.264 MP4 local output in `~/Movies/Framecast/`
- system audio + selected microphone recording (with mixed final output)
- microphone discovery + live meter + mute toggle
- camera discovery + camera preview + camera enable toggle
- floating recording overlay panel
- global hotkeys + temporary HUD notifications
- menu-bar quick controls (start/pause/stop)
- typed errors, permission recovery actions, and unified logging

In progress:

- composited camera overlay in the final encoded video
- realtime background blur/replacement processing pipeline for recorded output

## Run locally

```bash
swift build
swift run Framecast
```

When first recording, macOS should prompt for Screen Recording permission.
If permission is denied, enable it in System Settings and relaunch the app.

## Launch readiness workflow

Use these files for release hardening and shipping checks:

- `docs/LAUNCH_READINESS_CHECKLIST.md`
- `scripts/preflight_release.sh`
- `scripts/release_sign_notarize.md`

Run preflight:

```bash
./scripts/preflight_release.sh
```

Then complete code-signing + notarization with your Apple Developer credentials using the runbook.

Framecast — Native macOS Screen Recorder

Product Summary

Build Framecast, a high-quality, native macOS screen recorder focused on simplicity, excellent Apple Silicon performance, and professional recording quality.

Framecast should let users:

Record an entire display, a window, an application, or a selected region.

Record system audio.

Record a selected microphone.

Select between the Mac microphone, AirPods/Bluetooth microphones, USB microphones, and other available macOS audio inputs.

Enable the built-in or external webcam while recording.

Display the webcam as a configurable floating camera bubble.

Blur the webcam background.

Replace the webcam background with a user-selected image.

Show live microphone level meters before and during recording.

Pause, resume, and stop recordings with global keyboard shortcuts.

Show a floating recording controller while recording.

Exclude Framecast's own controls from the captured video where possible.

Encode video using native Apple hardware acceleration.

Save recordings locally as high-quality .mov or .mp4 files.

The first version should be a fully native macOS application.

Do not build the core application using Electron, Chromium, WebRTC, OBS embedding, or a browser-based recording stack.

Core Product Principles

1. Native First

Use Apple's native APIs and hardware capabilities wherever practical.

Preferred technologies:

Swift

SwiftUI

AppKit when SwiftUI is insufficient

ScreenCaptureKit

AVFoundation

CoreAudio

VideoToolbox

Core Image

Vision

Core ML

Metal where appropriate

Do not introduce third-party frameworks unless they solve a concrete problem significantly better than the native platform.

2. Apple Silicon Optimized

Framecast should target modern Apple Silicon Macs first.

The recording pipeline should avoid unnecessary CPU copies and unnecessary conversions between:

CMSampleBuffer

CVPixelBuffer

Metal textures

encoded video frames

Prefer zero-copy or GPU-backed paths where Apple's APIs permit them.

Hardware-assisted H.264 and HEVC encoding should be preferred.

3. Simple UX

The application should feel closer to a lightweight native utility than a complex video editor.

The main workflow should be:

Open Framecast.

Choose capture source.

Choose camera.

Choose microphone.

Configure camera background.

Verify audio levels.

Press Record.

Use compact floating controls or hotkeys.

Stop recording.

Open or reveal the completed recording.

The user should not need to understand codecs, bitrates, routing graphs, or capture-device internals for normal operation.

Technical Architecture

Use a modular architecture similar to:

Framecast
├── App
├── UI
│   ├── RecordingSetup
│   ├── SourcePicker
│   ├── CameraControls
│   ├── AudioControls
│   ├── RecordingOverlay
│   ├── CountdownOverlay
│   └── Settings
│
├── Recording
│   ├── RecordingCoordinator
│   ├── RecordingState
│   ├── ScreenCaptureEngine
│   ├── CameraCaptureEngine
│   ├── AudioCaptureEngine
│   ├── Compositor
│   ├── Encoder
│   └── RecordingSession
│
├── Effects
│   ├── BackgroundBlur
│   ├── BackgroundReplacement
│   └── CameraMask
│
├── Devices
│   ├── DisplayDiscovery
│   ├── CameraDiscovery
│   └── AudioDeviceDiscovery
│
├── Hotkeys
│   └── GlobalShortcutManager
│
├── Projects
│   ├── RecordingProject
│   └── RecordingMetadata
│
└── Utilities

Avoid putting capture, UI, encoding, and state management into one monolithic class.

Recording State Machine

Use an explicit recording state model.

Recommended states:

enum RecordingState {
    case idle
    case preparing
    case countdown
    case recording
    case paused
    case stopping
    case completed
    case failed
}

Transitions should be deterministic.

Do not allow UI components to independently infer recording state from unrelated properties.

The RecordingCoordinator should own the authoritative session state.

Screen Capture

Use ScreenCaptureKit.

Support:

Entire display

Individual window

Individual application

Region capture where practical

Use SCShareableContent to discover available:

displays

applications

windows

Use:

SCContentFilter

SCStream

SCStreamConfiguration

Capture should support Retina/native-resolution displays.

Initial target:

30 fps

60 fps

Prefer 60 fps when hardware and selected quality settings permit.

Excluding Framecast UI

Framecast's own UI should not appear in the finished screen recording wherever ScreenCaptureKit filtering permits it.

Exclude:

main Framecast window

countdown window

recording controller

microphone HUD

camera controls

status notifications

The user should be able to see the recording controller without recording it.

Investigate filtering Framecast's application/windows using SCContentFilter.

Do not implement the floating UI by burning it directly into the screen-capture stream.

System Audio

Capture system/application audio through ScreenCaptureKit.

Provide:

System Audio
[✓] Record system audio

Where supported, allow excluding Framecast's own audio.

The audio pipeline must remain synchronized with video.

Microphone Capture

Support any available macOS input device.

Examples:

MacBook built-in microphone

AirPods microphone

Bluetooth headset microphone

USB microphone

audio interface

Enumerate devices dynamically.

Do not hard-code device names.

The selected microphone must be preserved when possible between sessions.

Live Audio Meter

Display a live microphone meter before recording and during recording.

Example:

Microphone
MacBook Pro Microphone ▼

▁▁▂▃▅▇████▆▃▂▁

The meter should:

react with low latency

show whether audio is actually being received

make silent/disconnected microphones obvious

continue working while recording

Do not derive the meter from encoded audio.

Calculate it from live PCM samples.

A basic RMS + peak calculation is sufficient initially.

Bluetooth / AirPods

AirPods and Bluetooth microphones must be selectable when macOS exposes them as input devices.

Do not attempt to hide Bluetooth microphones simply because they may have lower recording quality.

However, the UI may display a small quality hint such as:

AirPods Pro
Bluetooth voice quality

Device routing changes during a recording should be handled gracefully.

At minimum:

detect disconnect

surface an obvious warning

avoid crashing the recording session

Webcam

Use AVFoundation for camera capture.

Support:

built-in FaceTime camera

external USB cameras

Continuity Camera if exposed through AVFoundation

The camera can be:

disabled

enabled before recording

toggled while recording

Initial webcam resolutions:

720p

1080p

Prefer the best supported format without overloading the machine.

Webcam Overlay

Render the camera as a compositor layer over the captured screen.

Supported layouts:

circle

rounded rectangle

rectangle

Allow:

drag position

resize

hide/show

camera mirror toggle

Default location:

bottom-right.

The camera overlay should remain resolution-independent.

Store position using normalized coordinates rather than absolute pixels.

Example:

{
  "x": 0.82,
  "y": 0.78,
  "width": 0.16
}

Camera Background Blur

Implement real-time person/background segmentation.

Preferred implementation order:

Investigate native macOS system video effects available through AVFoundation.

Use Apple's native background/person segmentation when programmatically appropriate.

If additional control is needed, use Vision/Core ML segmentation.

Composite using Core Image or Metal.

Support:

Background

○ Normal
● Blur
○ Replace

Blur strength:

Light
Medium
Strong

Do not send webcam frames to a cloud service.

All background processing must happen locally.

Custom Background Replacement

Allow the user to select a local image.

Supported initial formats:

PNG

JPEG

HEIC

Pipeline:

camera frame
    ↓
person segmentation
    ↓
foreground mask
    ↓
background image
    ↓
GPU composition
    ↓
camera overlay

The image should fill the camera frame using aspect-fill behavior.

Avoid stretching backgrounds.

Cache and preprocess the selected background rather than decoding it for every frame.

Video Composition

Prefer a GPU-backed compositor.

Composition inputs:

screen frame
camera frame
camera mask
camera background
camera position
camera shape

Output:

final video frame

Possible implementation:

Metal

Core Image backed by Metal

Avoid creating NSImage or CGImage objects for every video frame.

That will introduce unnecessary CPU overhead.

Recording Model

Design the recorder so the application can eventually support non-destructive editing.

Even if V1 produces a flattened recording, structure the recording session around independent sources.

Preferred future-compatible project structure:

RecordingName.framecast
├── screen.mov
├── camera.mov
├── system-audio.m4a
├── microphone.m4a
├── events.json
└── project.json

For the earliest MVP, generating only the final rendered file is acceptable.

However, do not tightly couple the architecture to flattened-only recording.

Recording Events

Track important recording events.

Example:

[
  {
    "timestamp": 12.420,
    "type": "pause"
  },
  {
    "timestamp": 17.805,
    "type": "resume"
  },
  {
    "timestamp": 43.120,
    "type": "cameraMoved",
    "x": 0.72,
    "y": 0.77
  }
]

This will enable a future editor to reproduce and modify recording state.

Encoder

Use native Apple media frameworks.

Preferred:

AVAssetWriter

VideoToolbox where direct control is needed

Initial codecs:

H.264
HEVC

Future:

ProRes

Default export:

MP4
H.264

or

MOV
HEVC

depending on compatibility decisions.

Hardware encoding should be used whenever available.

Do not use FFmpeg as the primary recording encoder.

FFmpeg may only be considered later for optional post-processing functionality if absolutely necessary.

Quality Presets

Implement simple presets.

Standard

30 fps
H.264
moderate bitrate
good compatibility

High

60 fps
H.264 or HEVC
higher bitrate
Retina-aware

Maximum

native capture resolution
60 fps where supported
HEVC
high bitrate

Avoid exposing dozens of low-level encoder options in the main UI.

Advanced controls can be added later.

Floating Recording Controller

While recording, show a compact floating panel.

Example:

╭──────────────────────────────────────╮
│ ● 02:37   ⏸   🎙 ▂▅██▅▂   📷   ■ │
╰──────────────────────────────────────╯

Required information:

recording status

elapsed duration

pause/resume

microphone level

camera enabled/disabled

stop recording

Implement this as a floating AppKit/SwiftUI panel.

Consider NSPanel for behavior not easily achievable with a normal SwiftUI window.

Properties:

always visible

compact

movable

should not steal focus unnecessarily

should not appear in recordings

Countdown

Before recording starts, display:

3
2
1

The countdown must not be captured in the final recording.

Recording should begin only after the countdown finishes.

Allow the countdown duration to eventually become configurable.

Initial default:

3 seconds.

Global Hotkeys

Support global shortcuts.

Initial defaults:

Start recording   ⌘ ⇧ R
Pause/resume      ⌘ ⇧ P
Stop recording    ⌘ ⇧ S
Toggle camera     ⌘ ⇧ C
Toggle microphone ⌘ ⇧ M

These must work even when Framecast is not the foreground application.

Shortcuts should eventually be configurable.

Handle shortcut conflicts gracefully.

In-Recording HUD Notifications

When a global shortcut is triggered, briefly show a native HUD.

Examples:

Microphone muted
⌘ ⇧ M

Paused
⌘ ⇧ P

Camera off
⌘ ⇧ C

HUDs should disappear automatically and should not appear in the recorded video.

Menu Bar

Framecast should support a menu-bar-first workflow.

Menu-bar menu:

Framecast

New Recording
───────────────
Screen       Built-in Retina Display
Camera       FaceTime HD Camera
Microphone   MacBook Pro Microphone
System Audio On

Start Recording

───────────────
Recordings
Settings
Quit

The full setup window may still exist.

The menu bar should provide fast access to common actions.

Recording Setup UI

Build a clean setup screen.

Suggested structure:

┌───────────────────────────────────────┐
│ Framecast                             │
│                                       │
│ Capture                               │
│ Built-in Retina Display        ▼      │
│                                       │
│ Camera                                │
│ FaceTime HD Camera             ▼      │
│ [ camera preview ]                    │
│                                       │
│ Background                            │
│ Normal   Blur   Replace               │
│                                       │
│ Microphone                            │
│ MacBook Pro Microphone         ▼      │
│ ▂▅██▅▂                                │
│                                       │
│ [✓] Record system audio               │
│                                       │
│ Quality                               │
│ High                           ▼      │
│                                       │
│             [ Start Recording ]       │
└───────────────────────────────────────┘

Keep the UI native and restrained.

Do not imitate Teams or Zoom visually.

Permissions

Handle macOS permissions explicitly.

Required permissions may include:

Screen Recording

Camera

Microphone

The app must:

detect missing permissions

explain why they are required

request them using macOS APIs

provide a way to open the appropriate System Settings page

gracefully recover after permission changes

Do not simply fail silently when ScreenCaptureKit returns no usable content.

Error Handling

Create typed errors where practical.

Examples:

enum RecordingError: Error {
    case screenPermissionDenied
    case microphonePermissionDenied
    case cameraPermissionDenied
    case screenSourceUnavailable
    case microphoneUnavailable
    case cameraUnavailable
    case encoderInitializationFailed
    case recordingWriteFailed
}

User-facing errors should be concise and actionable.

Do not surface raw framework errors unless they are also logged for debugging.

Device Changes

Watch for device changes.

Examples:

AirPods disconnect

USB microphone unplugged

external monitor disconnected

webcam removed

The app should not crash.

For audio device disappearance:

detect the change

notify the user

switch to a safe fallback if possible

record the event

For capture display disappearance:

stop gracefully if continuing is impossible.

Performance

Performance is a first-class requirement.

Initial target on a modern Apple Silicon Mac:

screen: 2560×1600 @ 60 fps
camera: 1080p @ 30 fps
system audio: enabled
microphone: enabled
background blur: enabled
hardware encoding: enabled

The application should avoid:

excessive CPU utilization

unnecessary memory growth

dropped frames

audio/video drift

blocking the main UI thread

Instrumentation should track:

dropped screen frames

dropped camera frames

current encoder queue depth

recording duration

output bytes

AV synchronization offset where measurable

Threading

Do not run capture processing on the main actor.

Use dedicated queues/tasks for:

ScreenCaptureKit callbacks

camera frames

audio processing

compositing

encoding

UI updates should be forwarded back to the main actor.

Be deliberate about buffer ownership and lifetime.

Logging

Use Apple's unified logging.

Prefer:

import OSLog

Create categories such as:

capture
camera
audio
encoder
effects
hotkeys
permissions
ui

Do not use excessive print() statements in production code.

Storage

Default save location:

~/Movies/Framecast/

Allow the user to change this in Settings.

Suggested filename:

Framecast 2026-08-24 at 14.32.18.mov

Use collision-safe naming.

Do not overwrite existing recordings.

Recording Completion

After stopping:

finalize encoder/writer safely

verify file exists

transition state to completed

display completion UI

Example:

Recording saved

Framecast 2026-08-24 at 14.32.18.mov

[Open] [Show in Finder]

The app must not report success before the asset writer has finished finalizing the file.

MVP Scope

Implement the MVP in the following order.

Phase 1 — Screen Recording

Build:

macOS project

ScreenCaptureKit discovery

display selection

window selection

screen capture

local recording

H.264 hardware-compatible encoding

start/stop

elapsed timer

permissions

Acceptance criteria:

user can record the screen

video plays correctly in QuickTime

no major frame corruption

audio/video timestamps remain stable

Phase 2 — Audio

Build:

system audio capture

microphone enumeration

microphone selection

live microphone meter

simultaneous system + microphone recording

Acceptance criteria:

user can hear system audio

user can hear selected microphone

user can switch the selected input before recording

AirPods appear if macOS exposes them as an input

meter responds in real time

Phase 3 — Camera

Build:

AVFoundation camera discovery

live preview

enable/disable camera

camera overlay

circle/rounded rectangle mask

resize and reposition

Acceptance criteria:

webcam remains synchronized with screen capture

overlay is smooth

camera can be moved before recording

Phase 4 — Background Effects

Build:

blur

custom background image

person segmentation

GPU-backed composition

Acceptance criteria:

segmentation operates in real time

recording remains usable at 30/60 fps depending on hardware

custom backgrounds do not distort

Phase 5 — Recording Controller

Build:

floating controller

timer

microphone meter

pause

resume

stop

toggle microphone

toggle camera

Acceptance criteria:

controller stays visible over other apps

controller is not included in the capture

actions update recording state reliably

Phase 6 — Hotkeys

Build:

global shortcut registration

start

pause/resume

stop

camera toggle

microphone toggle

temporary HUD

Acceptance criteria:

shortcuts work outside Framecast

hotkeys cannot accidentally trigger duplicate transitions

HUD does not appear in the recorded output

Pause / Resume

Pause/resume must preserve correct output timestamps.

Do not create playback files containing long frozen timestamp gaps simply because recording was paused.

Track paused duration and compensate timestamps, or use an equivalent robust writer strategy.

Test repeatedly:

record 10 sec
pause 5 sec
record 10 sec
pause 3 sec
record 10 sec
stop

Expected output duration:

approximately 30 seconds, not 38 seconds.

Future Architecture

Do not build these features in the MVP unless required, but keep the architecture compatible with them:

non-destructive editor

separate camera track

separate system audio track

separate microphone track

silence removal

transcription

captions

automatic zoom

click highlighting

cursor smoothing

keyboard visualization

webcam layout editing after recording

background replacement after recording

audio cleanup

export presets

GIF export

direct sharing

cloud upload

team workspace

presentation mode

teleprompter

Non-Goals for V1

Do not spend early implementation time on:

cloud backend

accounts

authentication

team collaboration

AI summaries

video hosting

browser extension

Windows support

iOS support

complex timeline editing

OBS plugin compatibility

The initial goal is to build an excellent local macOS recorder.

Coding Guidelines

Before implementing any feature:

Inspect the existing repository.

Understand current architecture and conventions.

Reuse existing components.

Avoid duplicate managers or services.

Keep framework boundaries clean.

Write small focused types.

Prefer composition over large inheritance hierarchies.

Avoid premature abstractions.

Keep capture code testable where possible.

Keep UI state separate from media-pipeline state.

Repository Inspection

Before changing code, inspect:

current branch

git status

existing app targets

deployment target

Swift version

package dependencies

entitlement configuration

sandbox configuration

Info.plist usage descriptions

ScreenCaptureKit code

AVFoundation code

AppDelegate/Scene setup

menu-bar implementation

current design system

persistence approach

tests

Do not rewrite existing working infrastructure unnecessarily.

macOS Target

Prefer a modern macOS deployment target that provides a strong ScreenCaptureKit experience.

Choose the minimum supported macOS version intentionally after checking the API availability needed for:

screen audio capture

microphone capture

ScreenCaptureKit filters

current AVFoundation effects

hardware encoding

Use availability checks if supporting multiple recent macOS releases.

Security / Privacy

Framecast is a local recording application.

By default:

recordings remain on-device

webcam frames remain on-device

microphone audio remains on-device

background segmentation remains on-device

Do not add analytics that record screen contents, camera frames, microphone audio, filenames, or recording content.

Any future telemetry must be strictly operational and privacy-preserving.

Testing

Create automated tests for pure logic where possible.

Examples:

recording state transitions

pause timestamp adjustment

project metadata serialization

normalized camera coordinates

filename generation

quality preset mapping

Media APIs may require integration/manual testing.

Maintain a manual test matrix covering:

M-series Mac
built-in display
external display
built-in mic
AirPods
USB microphone
built-in camera
external camera
system audio on/off
camera on/off
blur on/off
30 fps
60 fps
pause/resume
device disconnect during recording

Definition of Done for Initial Product

The first product-quality milestone is complete when a user can:

Install and launch Framecast.

Grant screen, camera, and microphone permissions.

Select a display/window.

Select a microphone.

See the microphone meter working.

Enable the webcam.

Choose normal, blurred, or custom webcam background.

Start recording after a countdown.

See a floating recording controller.

Pause/resume recording.

Toggle microphone/camera.

Stop using the controller or a global shortcut.

Receive a playable high-quality recording.

Open the recording in QuickTime.

Record at high resolution without unreasonable CPU usage.

Use Framecast controls without those controls appearing in the captured video.

Initial Engineering Task

Start by building Phase 1 only.

Do not attempt to implement every feature at once.

First:

Inspect the repository.

Verify macOS deployment target and entitlements.

Create the recording state machine.

Implement ScreenCaptureKit source discovery.

Build a minimal source picker.

Capture one display.

Encode the captured frames using AVFoundation/VideoToolbox-compatible native APIs.

Save the finished recording locally.

Implement start/stop.

Verify the resulting file with QuickTime.

Add basic error handling and logging.

Keep interfaces ready for camera and audio integration.

Once Phase 1 is stable, proceed through the phases sequentially.

Do not compromise recording correctness for UI polish.
