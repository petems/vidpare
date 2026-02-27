#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="VidPare"
TARGET_PATH="${1:-${ROOT_DIR}/dist/${APP_NAME}.app}"

require_env() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required environment variable: ${key}" >&2
    exit 1
  fi
}

require_env "APPLE_SIGN_IDENTITY"
require_env "APPLE_TEAM_ID"
require_env "NOTARY_KEYCHAIN_PROFILE"

if [[ ! -e "${TARGET_PATH}" ]]; then
  echo "Target does not exist: ${TARGET_PATH}" >&2
  exit 1
fi

if [[ "${TARGET_PATH}" == *.app ]]; then
  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "${APPLE_SIGN_IDENTITY}" \
    "${TARGET_PATH}"

  /usr/bin/codesign --verify --deep --strict --verbose=2 "${TARGET_PATH}"
  /usr/sbin/spctl --assess --type execute --verbose=2 "${TARGET_PATH}"

  /usr/bin/xcrun notarytool submit \
    "${TARGET_PATH}" \
    --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" \
    --team-id "${APPLE_TEAM_ID}" \
    --wait

  /usr/bin/xcrun stapler staple -v "${TARGET_PATH}"

  /usr/bin/codesign --verify --deep --strict --verbose=2 "${TARGET_PATH}"
  /usr/sbin/spctl --assess --type execute --verbose=2 "${TARGET_PATH}"
  echo "Signed and notarized app: ${TARGET_PATH}"
  exit 0
fi

if [[ "${TARGET_PATH}" == *.dmg ]]; then
  /usr/bin/codesign \
    --force \
    --timestamp \
    --sign "${APPLE_SIGN_IDENTITY}" \
    "${TARGET_PATH}"

  /usr/bin/codesign --verify --strict --verbose=2 "${TARGET_PATH}"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "${TARGET_PATH}"

  /usr/bin/xcrun notarytool submit \
    "${TARGET_PATH}" \
    --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" \
    --team-id "${APPLE_TEAM_ID}" \
    --wait

  /usr/bin/xcrun stapler staple -v "${TARGET_PATH}"

  /usr/bin/codesign --verify --strict --verbose=2 "${TARGET_PATH}"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "${TARGET_PATH}"
  echo "Signed and notarized disk image: ${TARGET_PATH}"
  exit 0
fi

echo "Unsupported target type: ${TARGET_PATH}" >&2
exit 1
