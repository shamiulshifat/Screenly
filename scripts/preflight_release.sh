#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/6] Checking toolchain"
command -v swift >/dev/null
command -v xcrun >/dev/null

echo "[2/6] Building project"
swift build

echo "[3/6] Verifying required docs"
test -f docs/LAUNCH_READINESS_CHECKLIST.md

echo "[4/6] Checking notarization tooling availability"
if ! xcrun notarytool --help >/dev/null 2>&1; then
  echo "WARN: notarytool unavailable in this environment"
fi

echo "[5/6] Checking Apple signing identities"
if ! security find-identity -v -p codesigning >/dev/null 2>&1; then
  echo "WARN: unable to enumerate code-signing identities"
fi

echo "[6/6] Preflight complete"
echo "Next: run scripts/release_sign_notarize.md flow manually with valid Apple credentials."
