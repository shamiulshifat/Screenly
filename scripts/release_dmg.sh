#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<USAGE
Usage:
  ./scripts/release_dmg.sh --version <v0.1.0|0.1.0> [--publish] [--notes "Release notes"]

Examples:
  ./scripts/release_dmg.sh --version v0.1.0
  ./scripts/release_dmg.sh --version 0.1.0 --publish --notes "First public release."
USAGE
}

VERSION=""
PUBLISH=false
NOTES="First public release."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --publish)
      PUBLISH=true
      shift
      ;;
    --notes)
      NOTES="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Error: --version is required"
  usage
  exit 1
fi

TAG="$VERSION"
if [[ "$TAG" != v* ]]; then
  TAG="v${TAG}"
fi

APP_NAME="Screenly"
APP_PATH="dist/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${TAG}-macOS-arm64.dmg"
DMG_PATH="dist/${DMG_NAME}"

echo "[1/3] Building app bundle"
./scripts/package_app_bundle.sh

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: app bundle not found at $APP_PATH"
  exit 1
fi

echo "[2/3] Creating DMG at $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "DMG ready: $DMG_PATH"

if [[ "$PUBLISH" == true ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: GitHub CLI 'gh' is required for --publish"
    exit 1
  fi

  if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "[3/3] Creating and pushing git tag $TAG"
    git tag -a "$TAG" -m "${APP_NAME} ${TAG}"
    git push origin "$TAG"
  else
    echo "[3/3] Tag $TAG already exists locally"
  fi

  echo "Publishing GitHub release $TAG"
  gh release create "$TAG" "$DMG_PATH" \
    --title "${APP_NAME} ${TAG}" \
    --notes "$NOTES"

  echo "Release published: $TAG"
fi

