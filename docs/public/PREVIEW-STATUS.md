# Developer preview status

Version: **0.3.0-alpha.1**. This is an early Mac developer preview, not a production or App Store release.

## Implemented

- Native sidebar, vertical tabs, saved nested folders, configurable one/two-column pins and history/archive search.
- Independent per-space Chromium profiles, themes, image/GIF backgrounds, noise/transparency controls and optional native glass.
- PIN-locked spaces with stay-unlocked and idle-time options. This is UI access protection, not full at-rest encryption.
- Arc sidebar import; separate profile import for bookmarks/history, an extension restore list, and optional supported website-cookie transfer into a fresh space.
- Same-domain new-tab chooser with a short countdown, hover pause and remembered per-domain preference.
- Downloads tray with progress and controls, tab tidy/cleanup, GitHub live-folder configuration.
- Isolated Mini control: temporary Chromium session, authenticated local commands, visible preview, take-over and stop controls.
- Sidebar drag-to-collapse after continuing more than 80 points past the 160-point minimum.

## Verified for this preview

93 core tests pass. Native QA covers sidebar collapse/reopen, core import UI, downloads controls and the Mini workflow. Cookie transfer uses synthetic fixtures and a separate Chromium harness; source data preservation, host scope, security flags, profile isolation and restart persistence have been checked.

## Still release gates

- Broad Chrome extension compatibility and real Web Store installation across representative extensions. The restore list does **not** install extensions or transfer extension storage.
- Real Meet/Teams calls, screen sharing and representative permission flows. Synthetic WebRTC/popout tests are not equivalent to live service validation.
- Real Arc Keychain/session transfer. Some logins rely on device binding or local storage and will require signing in again. Password CSV import is separate; passkeys do not transfer.
- Developer ID signing and notarization, update infrastructure, security audit, Safe Browsing integration, DRM/proprietary media compatibility and measured memory/battery performance.
- Direct Mac distribution comes first, retaining Chromium and the extension-compatibility goal. The Mac App Store is not the current release target. iOS sources are incomplete.

No claim is made that Aava is faster, lighter, safer or more compatible than Arc or Safari. Published screenshots show synthetic workspaces, not personal browsing data. GIFs are short sequences of actual native UI captures.
