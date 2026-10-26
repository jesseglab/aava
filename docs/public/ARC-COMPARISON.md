# Familiar from Arc. Different by design.

This compares Arc’s documented Mac workflows with Aava’s **0.3.0-alpha.1 developer preview**, checked 26 October 2026. It is not a benchmark or a claim of full feature parity. “Aava addition” means a capability emphasized in this implementation; absence from the cited Arc documentation is not proof that no Arc version has it.

| Area | Arc on Mac | Aava preview |
|---|---|---|
| Spaces, vertical tabs and saved folders | Core Arc workflow | Familiar native sidebar, nested folders and emoji spaces |
| Browsing identity | One profile can be assigned to multiple spaces | Every space gets its own independent profile |
| Favorites | Shared across spaces in the same profile | Per-space tiles; one or two columns, names and color tints |
| Themes | Space colors/gradients and custom tab icons | Ten presets, color wheels, image/GIF backgrounds, noise/transparency, icon styles and optional glass |
| Space access lock | Profile separation; PIN space locks are not described in the cited docs | PIN blur/lock with stay-unlocked and idle-time choices; not disk encryption |
| Small browser window | Little Arc for quick browsing | Separate, viewable Mini session designed for local AI control, with take-over and stop |
| GitHub live folders | Documented Arc feature | Configurable PR folders, repository grouping and status indicators; not claimed as a new invention |
| Tab cleanup and archive | Auto-archive and searchable archive | Tidy/clean actions, archive and history search |
| New-tab link handling | Arc offers Peek and link routing | Same-domain new-tab/replace chooser, hover-paused countdown and remembered preference; different behavior, not Peek parity |
| Chrome extensions | Documented extension commands and Chrome Web Store workflow | CEF integration and restore list; broad compatibility/install testing remains a release gate |
| Video popouts | Mini Player is documented | Capture/popout implementation; real Meet/Teams acceptance tests still pending |
| Sync and other platforms | Arc documents synced spaces/tabs and multiple platforms | Local Mac preview; no encrypted sync or released iOS app |
| Moving from Arc | Native Arc data | Spaces, pins and folders plus a separate profile-data importer; some sign-ins must be repeated |
| Memory and battery | Established browser with its own optimizations | Native shell and lazy tabs; no measured claim of superiority |

## Aava’s additions, in practical terms

**A private space can actually close its curtains.** Blur its page and sidebar until the PIN is entered, with configurable relocking. This is local access control, not a replacement for macOS disk encryption.

**AI work gets a separate browser session.** Mini’s temporary profile does not share your ordinary tabs or sign-ins. Its visible preview and take-over/stop controls make automation inspectable. A tool needs local command access; an ordinary chat interface cannot connect by itself.

**Personalization goes further than a gradient.** Give each space an image or GIF, tune noise and transparency, choose an icon style and make important favorites span two columns.

**A small decision can prevent a tab pile-up.** A same-domain link that asks for another tab can instead replace the current one, with a per-domain preference.

## Primary sources for Arc

- [Spaces](https://resources.arc.net/hc/en-us/articles/19228064149143-Spaces-Distinct-Browsing-Areas)
- [Profiles and shared identity](https://resources.arc.net/hc/en-us/articles/19227964556183-Profiles-Separate-Work-Personal-Browsing)
- [Pinned tabs and favorites](https://resources.arc.net/hc/en-us/articles/19231060187159-Pinned-Tabs-Tabs-you-want-to-stick-around)
- [Themes and custom tabs](https://start.arc.net/paint-the-internet)
- [Library and archive](https://resources.arc.net/hc/en-us/articles/19230634389911-Library-A-home-for-your-downloads-archived-tabs-easels-and-more)
- [Organize: GitHub folders, auto-archive and routing](https://resources.arc.net/hc/en-us/sections/19211839689111-Organize)
- [Commands, extensions and Little Arc](https://start.arc.net/command-bar-actions)
- [Mac release notes, Little Arc and Mini Player](https://start.arc.net/release-notes)

Aava is not affiliated with The Browser Company. Arc names are used only to explain comparison and migration.
