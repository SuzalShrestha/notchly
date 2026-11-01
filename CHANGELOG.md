# Changelog

All notable changes to Notchly. Versions follow [semantic versioning](https://semver.org).

## Unreleased

### Added
- **Claude pet** in the Agents tab and beside the closed notch. It naps when nothing runs, thinks, works with a prop for
  each tool (reading, editing, running commands, searching, browsing), waves when Claude needs you, celebrates when a turn
  finishes and sweats when a tool fails. Turn it off in Settings › Agents. It stays still under Reduce Motion.
- **Agents tab, Focus layout** (new default): a pet card with what the agent is doing in words, tools used, files
  changed and elapsed time; a switcher between sessions; an attention banner with **Go to Terminal**; a timeline of
  every step with its folder and duration; and a bar showing the mix of tools this turn. Grid and List remain.
- Agent sessions record the full prompt, turn count, per-step durations, files changed and failed tools. The context
  menu can copy the prompt, reveal the project in Finder, go to the terminal and clear finished sessions.
- The Agents tab can connect Claude Code itself when no hooks are installed.
- The Agents tab icon shows a badge while a session needs you.
- **Welcome tour** on first launch: five short pages with illustrations that pick your Nook widgets, connect Claude Code
  and set launch at login. Open it again from the menu bar (**Welcome Tour…**) or Settings › About.
- Design system: spacing and radius scales, semantic colors, hairline card edges, and shared button, key cap and
  status dot components.
- **Check for Updates…** in the menu bar menu and in Settings › About. It asks GitHub only when you click.
- Settings › About shows the version and links to the website, source and issue tracker.
- Opening Notchly again (Finder, Spotlight, Launchpad) while it runs shows Settings.
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
- Closed-notch agent activities no longer rebuild on every tool call; their views follow the session store directly.
- Music's level bars stop redrawing while playback is paused.
- The navigation dock's selection slides between tabs.
- Removed the microphone, speech and Downloads permission texts. No feature uses them yet.
- LRCLIB requests name Notchly and its version in the User-Agent, as LRCLIB asks.
- CI builds every branch, uploads notch snapshots, and publishes releases from a separate job. A release tag must match the version in `Info.plist`.

## 1.0.0 — 2026-10-31

First public release: notch shell with hover and click open, Nook widget grid (15 widgets), Music with synced lyrics,
Calendar, Tray, Prompter, Clipboard history, Agents (Claude Code hooks), AI usage, live activities and a settings window.
