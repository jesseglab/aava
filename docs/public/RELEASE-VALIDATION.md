# Release validation record

Checkpoint: 2026-10-26. Native app built from `bc2fed5`, with the hardened-signing workflow introduced after that commit. macOS 27.0, Apple Silicon, CEF 156.0.14 / Chromium 156.0.8078.48.

This is an incomplete validation record, not release approval. Tests use a separate **Aava Validation** app and fresh profiles; ordinary browsing profiles are not copied or changed.

| Check | Observed result | Remaining work |
|---|---|---|
| Hardened runtime | Development-signed app and nested helpers pass strict signature checks; app launches and renders sites. Secure timestamps verified. | Repeat using the publishing team's Developer ID certificate. |
| Distribution identity gate | An Apple Development identity is rejected for distribution before signing mutations. | Install and verify Developer ID Application identity for the publishing team. |
| Apple notarization | No real submission made. | Configure credentials, submit, obtain Accepted result, staple, verify Gatekeeper and extracted archive. |
| Web Store / Dark Reader | Official listing loads. Add to Chrome reaches the native installation prompt for Dark Reader 4.9.133. | Approve requested all-site access, complete installation, verify rendering, action popup, persistence, and space isolation. |
| Google Meet | Official Google sign-in page loads in its fresh space. | Test-account sign-in, real call, audio/video, sharing, popout and return, reconnect, end call. |
| Microsoft Teams | Official Microsoft sign-in page loads in its fresh space. | Test-account sign-in, real call, audio/video, sharing, popout and return, reconnect, end call. |
| Release workflow tests | Five mocked safety-gate tests pass; Python scripts compile. | These tests do not constitute Apple acceptance or live-service validation. |

## Live test protocol

For each extension, record the publisher, version, install source, requested permissions, install outcome, actual feature behavior, action/settings UI, relaunch persistence, and absence from another fresh space. Test a representative content-script extension, Manifest V3 network blocker, and password-manager workflow. Native messaging and Chrome window/tab mapping require separate checks; Aava's native host arrangement can differ from Chrome.

For each meeting service, use test accounts and a second endpoint. Check two-way audio/video, mute/camera toggles, screen-sharing selection and stop, automatic popout when leaving the call tab, return to the call, switching spaces, network recovery, and ending capture. Confirm capture never silently begins in another space and that stopped calls do not remain marked active. A loaded login page, self-preview, or synthetic WebRTC fixture is not a passing two-way call.

No passwords, session cookies, meeting links, account identifiers, or private participant screenshots belong in this public record. Retain sanitized evidence and the exact signed artifact checksum when validation completes.
