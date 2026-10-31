# Notchly

Notchly turns the MacBook notch into a small panel for music, files, your calendar, clipboard history and coding agents.
Point at the notch and it opens. Move away and it closes.

**Website:** https://suzalshrestha.github.io/notchly/ · **Download:** [latest release](https://github.com/SuzalShrestha/notchly/releases/latest)

![The open notch, Nook tab](docs/img/open-nook.png)

Notchly is an independent, MIT-licensed project inspired by [NotchNook](https://getnotchnook.com/). It is not affiliated
with NotchNook or lo.cafe. It ships none of NotchNook's images, fonts or text. Some design values (notch geometry, springs,
colors) were measured from NotchNook's app and website; the table below lists them.

## Install

1. Download `Notchly.zip` from the [latest release](https://github.com/SuzalShrestha/notchly/releases/latest) and unzip it.
2. Move `Notchly.app` to Applications.
3. The build is ad-hoc signed, not notarized. On first launch, open System Settings › Privacy & Security and click
   **Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/Notchly.app`.

Needs macOS 14 or later on Apple silicon.

## Build, test, run

```bash
./verify.sh            # release build → build/Notchly.app, self-tests, PNG snapshots in build/snapshots
./make-app.sh --run    # build and launch
```

Works with Xcode or with only the Command Line Tools. With only the Command Line Tools, the scripts use the macOS 26.5 SDK
when it is installed: the macOS 27 SDK turns `@State` into a macro whose plugin ships only with Xcode.

Launch flags: `--selftest` (assert checks for all parsers and state machines), `--snapshot <dir>` (render every notch
state and widget to PNG), `--open <tab>` (open the notch at launch), `--dock` (run as a regular app so UI-testing tools can see it).

Every push builds the app and runs the self-tests on GitHub Actions. Pushing a `v*` tag also publishes a release with `Notchly.zip`.
The website is plain HTML in [`docs/`](docs/), served by GitHub Pages.

## Design values measured from NotchNook

| Item | Value | Source |
|---|---|---|
| Notch path | bottom radius 11 → 40 pt over +100 pt height; ears ≤5 → 24 pt over +300 pt width; cubic corners k = 0.62 | `NotchShape` disassembly + website notch module |
| Open spring | response 0.48, damping 0.88 | `NotchView.openAnimation` |
| Close spring | response 0.40, damping 0.95 | `NotchView.closeAnimation` |
| Reduce Motion | easeInOut 0.2 s | same functions |
| Open speed | standard ×1, slower ×0.8, slowest ×0.65 | `NotchOpenSpeed` |
| Notchless handle | 184 × 8 pt | `generalSettings.handleSize` |
| Content padding | 12 pt | `generalSettings.contentPadding` |
| Colors | `noteBG`, `selected`, `weekendPink`, … | `Assets.car` |
| Tabs and shortcuts | nook 1 … agents 7, ⌃⌘digit | `navigationShortcutsSettings` (modifier meaning inferred) |
| Settings keys | `generalSettings`, `clipboardSettings`, `mediaWidgetSettings`, … (JSON in UserDefaults) | user defaults |
| Enum cases | widgets, live activities, clipboard filters, weather conditions, agent phases … | Swift field metadata |

## Feature coverage compared with NotchNook

| NotchNook feature | Notchly | Notes |
|---|---|---|
| Notch shell: hover open, click open, Esc, haptics, multi-display, notchless handle | yes | vertical "scrub" gesture not built |
| Navigation dock (compact / icons / dots) + ⌃⌘1–7 | yes | |
| Nook widget grid + reorder | yes | reorder in Settings, not drag-in-place edit mode |
| Widgets: media, calendar, weather, timer, to-dos, activity, AI usage, pulse, clipboard, notes, tray, volume, shortcuts, mirror, quick apps | yes (15/15) | |
| Music tab: artwork, scrubber, transport, synced lyrics (LRCLIB) | yes | Spotify + Apple Music via AppleScript; no system-wide MediaRemote source, no queue, no app volume mixer |
| Media live activity + visualizer | yes | bars are simulated, not an audio tap |
| Volume HUD | yes | shown beside the system HUD, does not replace it |
| Tray: drop, thumbnails, drag out, AirDrop, share, persist | yes | no file converter |
| Clipboard history: 7 filters, search, favorites, retention, skip passwords, excluded apps | yes | no categories |
| Calendar tab: day strip, agenda, Join links, new-event composer, upcoming-meeting activity | yes | |
| Weather (Open-Meteo) | yes | no air quality |
| Timers / Pomodoro + live activities | yes | no focus music, no rain ambience |
| Prompter: auto-scroll, speed, countdown, scripts | yes | no voice-follow mode |
| Agents: Claude Code hook bridge (unix socket), sessions, steps, alert activity | yes | hooks install only from Settings button; no approve/answer from the notch; no Codex hooks |
| AI usage (local token scan of Claude Code + Codex logs) | yes | no provider quota APIs, no USD cost |
| Battery live activity | yes | |
| Pockets, Terminal, Lock-screen widgets, Messages, Downloads, Video downloader, Bluetooth/AirPods, Liquid Glass shader, Onboarding, Sparkle updates | no | not built yet |
