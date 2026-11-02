# Changelog

All notable changes to Notchly. Versions follow [semantic versioning](https://semver.org).

## Unreleased

### Added
- **A mascot for each coding agent.** Pixel characters for Claude Code, Codex and Gemini CLI replace the Claude pet. Each
  one acts out its agent: it naps, thinks, reads, types while it runs commands, waves when the agent needs you,
  celebrates when a turn finishes and sweats when a step fails.
- **Roaming mascots.** While an agent has a session, its mascot walks along the bottom of the screen and hops onto the
  tops of your windows. When the agent needs you or finishes, the mascot drops out of the notch with a speech bubble
  ("website: OK to go ahead with “Deleting files”?"). Turn it off in Settings › Agents › **Roam the screen**. Under
  Reduce Motion the mascot does not walk.
- The Agents tab shows the agent's own plan (its to-do list) as a checklist with a "2 of 4 done" count.
- Gemini CLI events (`BeforeAgent`, `BeforeTool`, `AfterTool`, `AfterAgent`) are read like Claude Code's.

### Changed
- **The Agents tab speaks plain words.** Steps read "Reading Design.swift", "Running tests", "Sharing changes" or
  "Using Github: create issue" instead of tool names such as `Bash`, `Grep` or `mcp__github__create_issue`. Each step
  has a check, a spinner or a cross. The tool mix bar is replaced by one line: steps, files changed and hiccups. The
  tool name and its input stay in the tooltip.
- A permission request names the step the agent wants to take ("OK to go ahead with “Deleting files”?").

## 1.1.0 — 2026-11-01

### Security
- Release builds use the hardened runtime, with entitlements for the camera, calendars, location and Apple Events, so
  injected code cannot borrow Notchly's permissions.
- Clipboard history also skips auto-generated items and anything copied in a known password manager, ignores text over
  1 MB, and is left out of Time Machine. The data folder is owner-only (0700, files 0600).
- The agent socket refuses other users, reads connections in parallel so a slow client cannot stall Claude's hooks,
  and keeps at most 32 sessions.
- Installing hooks writes through a symlinked `settings.json`, keeps its file mode, refuses to overwrite a change Claude
  Code made at the same moment, and shell-quotes the script path.
- Calendar **Join** opens only https (http is upgraded), Zoom and Teams links.
- Update checks only open release pages of this repository on github.com.
- Weather sends coordinates rounded to about 1 km.
- **Show notch in screenshots** is off by default for new installs, so screenshots and screen shares leave out clipboard
  history (where the capture app respects it). Existing installs keep their setting.
- Release zips get a GitHub build provenance attestation; CI actions are pinned to commit SHAs.

### Fixed
- The AI usage scanner reads transcripts instead of memory-mapping them, which could crash if a file shrank mid-scan.

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
