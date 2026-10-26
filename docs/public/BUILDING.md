# Building Aava

Aava’s desktop shell is native SwiftUI/AppKit. Websites run in a pinned Chromium Embedded Framework (CEF) build. This repository contains the actual app, not just a mockup.

## Requirements

- Apple Silicon Mac, macOS 14 or later.
- Xcode command-line tools and Swift 5.10 or newer.
- CMake, Python 3 and several GB of free disk space.
- Network access for the pinned CEF download.

## Build

```sh
git clone https://github.com/jesseglab/aava.git
cd aava
python3 scripts/fetch-cef.py
./scripts/build-mac.sh
open build/mac/Aava.app
```

The build script creates an **ad-hoc-signed local development app**, not a notarized distribution or App Store archive. Do not disable Gatekeeper or other macOS protections to run a downloaded preview. Build locally or wait for a distribution-signed release if macOS cannot verify a package.

`Apps/macOS/cef-version.json` pins the engine and download checksum. `vendor/`, `build/` and `.build/` are intentionally excluded from Git. Generated icons and their licenses are included, so old design-output folders are not needed for the normal build.

For signing on a configured development Mac, set `AAVA_SIGN_IDENTITY` before running the build script. Direct distribution requires Developer ID signing, notarization and a production update channel; do not treat development signing as release approval. The Mac App Store is not the current release target.

See [direct distribution](DISTRIBUTION.md) for the staged signing/notarization workflow and [release validation](RELEASE-VALIDATION.md) for the current evidence and outstanding checks.

## Tests

```sh
swift test
python3 -m compileall -q scripts
python3 -m unittest discover -s Tests/Release -v
```

After a native build, the isolated cookie integration test can run with:

```sh
AAVA_SIGN_IDENTITY='<your local signing identity>' python3 scripts/test-arc-cookie-transfer.py
```

It creates a temporary test app and synthetic data, never reads real Arc credentials, and checks cookie scope, flags, isolation and restart persistence. Local Keychain/signing configuration can affect running this test.

## Data and profiles

Normal development data lives in `~/Library/Application Support/Aava`. Each space has its own Chromium request context and profile directory. `AAVA_DATA_DIRECTORY` selects an independent data root for test builds. Never point tests at someone’s real browsing profile.

Mini control is optional. Its temporary, separate profile does not share ordinary tabs, cookies, extensions or downloads. The included controller is `scripts/aava-mini.py`; start Mini inside Aava and use its copyable control prompt rather than guessing a socket or token.

## Layout

| Path | Responsibility |
|---|---|
| `Sources/AavaCore` | Spaces, history, bookmarks, import and state policies |
| `Apps/macOS/Sources` | SwiftUI/AppKit shell, CEF integration, Mini control |
| `Apps/macOS/Resources` | Brand assets, icons and licenses |
| `Apps/iOS` | Earlier incomplete WebKit sources; no release target yet |
| `Tests` | Core tests and standalone native integration harness |
| `docs/media` | Public screenshots and repository artwork |

The first release targets Apple Silicon Macs. Intel, Windows and Linux builds are not provided. iPhone/iPad follows the Mac release work; mobile parity is not claimed.
