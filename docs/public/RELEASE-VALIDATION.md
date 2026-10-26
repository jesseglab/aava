# Release validation record

Checkpoint: 2026-10-26. Native validation covers the release workflow at `74104f4` plus the extension lifecycle changes described below. macOS 27.0, Apple Silicon, CEF 156.0.14 / Chromium 156.0.8078.48.

This is an incomplete validation record, not release approval. Tests use a separate **Aava Validation** app and fresh profiles; ordinary browsing profiles are not copied or changed.

| Check | Observed result | Remaining work |
|---|---|---|
| Hardened runtime / distribution signing | Geeklab Developer ID Application certificate issued and installed. Aava 0.3.0 build 6 and nested code pass strict distribution-signature, secure-timestamp and hardened-runtime checks. | Apple acceptance, stapling and Gatekeeper validation remain separate gates. |
| Distribution identity gate | Development identities are rejected before distribution signing. The installed Geeklab Developer ID identity passed the team check. | Retain the private key in Keychain; it was not exported. |
| Apple notarization | No real submission made. The intended local credential profile is not configured. | Configure credentials, submit, obtain Accepted result, staple, verify Gatekeeper and extracted archive. |
| Web Store / Dark Reader | Dark Reader 4.9.133 installed from the official Chrome Web Store with user-approved all-site access. Installation survives process restart. A light-only fixture is white with the extension disabled and dark when enabled. Extension options render. A separate fresh space has an empty extensions manager. Incognito and file-URL access remain off. | Verify toolbar action targets the current native tab, settings persistence, updates, and representative additional extensions. These observations do not establish universal Chrome compatibility. |
| Google Meet | Official Google sign-in page loads in its fresh space. | Test-account sign-in, real call, audio/video, sharing, popout and return, reconnect, end call. |
| Microsoft Teams | Official Microsoft sign-in page loads in its fresh space. | Test-account sign-in, real call, audio/video, sharing, popout and return, reconnect, end call. |
| Release workflow tests | Five mocked safety-gate tests pass; Python scripts compile. | These tests do not constitute Apple acceptance or live-service validation. |

## Extension lifecycle fixes

Extension package downloads now defer to Chromium's normal handling instead of Aava's generic Save file drawer. Chromium retains installation prompts and security checks. The previous drawer flow did install Dark Reader; this change removes an unnecessary download interception, not a claimed universal installation failure.

A repeatable Quit hang was observed in the isolated validation app. CEF's `GetDefaultClient` contract warns that Chrome-created windows without a client are unmanaged and block shutdown. Aava now supplies a fresh tracked client for those windows, including extension-created pages, and closes late-created windows during shutdown. Regression validation passed in the Developer ID-signed build 6: open Dark Reader options, open its Help page in a Chromium-created window, use Quit Aava, confirm the app process exits, and relaunch successfully. This does not cover every extension or unsaved-form shutdown scenario.

## Live test protocol

For each extension, record the publisher, version, install source, requested permissions, install outcome, actual feature behavior, action/settings UI, relaunch persistence, and absence from another fresh space. Test a representative content-script extension, Manifest V3 network blocker, and password-manager workflow. Native messaging and Chrome window/tab mapping require separate checks; Aava's native host arrangement can differ from Chrome.

For each meeting service, use test accounts and a second endpoint. Check two-way audio/video, mute/camera toggles, screen-sharing selection and stop, automatic popout when leaving the call tab, return to the call, switching spaces, network recovery, and ending capture. Confirm capture never silently begins in another space and that stopped calls do not remain marked active. A loaded login page, self-preview, or synthetic WebRTC fixture is not a passing two-way call.

No passwords, session cookies, meeting links, account identifiers, or private participant screenshots belong in this public record. Retain sanitized evidence and the exact signed artifact checksum when validation completes.
