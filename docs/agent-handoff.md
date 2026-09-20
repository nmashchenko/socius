> Historical handoff. The follow-up findings, real-app drag trace, and current validation are in [review-2026-09-20.md](review-2026-09-20.md).

# Socius handoff — 2026-09-20

## User request and ground truth

The user is handing this to a stronger/next agent. Their latest report:

> It still can't go below a specific point; Snippets is still broken. Do a full review of all committed files.

**Both bugs remain unresolved despite the previous agent reporting passing tests.** Reproduce them in the actual running development app before changing more code. Passing synthetic window tests did not establish that the user-facing issues were fixed.

Review **all committed files**, as explicitly requested, and also review the entire current uncommitted diff and untracked additions. Do not limit the review to the two known bugs. Prioritize correctness, regressions, interaction/event routing, lifecycle cleanup, performance, persistence, permissions, and release configuration. Report findings with file/line references and verification evidence. Fix authorized local issues; do not publish, push, reset data, or discard existing work.

## Workspace and runtime

- Repository: `/Users/nmashchenko/Documents/socius`; remote `nmashchenko/socius`.
- Current HEAD: `cb1c54e` — Separate development bundle identity from production TCC grants.
- Previous commits include `1ed907b` (permission flows), `a4e2b23` (skip hosted packaging for published releases), `ccaa7d6` (development storage and icon).
- Extensive working-tree changes are **not committed**. Start with `git status --short`, `git diff`, and inspect untracked files too.
- Local development app: `build/Socius.app`, bundle ID `app.socius.desktop.development`, display name Socius Dev.
- Production app: `/Applications/Socius.app`, ID `app.socius.desktop`. Preserve its data and permissions.
- Last action rebuilt and restarted the development app with `--developer`, preserving data. No new release was published during this batch.
- Build: `bash Scripts/bundle.sh` (release-optimized local development bundle, signed with Socius Local Development).
- Tests: `swift test --disable-sandbox`; native UI tests need a GUI session and may interfere with each other or the user's mouse.
- Quit dev only: `osascript -e 'tell application id "app.socius.desktop.development" to quit'`; launch `open -n /Users/nmashchenko/Documents/socius/build/Socius.app --args --developer`.
- Development data: `~/Library/Application Support/Socius/Development`. Two older reset backups exist alongside it under `Socius-Dev-Backup-20260919-225456` and `Socius-Dev-Backup-20260919-225922` in Application Support.

## Priority 1: real bottom drag boundary still wrong

User screenshot shows the pet unable to move below a horizontal boundary well above the bottom/Dock. Latest user confirms this persists after the last build.

Inspect:

- `Sources/Socius/PetPointerInput.swift`: owns mouse-down/drag/up; Quartz-to-AppKit coordinate conversion in `screenLocation(of:)` uses `NSScreen.screens.first.frame.maxY`. Check actual multi-monitor arrangements, origins, backing scales, and coordinate samples.
- `Sources/Socius/EdgeDockController.swift`: `dragPet`, `endUserDrag`, `resizeForScreen`, `repositionHome`, restore/dock geometry, and any native window constraints.
- `Sources/Socius/PetAppearance.swift`: `PetMetrics`, screen-relative sizing, sprite bounds versus transparent panel bounds.
- `Sources/Socius/SociusApp.swift`: `PetPanel.constrainFrameRect` bypasses AppKit constraints only when `petInput != nil`.
- `Sources/Socius/PetInteractionView.swift`: actual hosted layout, input region attachment, clipping and offsets.

Last attempted fix:

- Added `feetFromBottom = centerFromBottom - size / 2`.
- `PetMetrics.frame` lower Y limit now `screen.minY - feetFromBottom`, allowing transparent footer below the work area.
- `dragPet` now clamps Y between `visibleFrame.minY - feetFromBottom` and `visibleFrame.maxY - headFromBottom - 4`.
- Added geometry and native panel tests in `PetAppearanceTests`, all passed, but **did not reproduce the real failure**. The native test uses a simple `PetPointerRegion`, not the full desktop hosting tree; do not treat it as proof.

Instrument actual pointer coordinates, screen frame/visibleFrame, requested vs resulting panel frame, metrics and input attachment during a real drag. Determine whether the bound occurs during dragging, on release, or during subsequent idle travel. Do not keep tweaking constants without identifying which layer clamps it.

