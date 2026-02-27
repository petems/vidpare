#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_NAME="VidPare"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
VERSION="${VERSION:-${1:-0.1.0-dev}}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${APP_BUNDLE_ID:-com.vidpare.app}"

pushd "${ROOT_DIR}" >/dev/null

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

swift build -c release --triple arm64-apple-macosx14.0
swift build -c release --triple x86_64-apple-macosx14.0

ARM_BINARY="${ROOT_DIR}/.build/arm64-apple-macosx/release/${APP_NAME}"
X86_BINARY="${ROOT_DIR}/.build/x86_64-apple-macosx/release/${APP_NAME}"
UNIVERSAL_BINARY="${APP_DIR}/Contents/MacOS/${APP_NAME}"

if [[ ! -x "${ARM_BINARY}" || ! -x "${X86_BINARY}" ]]; then
  echo "Missing one or more release binaries." >&2
  exit 1
fi

lipo -create "${ARM_BINARY}" "${X86_BINARY}" -output "${UNIVERSAL_BINARY}"
chmod +x "${UNIVERSAL_BINARY}"

PLIST_TEMPLATE="${ROOT_DIR}/scripts/release/Info.plist.template"
PLIST_OUTPUT="${APP_DIR}/Contents/Info.plist"

sed \
  -e "s/__BUNDLE_ID__/${BUNDLE_ID}/g" \
  -e "s/__VERSION__/${VERSION}/g" \
  -e "s/__BUILD_NUMBER__/${BUILD_NUMBER}/g" \
  "${PLIST_TEMPLATE}" > "${PLIST_OUTPUT}"

ARCHS="$(lipo -archs "${UNIVERSAL_BINARY}")"
if [[ "${ARCHS}" != *"arm64"* || "${ARCHS}" != *"x86_64"* ]]; then
  echo "Universal binary arch validation failed. Found: ${ARCHS}" >&2
  exit 1
fi

echo "Built universal app bundle at: ${APP_DIR}"
echo "Binary architectures: ${ARCHS}"

popd >/dev/null
