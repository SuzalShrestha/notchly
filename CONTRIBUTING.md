# Contributing to Notchly

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Before you start

- **Bugs and ideas:** open an [issue](https://github.com/SuzalShrestha/notchly/issues/new/choose). For a larger change, open
  an issue first so we can agree on the approach before you spend time on it.
- **Security problems:** see [SECURITY.md](SECURITY.md). Please do not open a public issue.

## Build and test

You need macOS 14 or later on Apple silicon, and Xcode or the Command Line Tools.

```bash
./verify.sh            # release build → build/Notchly.app, self-tests, PNG snapshots in build/snapshots
./make-app.sh --run    # build and launch
```

- `Notchly --selftest` runs the `assert`/`precondition` checks in each feature's `selfTest()`. Run it from a debug
  build (`swift build && .build/debug/Notchly --selftest`); `-O` strips `assert`.
- `Notchly --snapshot <dir>` renders every notch state and widget to PNG, so you can review UI changes without
  screen capture. CI uploads these as the `snapshots` artifact on every push.
- `--open <tab>`, `--settings` and `--dock` help when you test by hand.

## Layout

```
Sources/Notchly/
  Core/       app delegate, notch window and shape, settings storage, design tokens, settings window, snapshots
  Features/   one file per tab or widget: model, service, views, settings pane and selfTest()
docs/         the website (plain HTML, served by GitHub Pages)
```

Settings are `Codable` structs stored as JSON in UserDefaults through `Setting`. Feature data (clipboard, tray, notes,
to-dos, timers, scripts) goes through `DataFile` into `~/Library/Application Support/Notchly`.

## Guidelines

- No third-party packages. Plain Swift, SwiftUI and AppKit keep the build simple and the app small.
- No analytics, accounts or background network calls. New network access must be opt-in and listed in the README's
  Privacy section.
- Add a `selfTest()` check for new parsers and state machines.
- Keep UI text short and plain.
- Do not copy NotchNook's images, fonts, sounds or text.

## Pull requests

1. Branch from `main`.
2. Run `./verify.sh` and try the change in the running app.
3. Update `CHANGELOG.md` under **Unreleased**, and the README or website if users will notice the change.

## Releasing (maintainers)

1. Set `CFBundleShortVersionString` (and bump `CFBundleVersion`) in `Info.plist`.
2. Move the **Unreleased** notes in `CHANGELOG.md` under the new version.
3. Tag and push: `git tag v1.2.0 && git push origin v1.2.0`. CI checks that the tag matches `Info.plist`, then
   publishes `Notchly.zip` and its SHA-256 checksum.
