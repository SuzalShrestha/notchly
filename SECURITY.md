# Security

Notchly reads sensitive things on your Mac: clipboard history, calendar events and Claude Code activity. If you find a
way for another app, user or website to read that data, change it, or run code through Notchly, please report it
privately.

## Reporting

Use [GitHub's private vulnerability reporting](https://github.com/SuzalShrestha/notchly/security/advisories/new).
Include the Notchly version, macOS version and steps to reproduce. You should get a reply within a week.

## Scope

- The agent bridge: the Unix socket at `~/Library/Application Support/Notchly/agents.sock` (mode 0600) and the hook
  script that Notchly adds to `~/.claude/settings.json`.
- Clipboard history and its image files in `~/Library/Application Support/Notchly/clipboard`.
- Network requests to Open-Meteo, LRCLIB, Spotify artwork and the GitHub releases API.

Release builds are ad-hoc signed and not notarized. Check a download against the `Notchly.zip.sha256` file attached to
each release, or build from source.
