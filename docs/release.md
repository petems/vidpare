# VidPare Release Process (Universal macOS DMG)

## Prerequisites

- Apple Developer certificate installed on the runner/machine
- Notary keychain profile configured for `xcrun notarytool`
- Environment variables:
  - `APPLE_SIGN_IDENTITY`
  - `APPLE_TEAM_ID`
  - `NOTARY_KEYCHAIN_PROFILE`
  - `APP_BUNDLE_ID` (optional, defaults to `com.vidpare.app`)
  - `BUILD_NUMBER` (optional, defaults to `1`)

## Local Release Commands

Build universal app bundle:

```bash
VERSION=0.1.0 ./scripts/release/build-universal.sh
```

Sign and notarize app bundle:

```bash
./scripts/release/sign-and-notarize.sh dist/VidPare.app
```

Package DMG:

```bash
VERSION=0.1.0 ./scripts/release/package-dmg.sh
```

Sign and notarize DMG:

```bash
./scripts/release/sign-and-notarize.sh dist/VidPare-0.1.0.dmg
```

## Validation Gates

- Universal architecture check with `lipo -archs` in `build-universal.sh`
- Signature validation with `codesign --verify --deep --strict`
- Gatekeeper assessment with `spctl --assess`
- Notarization and stapling with `xcrun notarytool` + `xcrun stapler`

## CI Pipelines

- `.github/workflows/ci.yml`
  - Native arm64 build + tests
  - x86_64 build
  - x86_64 tests under Rosetta
  - Optional native Intel smoke job (`ENABLE_INTEL_RUNNER=true`)
- `.github/workflows/release.yml`
  - Triggered on `v*` tags
  - Builds universal app
  - Signs + notarizes `.app`
  - Packages DMG
  - Signs + notarizes `.dmg`
  - Publishes release artifact
