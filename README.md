# Socius

A tiny pixel octopus that lives on your Mac, with a working pocket of everyday tools.

## Run

Requires macOS 15+ and Swift 6.2+ (Xcode or Command Line Tools).

```sh
bash Scripts/setup-local-signing.sh # once per development Mac
./Scripts/bundle.sh
open build/Socius.app
```

Click Mochi, then choose a tool. A transparent native host keeps the pet’s pocket stable while its visible surface changes. Hungry or grumpy pets ask for care before helping; saved data is not deleted.

## Tools

| Tool | What works | First use |
| --- | --- | --- |
| Shelf | Cyclop file cards, grouped selection/copy/drag, Quick Look thumbnails, screenshot capture, open/reveal/remove | Drop files or use Add files; choose a screenshot folder to watch |
| Clipboard | Cyclop’s latest 40 text/file entries, click to copy, delete, clear, privacy cover; copied images go to Shelf | Collects across apps by default; pause with Remember copies |
| Music | Spotify Desktop artwork, playback controls, seeking and system volume | Requires Spotify Desktop; browser integration is planned |
| Snippets | Named reusable text, search, copy, inline editing, reorder and delete | Press + |
| Notes | Autosaving scratchpad with first-line titles and separate note selection | New Note |
| AI Credits | Codex and Claude allowance windows and reset times | Automatic installed CLI access; optional Claude Keychain fallback |
| Layouts | Save positions, launch missing apps, restore available windows with progress | Allow Accessibility access, arrange apps, save a layout |

Imported tool data lives in `~/Library/Application Support/Socius/Cyclop`; Shelf references and settings also use the Socius preferences domain. Existing data imports once from `tools.json`, which is retained and still holds layouts. Clipboard history is in memory; copied images are persisted to Cyclop’s screenshot vault and added to Shelf, matching upstream. Removing a Shelf card leaves its original file untouched.

Layout restore performs Accessibility work off the main thread with bounded concurrency and short per-app timeouts. It skips minimized/full-screen windows, reports failures, and does not reopen documents or browser tabs. Unplugged displays fall back to an available screen.

AI Credits automatically uses installed Codex and Claude CLIs concurrently, with independent loading and retry controls. Codex reads account allowance through its app-server method without starting a conversation. Claude runs its built-in `/usage` in a dedicated empty directory with hooks, tools and MCP disabled, then reads the terminal screen’s session, weekly and model-specific account limits and reset labels. No model request is sent. Socius does not read Keychain credentials on this route; the CLI manages its own authentication. A 20-second timeout and cancellation terminate the helper. The terminal format is not a stable API and may require updates when Claude changes its UI. Session cost/token totals from another running Claude session are not available in this separate process. The old status-line bridge remains supported for existing integrations but is not installed automatically or used to overwrite fresh CLI limits.

If Claude CLI is missing, an explicit one-time Keychain sync is offered alongside Install CLI. Its notice explains that the token is sent only to Anthropic over HTTPS, never saved or logged, and not sent elsewhere. This is authenticated network access, not entirely local operation. Missing Codex CLI offers installation because API keys cannot report ChatGPT subscription allowances.

Developer playground includes live process memory footprint (MB, once per second), peak while open, editable idle/peek delays, a 5-second demo preset and production reset. Timing overrides live only for the current app session.

The five overlapping tools now use [Cyclop’s actual source](Vendor/Cyclop/README.md). Notes are an autosaving scratchpad; Snippets are a named reusable list. The former custom implementations are no longer used by the pocket.

## Pet interactions

