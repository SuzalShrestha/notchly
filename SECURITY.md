# Security

Notchly reads sensitive things on your Mac: clipboard history, calendar events and Claude Code activity. If you find a
way for another app, user or website to read that data, change it, or run code through Notchly, please report it
privately.

## Reporting

Use [GitHub's private vulnerability reporting](https://github.com/SuzalShrestha/notchly/security/advisories/new).
Include the Notchly version, macOS version and steps to reproduce. You should get a reply within a week.

## Scope

- The agent bridge: the Unix socket at `~/Library/Application Support/Notchly/agents.sock` (mode 0600; connections
  from other users are refused) and the hook script that Notchly adds to `~/.claude/settings.json`.
- Clipboard history and its image files in `~/Library/Application Support/Notchly/clipboard`.
- Network requests to Open-Meteo, LRCLIB, Spotify artwork and the GitHub releases API.

## What Notchly protects, and what it cannot

- The data folder `~/Library/Application Support/Notchly` is owner-only (0700) and its files 0600. Clipboard history is
  left out of Time Machine.
- Clipboard history skips items marked concealed, transient or auto-generated, and anything copied in a known password
  manager, while **Skip passwords** is on. Anything else you copy (for example an API key in a terminal) is kept as plain
  text for the retention period. Add apps to the excluded list, or shorten retention, if that matters to you.
- The app runs with the hardened runtime, so other programs cannot inject code into it to borrow its Calendar, Camera,
  Location or Automation permissions.
- Unless you turn on **Show notch in screenshots**, Notchly asks macOS to leave the notch out of screenshots,
  recordings and screen sharing. Some capture apps on recent macOS ignore that request, so close the notch before you
  share your screen.
- Not in scope: a program already running as your user account. It can reach the agent socket and send fake agent
  events, and it can read Notchly's files, just as it can read the rest of your home folder. Reports that need this
  are still welcome when Notchly makes it easier than it would be otherwise.

## Verifying a download

Release builds are ad-hoc signed and not notarized. Each release zip has a build provenance attestation signed by
GitHub; check it with `gh attestation verify Notchly.zip --repo SuzalShrestha/notchly` before allowing the app in
Privacy & Security. The `Notchly.zip.sha256` file next to it only catches a broken download. Or build from source.