## Priority 2: Snippets still broken

User's earlier symptoms: move-up/down/delete sometimes do nothing; keep row-click copying; input sizes should match other panes; Enter submits. Latest request also explicitly wants Cyclop's hover/focus highlight animation and matching upstream behavior. After the last build the user still says Snippets is broken; the exact remaining symptom needs reproduction, not assumption.

Relevant files:

- `Vendor/Cyclop/Sources/UI/SnippetsPane.swift`
- `Vendor/Cyclop/Sources/UI/SnippetInput.swift`
- `Vendor/Cyclop/Sources/Services/SnippetStore.swift`
- `Sources/Socius/AnchoredPocket.swift` (native floating panel, hit region, local/global event monitors, focus)
- `Tests/CyclopToolsTests/SnippetInputTests.swift`

Upstream reference:

- https://github.com/akalikbergenov/cyclop
- Imported revision: `8d9ea04672898f651af2794d9be6289eebc658a1`.
- Local checkout: `/tmp/socius-cyclop-reference/Sources/Cyclop/UI/SnippetsPane.swift`.
- Latest fetched source: `/tmp/cyclop-snippets-latest.swift` from `main/Sources/Cyclop/UI/SnippetsPane.swift`; it matched the local reference when compared this turn.
- Cyclop uses `if hovering, !editing` for action visibility, row surface highlight, and `Theme.contentAnimation = .easeOut(duration: 0.16)`.

Attempts so far:

- Moved copy/double-click edit gestures onto the text area so action buttons are sibling targets rather than children of a gesture-bearing whole row.
- Added 26×30 action hit targets and `.allowsWindowActivationEvents()` through `SnippetActionStyle`.
- Initially made actions always visible; user requested hover reveal back. Current code restores upstream's conditional hover reveal and animation, retains larger targets and separated gestures. It is **not a byte-for-byte upstream copy**.
- Native `SnippetInput` handles Return and Escape in its delegate; fields use shared 34-point height and input fill. Focus is regular state driving native first responder.
- Store mutations persist before publishing; failed saves keep drafts and show `writeError`.
- Outer search-row tap gesture removed; native field handles focus.
- Pocket Escape handling leaves Escape to an active NSTextView editor.

Important test limitation:

- Trying to synthesize hover on the full pane failed; attempting to pump AppKit's event queue hung and was stopped.
- Current `SnippetRowActionTests` hosts `HoveredSnippetRows`, initializing row hover state to true. It verifies native move/delete click targets **only after controls are already revealed**, not the actual hover transition, window activation, or full pocket event routing.
- `SnippetRow` and its `hovering` state were made internal for this fixture. Review whether this test seam should stay.
- Do not claim the intermittent click bug is fixed based on this test. Test pointer entry, immediate action clicks, inactive-app first click, reorder under pointer, search filtering, edit/copy transitions, and pocket hit-region changes in the full running app.

## Other latest fixes needing real-app verification

### Pocket spacing after resizing

User reported changing pet size leaves the pocket too far away. `AnchoredPocket.Coordinator.show` previously returned for an existing panel without repositioning. Current code retains a positioning closure and invokes it on updates and `PocketAnchorView.layout`. Native child-window resize test passes. Verify both sides of screen and changes across the full size range, including parent-window resize ordering and screen clamping.

### Idle reminders and playground

- Found `EdgeDockController.update` called `schedule.interact` whenever **any app** held the left mouse button. That clears `nextPeek`, so a tucked pet could permanently lose reminders.
- Current fix restricts that global-click deferral to `.engaged`. `update` accepts `mouseButtons` for deterministic regression coverage. Tests now explicitly use zero for unrelated timing checks.
- Desktop reminder bubbles use `presence.reminder` in `DesktopPetView`. Confirm actual visibility/clipping near screen edges and that hover/pocket flags do not remain stuck.
- Playground used to change `PlaygroundPresence.phase` without using it in rendering. Current preview hides speech when tucked, shows a reminder when peeking, sets `shyEdge` and idle motion based on phase. "Show reminder" works from any phase. Tick holds during care or open pocket.
- Preview intentionally stays inside the stage and uses an isolated model; earlier user explicitly objected to preview drifting to its edge automatically. Verify the controls give meaningful feedback without affecting the real desktop pet.

