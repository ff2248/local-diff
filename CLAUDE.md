# CLAUDE.md

Offline macOS side-by-side text diff app. User-facing documentation is in README.md.

## Commands

```bash
swift test                  # all tests; DiffEditorTests need a logged-in GUI session
scripts/build-app.sh        # release build, assembles and ad-hoc signs build/LocalDiff.app
```

## Releasing

Publish a GitHub Release with a `vX.Y.Z` tag. `.github/workflows/release.yml` then tests, builds with that version, uploads `LocalDiff-vX.Y.Z.dmg` and its `.sha256`, and pushes the updated cask to `ff2248/homebrew-localdiff` (`Casks/localdiff.rb`) through the `HOMEBREW_TAP_DEPLOY_KEY` secret. A prerelease gets the DMG but leaves the cask alone. The version in `Resources/Info.plist` is only the default for local builds, and `scripts/build-app.sh` always builds a universal (arm64 and x86_64) binary.

## Modules

| Target | Role |
|---|---|
| `DiffCore` | Pure Swift diff engine: `computeDiff`, statistics, `alignmentPadding`. No AppKit. |
| `DiffEditor` | TextKit 1 `NSTextView` pair wrapped for SwiftUI: highlights, alignment, line-number ruler, theme |
| `LocalDiffApp` | Window, toolbar, statistics bar, debounced background diff |

`DiffCore` reports every text position as a UTF-16 `NSRange`.

## Hard constraints

- No network access: the entitlements file holds only `com.apple.security.app-sandbox`, and there are no third-party dependencies.
- Nothing is written to disk: no `UserDefaults` or `@AppStorage` for text, and window restoration stays disabled.
- Text copied out of a pane must equal what was pasted. Alignment uses paragraph spacing and `textContainerOrigin`, never inserted characters. Automatic substitutions, Writing Tools and inline predictions stay off.
- Results for typical documents (under 2,000 lines total) must not change when optimizing. Check against the existing `DiffCore` tests.
- UI copy is Traditional Chinese (Taiwan).

## Editor gotchas

- TextKit 1 ignores `paragraphSpacingBefore` on the first paragraph, so first-line padding goes through `textContainerOrigin`.
- The line-number ruler occupies the clip view's `contentInsets.left`. Programmatic scrolling must keep `contentView.bounds.origin.x`, or the text slides under the ruler.
- `NSRulerView.drawHashMarksAndLabels(in:)` is not clipped to the ruler. Fill only the ruler's own band.
- A `Comparison` applies only while both panes still hold the exact text it was computed from. Anything that reuses a stale result must check this first.
- Swap, clear and dropped files go through `DiffTextView.replaceText(with:)` so they stay undoable.
- Collapsed blocks ("show only changes") are laid out as one line fragment each: hidden glyphs become `.null`, newlines inside the block keep their control-character glyph but get `.zeroAdvancement` except the last one, and alignment measures every hidden line after the first as height 0. Nulling the newline glyphs merges the block with the next line. A paragraph style inside a block must cover the whole block, and changing paragraph styles before a block can leave a partial relayout that splits it, so `applyPadding` re-lays out every block afterwards.
- Plain-text `NSTextView` registers its drag types lazily. File drops are added in `updateDragTypeRegistration()`.

## Tests

- In `@MainActor` Swift Testing tests, work queued with `DispatchQueue.main.async` (realignment after a resize) runs only after `await Task.sleep`. Use `EditorFixture.settle()`.
- Test fixtures use made-up text only.