- Click for a short trail of hearts and the pocket.
- Feed a pixel shrimp, find a pearl under a shell, or curl up for a nap.
- Idle tentacles ripple; sleeping uses gentle breathing and bubbles.
- **Production timings: 30 seconds to hide and 5 minutes between reminder peeks.** Mochi peeks from the nearest horizontal edge at the same height. Click to return; hovering holds its position.
- Right-click **Keep Mochi here** to disable auto-hide.
- Travel uses the screen display link targeting 60 fps. Quiet mode and macOS Reduce Motion reduce movement.
- Fullness declines over roughly 12 waking hours; spirits over 18. At 20% or lower, Mochi refuses tools. Feeding restores 45 fullness, play restores 45 spirits, and petting restores 8 spirits. Sleep pauses decay.
- Pet care state still resets on relaunch; tool data persists independently.

## Developer playground

```sh
open build/Socius.app --args --developer
```

The Interaction playground opens automatically and is also accessible from the menu-bar paw or Mochi’s context menu. Its sidebar has mood presets, neglect, care, idle, and reminder simulations. These controls affect the desktop pet. Ordinary launches omit the playground.

For a direct tool launch: `open build/Socius.app --args --tool Notes` (quit an already-running instance first). A native preview with disposable sample data can be rendered with `build/Socius.app/Contents/MacOS/Socius --render-preview --tool Notes`.

## Checks

```sh
swift test --disable-sandbox
# Optional read-only check against the signed-in Codex account:
SOCIUS_LIVE_USAGE_TEST=1 swift test --disable-sandbox --filter liveCodexUsageConnection
```

Tests cover pet interactions, display-linked travel, persistence and corrupt-file preservation, clipboard privacy/retention, screenshot ordering, usage parsing and RPC handshake, Claude settings restoration, and layout geometry. Spotify authorization/playback and Accessibility window control require manual checks on the host Mac.

Socius ships a predefined set of pocket tools. Active implementations live in `Sources/Socius` and `Vendor/Cyclop/Sources`; obsolete scaffolding has been removed.

The transparent host and in-place transition approach were informed by Cyclop’s [NotchPanel](https://github.com/akalikbergenov/cyclop/blob/main/Sources/Cyclop/Notch/NotchPanel.swift) and [Theme](https://github.com/akalikbergenov/cyclop/blob/main/Sources/Cyclop/UI/Theme.swift); Socius retains its own pet-anchored layout and visual style.

Overlapping tools directly reuse Cyclop’s MIT-licensed source. See [source attribution and integration differences](Vendor/Cyclop/README.md). Mochi artwork and pet interactions are Socius-specific.

Local builds use the persistent **Socius Local Development** code-signing identity in the login Keychain. Its certificate is trusted for code signing only. The designated requirement pins the app identifier and signing certificate, rather than the changing binary hash, so rebuilding retains the same permission identity. The transition from older ad-hoc builds may require granting Accessibility access once more. This follows [Apple’s designated-requirement guidance](https://developer.apple.com/library/archive/technotes/tn2206/). A production release should use an Apple-issued signing identity via `CODESIGN_IDENTITY`.



## Inspiration

Socius’s pocket tools are inspired by [Cyclop](https://github.com/akalikbergenov/cyclop). Shelf, clipboard, music, notes and snippets reuse its MIT-licensed implementations, adapted for Socius’s pet and pocket. See [the source attribution and integration changes](Vendor/Cyclop/README.md).

## Personalize your pet

Open **Settings** in the pocket or menu bar to name your pet, enable Quiet mode, or open a bug report on GitHub. Name, quiet mode and hidden pocket tools persist locally. Use Show in pocket to choose which built-in tools are visible. The first launch introduces your pet against a softly blurred backdrop; Skip and Escape dismiss it. After the greeting, the pet retreats to the screen edge. Later launches start idle. Developers can replay the greeting from the playground’s Replay onboarding button or with `--onboarding`.

Bring the pet to your cursor with **Control–Option–M**. Record another global combination in Settings; shortcut preferences stay on this Mac. Shortcuts require Command, Control or Option, and unavailable combinations show an error.

## Releases

See [release preparation](docs/releasing.md) for signed, notarized DMG builds and [0.1.0 beta notes](docs/releases/0.1.0-beta.1.md). Release scripts keep credentials in Keychain and do not publish automatically.
