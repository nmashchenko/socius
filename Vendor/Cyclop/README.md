# Socius tool source attribution

Direct source import from [akalikbergenov/cyclop](https://github.com/akalikbergenov/cyclop/tree/8d9ea04672898f651af2794d9be6289eebc658a1), revision `8d9ea04672898f651af2794d9be6289eebc658a1`. Copyright (c) 2026 akalikbergenov, MIT; see [LICENSE](LICENSE). The license is also included in the Socius app bundle.

These are the actual upstream implementations, compiled in the `CyclopTools` module, rather than independent equivalents. `upstream.json` records original file SHA-256 hashes. [integration.patch](integration.patch) records all changes to imported Swift files. `PocketAdapter.swift` is Socius integration code.

| Tool | Imported implementation |
| --- | --- |
| Shelf | ShelfStore, ShelfPane, ShelfDragSource, ScreenshotVault, ScreenshotFolderWatcher |
| Clipboard | ClipboardStore, ClipboardPane; latest 40 entries, sensitive/internal-copy exclusions, delayed Universal Clipboard images |
| Music | MediaController, PlayerBridge, NowPlayingFeed, MediaPane, original Objective-C helper |
| Snippets | SnippetStore, SnippetsPane; named reusable text, search, copy, inline edit, ordering |
| Notes | NoteStore, NotesPane, DebouncedWrite; scratch notes with autosave and first-line titles |

Shared theme, privacy controls, copy feedback, localization helpers, and skeleton views are imported too. The upstream SnippetStore test suite is included with only its module import renamed.

## Integration differences

- Socius’s transparent pocket hosts the panes; Cyclop’s notch shell and unrelated tools are not imported.
- Dark-theme foregrounds are adapted to Socius’s cream/sage palette. Layout and interaction code otherwise follows upstream, including click-to-copy rows, inline editing, and direct animated deletion instead of the old detached confirmation banner.
- Support files live in `~/Library/Application Support/Socius/Cyclop`. Preferences use Socius’s app domain. Tests and native previews use isolated data/preferences.
- The adapter adds Add files and Watch screenshots entry points, a clipboard pause switch, and file-picker suspension of the floating pocket. The core Shelf supports grouped selection and external dragging; clipboard images are saved into its screenshot vault, as in Cyclop.
- Existing Socius snippets, notes, Shelf references, watcher folder, and clipboard preference import once. Original `tools.json` is retained. Layouts remain in that original file.
- Music currently accepts Spotify Desktop sessions only. Browser and other player support are deferred. It reuses Cyclop’s helper and Spotify scripting fallback. Its private MediaRemote implementation is inherited upstream and may need maintenance with macOS releases.
- AI Credits and window layouts are Socius code; Cyclop has neither tool. Pet care, gating, idle travel, and the pocket host are Socius code.

## Verification

Run `swift test --disable-sandbox` and `./Scripts/bundle.sh`. Actual music playback, file dragging between apps, and Accessibility restore still require host interaction; passing parser/store tests is not a claim of complete UI parity or measured 60 fps.

Modified upstream files: `Services/Support.swift`, `Services/ConfigStore.swift`, `Services/ShelfStore.swift`, `Services/MediaController.swift`, `Services/ScreenshotFolderWatcher.swift`, `UI/Theme.swift`, `UI/SpoilerField.swift`, `UI/ShelfPane.swift`, `UI/SnippetsPane.swift`, `UI/NotesPane.swift`, `UI/MediaPane.swift`.

Additional Socius adaptations: Notes uses `PocketNoteEditor` (an owned NSTextView/NSScrollView) to avoid the legacy scrollbar gutter while retaining Cyclop’s NoteStore and autosave. Privacy dots use the light theme’s ink color. The Music volume control changes system output volume, rather than Spotify’s app volume. Its refreshed layout adds a playback-state bar indicator, restrained artwork scaling, and press feedback with Reduce Motion support; it does not sample audio. SnippetInput uses a native text field with a stable editing baseline. Clipboard and Snippets have shorter pocket pages. These changes are recorded in the integration patch where upstream files were modified.

Music motion inspiration: [ElevenLabs UI audio components](https://ui.elevenlabs.io/docs/components). The SwiftUI implementation is original; no ElevenLabs dependency or service is used.