## Broader uncommitted batch to review

The user authorized local fixes for:

- Remove quiet mode (broken; now removed, OS Reduce Motion remains).
- Reduce happiness gained per pet click to +2.
- Improve summon-hotkey UX and movement, registration rollback on failure.
- Automatic per-screen pet scaling plus size setting; four pet color presets in settings/onboarding.
- Multi-step explanatory onboarding using the real desktop pet's model.
- Sleeping pose and inward sleep bubbles.
- Screenshot watcher status/feedback and cleanup.
- Claude CLI discovery (PATH and common version-manager locations), runtime PATH, clearer failures and optional credential fallback.
- Standardized Snippets fields, Return submission and reliable actions.

Review all changed files, especially lifecycle/performance-sensitive areas:

- `CreatureView`: per-frame walking/sleep transforms moved into Canvas; Timeline cadence changed. No measured performance proof. Earlier severe lag reportedly disappeared before that rebuilt version was launched.
- `PetHotkey` and `PetModel.setShortcut`: registration replacement keeps old shortcut on failure. Avoid recursive self-assignment in observable property `didSet` (caused a crash in an earlier attempt).
- `ScreenshotFolderWatcher`: cancellation/generation checks, access failures, folder status, stop/change behavior.
- `CLIExecutableLocator`, `ClaudeCLIUsage`, `UsageService`: Claude reads succeeded locally but original detection issue was not reproduced conclusively.
- `Vendor/Cyclop/Sources/Services/Support.swift`: clean-dev-start crash fixed by using `.standard` for the app's own development bundle ID; `UserDefaults(suiteName: ownBundleID)!` had returned nil.
- Attribution docs/integration patch may need synchronization with current vendored changes.

## Preserve onboarding lifecycle fixes while reviewing

User saw two pets during onboarding, and closing/Alt-Tabbing onboarding left the pet lagging.

- `PetModel.onboardingActive` gates pocket opening.
- `PetPanel.suspendDesktopPresentation` cancels input, hides/removes child pockets, removes desktop content/input and orders panel out.
- AppDelegate attaches the desktop hosting view only outside onboarding; intro shares the same model.
- `WelcomeWindowSession` owns exact-once complete/cancel handling; panel `hidesOnDeactivate = false` prevents Alt-Tab from silently hiding it.
- Escape/native close/app hide cancel and restore desktop; only explicit completion marks onboarding seen. App reopen can replay unfinished intro; menu has Show introduction.
- `AnchoredPocket` blocks stale reopen requests during onboarding.
- Native tests cover close/cancel idempotence and blocking stale pocket presentation. Verify actual app hide/reopen, multiple displays, repeated replay, and task/window cleanup.

## Diagnostics/logging gap

User asked whether Claude/Codex connection failures are logged properly. Audit answer was **not yet**: UI errors exist, but no consistent structured diagnostic log; Codex stderr discarded; Claude terminal output temporary; discovery failures not logged. Structured safe logs and Copy diagnostics were proposed, **not implemented**. Never log tokens, credentials, raw auth files or sensitive command output.

## Validation actually performed

- Latest targeted run: **34 tests in 6 suites passed**, including PetAppearance, PetPointer, SnippetRowAction, PocketMotion, EdgeDock and Playground.
- Log: `/tmp/socius-followup-verified.log`.
- Latest local build and signature verification succeeded: `/tmp/socius-followup-build.log`.
- Earlier complete suite passed 102 tests before subsequent onboarding and follow-up changes; **not a current full-suite result**.
- Tests passing did not resolve the user's bottom-boundary and Snippets reports. Real-app reproduction is the acceptance criterion for these two issues.

## Requested next-agent outcome

1. Reproduce and fix the actual bottom drag limit and intermittent Snippets failure with evidence.
2. Verify pocket spacing, reminders and playground controls in the running dev app.
3. Fully review all committed files and the uncommitted/untracked batch; identify and address remaining material issues locally.
4. Run appropriate regressions and the full suite after the final changes, rebuild/restart dev without resetting data, and clearly distinguish automated checks from manual verification.
5. Leave publication/commits to a separate user instruction.
