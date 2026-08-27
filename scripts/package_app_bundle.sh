#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Framecast"
BUILD_DIR=".build/apple/Products/Release"
APP_DIR="dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

mkdir -p dist

echo "[1/4] Building release binary"
swift build -c release --arch arm64

BIN_PATH=$(find .build -type f -name "$APP_NAME" -perm -111 | head -n 1)
if [[ -z "${BIN_PATH:-}" ]]; then
  echo "Could not find built executable"
  exit 1
fi

echo "[2/4] Creating app bundle structure"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>com.framecast.app</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSCameraUsageDescription</key><string>Framecast uses camera input for webcam overlay recording.</string>
  <key>NSMicrophoneUsageDescription</key><string>Framecast uses microphone input for voice capture.</string>
</dict>
</plist>
PLIST

echo "[3/4] Bundle created: ${APP_DIR}"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "[4/4] Signing app bundle"
  codesign --deep --force --verify --verbose --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  echo "[4/4] Skipping signing (set SIGN_IDENTITY to enable)"
fi

echo "Done"
