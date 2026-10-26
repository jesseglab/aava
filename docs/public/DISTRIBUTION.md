# Direct Mac distribution

Aava targets a Developer ID signed, notarized Apple Silicon download. A development signature, a passing test suite, and an Apple notarization are separate results. The current preview is not a notarized daily-driver release.

## Required setup

1. Install the publishing team's **Developer ID Application** certificate and its private key in the signing Mac's Keychain. An Apple Development or App Store distribution certificate cannot substitute for it. Confirm the team in Apple Developer before issuing a certificate; do not revoke existing certificates as part of setup.
2. Configure a named `notarytool` Keychain profile using Apple's interactive credentials flow or an approved App Store Connect API key. Keep credentials and private keys out of this repository, logs, shell history, and chat.
3. Build the native app using `scripts/build-mac.sh`. Choose a dedicated release staging directory outside cloud-synced folders: Finder/File Provider metadata can invalidate a copied app signature.
4. Choose the release version and numeric build number. The pipeline sets the distribution bundle ID to `app.geeklab.aava`, removes test data-directory overrides, and updates helper bundle metadata.

The installed Xcode command-line tools must provide `codesign`, `notarytool`, `stapler`, and `spctl`. Apple account access and network access are required. No database migration is involved.

## Create and verify a package

Replace the placeholders with the configured identity, team, profile, paths, and release numbers:

```sh
python3 scripts/notarize-mac.py \
  --app /path/to/assembled/Aava.app \
  --work-dir /private/tmp/aava-release-UNIQUE-BUILD \
  --identity 'Developer ID Application: PUBLISHER (TEAMID)' \
  --team-id TEAMID \
  --keychain-profile aava-notary \
  --version 0.3.0 \
  --build-number 4
```

The script signs libraries, the framework, helpers, and the app inside-out. It enables hardened runtime and secure timestamps, using JIT entitlements only for the Chromium renderer and GPU helper roles. The main app declares camera and microphone access, which still require user permission. It does not disable library validation or add debugger entitlements.

The script submits a signed ZIP, records Apple's submission ID and its checksum, and waits for a result. A processing timeout retains the submission: repeat the same command to resume rather than submitting again. A modified submitted archive is rejected. If signing or submission fails before an ID is saved, inspect the retained work directory; use a fresh directory instead of overwriting the evidence.

Only an **Accepted** result proceeds to stapling, signature verification, and Gatekeeper assessment. The script then creates and extracts a candidate ZIP and repeats verification on the extracted app. Only after these checks pass does it expose `Aava-VERSION-macos-arm64.zip` with a SHA-256 sidecar. It retains Apple's log and the submission state locally. It does not publish a GitHub release or install over a user's browser.

## Validation before publishing

- Test the exact packaged, downloaded app on a clean account/Mac with quarantine intact. Do not remove quarantine or bypass Gatekeeper.
- Verify real representative extensions, sign-in, camera/microphone, screen sharing, Meet/Teams popouts, and relaunch persistence. Record specific results; engine compatibility is not proof that every Chrome extension works.
- Establish a supported security-update path and assess the remaining gates in [preview status](PREVIEW-STATUS.md).
- Publish the verified archive and checksum with its exact commit/build and known limitations. Do not replace an earlier artifact while retaining its old checksum or validation claim.

## Automated checks

```sh
python3 -m unittest discover -s Tests/Release -v
```

These are mocked lifecycle tests for rejection, timeout/resume, modified submissions, Gatekeeper failure, and successful package gating. They do **not** contact Apple or prove that an actual binary is notarized.

References: [Apple notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues), [CEF code-signing guidance](https://github.com/chromiumembedded/cef/blob/master/docs/code_signing.md).
