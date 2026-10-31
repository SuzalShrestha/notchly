# Changelog

All notable changes to Notchly. Versions follow [semantic versioning](https://semver.org).

## Unreleased

### Added
- **Check for Updates…** in the menu bar menu and in Settings › About. It asks GitHub only when you click.
- Settings › About shows the version and links to the website, source and issue tracker.
- Opening Notchly again (Finder, Spotlight, Launchpad) while it runs shows Settings.
- First launch opens Settings with a short welcome, so it is clear the app is running.
- Website: FAQ, link previews for social sites, and an accurate list of network calls.
- Contributing guide, security policy, issue and pull request templates.
- The menu bar menu links to the website and to the issue tracker.
- Releases include a SHA-256 checksum.

### Fixed
- Turning off navigation shortcuts now releases ⌃⌘1–7 so other apps can use them.
- Launch at login shows errors and the "needs approval" state instead of failing silently.
- Display settings (which screens, notch fine-tune, screenshots) apply right away.
- A second running copy of Notchly no longer stacks a second notch or takes over the agent socket.
- Seeking in Music keeps sub-second precision.
- Prompter scripts save after you stop typing instead of on every keystroke.
- `make-app.sh` stops when the build fails instead of packaging an older binary.
- External tools run by Notchly (Shortcuts) can no longer hang on a full stderr pipe.

### Changed
- Removed the microphone, speech and Downloads permission texts. No feature uses them yet.
- LRCLIB requests name Notchly and its version in the User-Agent, as LRCLIB asks.
- CI builds every branch, uploads notch snapshots, and publishes releases from a separate job. A release tag must match the version in `Info.plist`.

## 1.0.0 — 2026-10-31

First public release: notch shell with hover and click open, Nook widget grid (15 widgets), Music with synced lyrics,
Calendar, Tray, Prompter, Clipboard history, Agents (Claude Code hooks), AI usage, live activities and a settings window.
