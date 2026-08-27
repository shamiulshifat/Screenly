# Screenly Launch Readiness Checklist

This checklist tracks the final path from feature-complete to production launch.

## 1) Build & Packaging

- [x] `swift build` passes on local machine
- [ ] Build a signed `.app` bundle with production signing identity
- [ ] Create release artifact (`.dmg` or zipped `.app`)
- [ ] Verify app launches cleanly on a fresh macOS user profile

## 2) Signing & Notarization

- [ ] Sign app bundle with Developer ID Application certificate
- [ ] Submit app for notarization (`notarytool`)
- [ ] Staple notarization ticket
- [ ] Validate Gatekeeper launch with `spctl --assess`

## 3) Permissions & Privacy UX

- [x] Screen/Camera/Microphone permission detection + settings deep links
- [x] Actionable permission-denied messages in setup UI
- [ ] Verify copy and behavior in first-run tests (clean macOS account)
- [ ] Verify post-settings-regrant recovery flow without relaunch regressions

## 4) Recording Correctness

- [x] Pause/resume timestamp compensation in writer pipeline
- [x] Screen + system audio + mic capture paths wired
- [x] Camera overlay and effect paths wired into encoded output
- [ ] Long-session AV sync soak tests (>= 30 min)
- [ ] Multi-pause scenario verification matrix

## 5) Stability & Device Changes

- [x] Device disconnect handlers for camera/microphone/display changes
- [x] Safe fallback behavior and user warning messaging
- [ ] Stress test hot-plugging USB/Bluetooth devices while recording

## 6) Performance Validation

- [x] In-app diagnostics (drops, queue pressure, AV offset, output bytes)
- [x] Trend-based warnings + safe mode mitigation
- [ ] Validate target workloads across M-series hardware profiles
- [ ] Tune effect presets from measured benchmarks

## 7) Release QA Matrix

Run and sign off:

- [ ] Built-in display + external display
- [ ] Built-in mic + AirPods + USB mic
- [ ] Built-in camera + external camera
- [ ] System audio ON/OFF
- [ ] Camera ON/OFF
- [ ] Blur/Replace/Normal backgrounds
- [ ] 30/60 fps presets
- [ ] Pause/resume cycles
- [ ] Hotkeys outside app focus

## 8) Operational Readiness

- [ ] Final release notes
- [ ] End-user setup guide
- [ ] Troubleshooting guide for permissions and common failures
- [ ] Internal rollback / hotfix procedure

---

## Completion Rule

Mark project launch-ready only when all required checkboxes are complete and verified on at least one clean target machine.
