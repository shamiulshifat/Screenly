# Release Signing + Notarization Runbook

## Prerequisites

- Apple Developer account with Developer ID certs.
- `xcode-select` configured with a recent Xcode.
- `notarytool` credentials configured in keychain profile.

## 1) Build app bundle

If using SwiftPM executable only, wrap into `.app` before signing, or migrate to an Xcode app target for release packaging.

## 2) Sign bundle

```bash
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: <TEAM NAME>" \
  /path/to/Screenly.app
```

## 3) Zip for notarization

```bash
ditto -c -k --keepParent /path/to/Screenly.app /tmp/Screenly.zip
```

## 4) Submit notarization

```bash
xcrun notarytool submit /tmp/Screenly.zip \
  --keychain-profile "AC_NOTARY_PROFILE" \
  --wait
```

## 5) Staple ticket

```bash
xcrun stapler staple /path/to/Screenly.app
```

## 6) Verify Gatekeeper

```bash
spctl --assess --type execute --verbose /path/to/Screenly.app
codesign --verify --deep --strict --verbose=2 /path/to/Screenly.app
```

## 7) Smoke test on clean user

- Launch app first time.
- Grant permissions.
- Record 30–60 second sample with mic+system audio+camera.
- Validate output playback and diagnostics JSON.
