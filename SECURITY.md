# Security

Aava is an early developer preview. It has not received an independent browser security audit, production update infrastructure, or a verified Safe Browsing integration. Do not describe it as a hardened daily-driver browser.

Please do not post credentials, cookie databases, tokens, PINs, browsing profiles or sensitive reproduction details in public issues. Use [GitHub private vulnerability reporting](https://github.com/jesseglab/aava/security/advisories/new), which is enabled for this repository.

Spaces use independent Chromium request contexts. PIN locking is a local UI access control, not a claim of full disk encryption. Mini control uses a separate temporary profile and an authenticated local socket; it does not expose ordinary browser profiles. Imported sessions are explicitly selected and placed into a fresh profile.

CEF/Chromium security updates must be reviewed and delivered through new builds. The initial preview has no automatic updater. The current engine is pinned in `Apps/macOS/cef-version.json`.
