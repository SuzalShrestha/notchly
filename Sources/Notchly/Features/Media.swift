import AppKit
import CoreAudio
import AudioToolbox
import SwiftUI

// MARK: - Settings (same key names as NotchNook)

/// Same cases as NotchNook's MediaSource. `systemWide` here means "whichever player is active".
enum MediaSource: String, Codable, CaseIterable {
    case appleMusic, spotify, systemWide
    var title: String { switch self { case .appleMusic: "Apple Music"; case .spotify: "Spotify"; case .systemWide: "Automatic" } }
    var appName: String { self == .spotify ? "Spotify" : "Music" }
    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
}

struct MediaWidgetSettings: Codable, Equatable {
    var showLyrics = true
    var showPlaybackProgress = false
    var preferredSource: MediaSource = .systemWide
}

struct MediaLiveActivitySettings: Codable, Equatable {
    var isAutomaticallyColored = true
    var albumCornerRadius: Double = 5
    var showVisualizer = true
}

struct VolumeWidgetSettings: Codable, Equatable {
    var showsOutput = true
}

@MainActor
enum MediaFeature {
    static let settings = Setting("mediaWidgetSettings", default: MediaWidgetSettings())
    static let activitySettings = Setting("mediaLiveActivitySettings", default: MediaLiveActivitySettings())
    static let volumeSettings = Setting("volumeWidgetSettings", default: VolumeWidgetSettings())

    static func start() {
        MediaService.shared.start()
        VolumeService.shared.start()
    }

    static func selfTest() {
        let lrc = """
        [ar:Someone]
        [ti:Song]
        [00:12.50] First line
        [00:05.00][01:02.25]Chorus
        [00:20.00]
        not a lyric
        """
        let lines = LRCLIBLyricsProvider.parse(lrc)
        assert(lines.map(\.time) == [5, 12.5, 20, 62.25], "lrc times \(lines.map(\.time))")
        assert(lines.map(\.text) == ["Chorus", "First line", "", "Chorus"], "lrc text")
        assert(LRCLIBLyricsProvider.parse("[00:01:50]x").first?.time == 1.5, "mm:ss:xx form")
        assert(LRCLIBLyricsProvider.parse("").isEmpty)
        assert(LyricLine.index(in: lines, at: 4) == nil)
        assert(LyricLine.index(in: lines, at: 13) == 1)
        assert(LyricLine.index(in: lines, at: 999) == 3)

        let p = NowPlaying(parsing: "playing\tSong\tArtist\tAlbum\t201,5\t12.25\tid1\thttps://x/y.jpg", source: .spotify)
        assert(p?.isPlaying == true && p?.duration == 201.5 && p?.elapsed == 12.25 && p?.artworkURL == "https://x/y.jpg", "status parse")
        assert(NowPlaying(parsing: "", source: .appleMusic) == nil)
        assert(NowPlaying(parsing: "paused\tA\tB\tC\t10\t1\tid\t", source: .appleMusic)?.isPlaying == false)

        let red = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        let c = MediaService.averageColor(red).usingColorSpace(.sRGB)!
        assert(c.redComponent > 0.9 && c.greenComponent < 0.2 && c.blueComponent < 0.2, "average color \(c)")
    }
}

// MARK: - Now playing

struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsed: TimeInterval
    var isPlaying: Bool
    var source: MediaSource
    var trackID: String
    var artworkURL: String

    /// Parses the tab-separated line returned by `MediaService.statusScript`.
    init?(parsing line: String, source: MediaSource) {
        let f = line.components(separatedBy: "\t")
        guard f.count >= 8, f[0] != "stopped" else { return nil }
        // AppleScript formats reals with the locale's decimal separator.
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        title = f[1]; artist = f[2]; album = f[3]
        duration = num(f[4]); elapsed = num(f[5])
        isPlaying = f[0] == "playing"
        self.source = source
        trackID = f[6]; artworkURL = f[7]
    }
}

// ponytail: Apple Music and Spotify only, polled through AppleScript once per second. The original reaches
// MediaRemote (system-wide: browsers, Podcasts, …) through a perl adapter; add that if other sources matter.
@MainActor @Observable
final class MediaService {
    static let shared = MediaService()

    private(set) var track: NowPlaying?
    private(set) var artwork: NSImage?
    private(set) var tint = Color.white
    private(set) var lyrics: LyricsLookupResult?
    private var anchor = Date()

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var polling = false
    @ObservationIgnored private var lyricsCache: [String: LyricsLookupResult] = [:]
    /// NSAppleScript is not thread safe: every script runs on this one serial queue.
    nonisolated private static let queue = DispatchQueue(label: "notchly.media.applescript")

    func start() {
        guard timer == nil else { return }
        var tick = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                // Every second while playing (elapsed is extrapolated anyway), every 3 s otherwise.
                tick += 1
                if MediaService.shared.track?.isPlaying == true || tick % 3 == 0 { MediaService.shared.poll() }
            }
        }
        timer?.tolerance = 0.3
        poll()
    }

    func elapsed(at date: Date) -> TimeInterval {
        guard let t = track else { return 0 }
        let e = t.elapsed + (t.isPlaying ? date.timeIntervalSince(anchor) : 0)
        return t.duration > 0 ? min(e, t.duration) : e
    }

    // MARK: Controls

    func playPause() { send("playpause"); track?.isPlaying.toggle(); anchor = Date() }
    func next() { send("next track") }
    func previous() { send("previous track") }
    func seek(to time: TimeInterval) {
        // AppleScript reads "12.5" in every locale; keep sub-second precision.
        send("set player position to \(String(format: "%.2f", max(0, time)))")
        track?.elapsed = time; anchor = Date()
    }

    private func send(_ command: String) {
        guard let s = track?.source else { return }
        let src = "if application \"\(s.appName)\" is running then tell application \"\(s.appName)\" to \(command)"
        Self.queue.async {
            _ = Shell.appleScript(src)
            Task { @MainActor in MediaService.shared.poll() }
        }
    }

    // MARK: Polling

    private func poll() {
        guard !polling else { return }
        // Never script an app that is not running: `tell application` would launch it.
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let sources = [MediaSource.spotify, .appleMusic].filter { running.contains($0.bundleID) }
        guard !sources.isEmpty else { apply(nil); return }
        let preferred = MediaFeature.settings.value.preferredSource
        polling = true
        Self.queue.async {
            let found = sources.compactMap { s in Shell.appleScript(Self.statusScript(s)).flatMap { NowPlaying(parsing: $0, source: s) } }
            let pick = found.first { $0.isPlaying } ?? found.first { $0.source == preferred } ?? found.first
            Task { @MainActor in
                let me = MediaService.shared
                me.polling = false
                me.apply(pick)
            }
        }
    }

    private func apply(_ new: NowPlaying?) {
        let changed = new?.trackID != track?.trackID || new?.source != track?.source
        if new != track { track = new; anchor = Date() }
        if changed {
            artwork = nil; tint = .white; lyrics = nil
            if let new { loadArtwork(new); loadLyrics(new) }
        }
        updateLiveActivity()
    }

    private func updateLiveActivity() {
        let center = LiveActivityCenter.shared
        guard track?.isPlaying == true else { center.remove(.media); return }
        guard center.activities[.media] == nil else { return }   // the views observe this service
        center.show(LiveActivity(kind: .media, priority: 10, leadingWidth: 24, trailingWidth: 24,
                                 leading: AnyView(MediaActivityArt()), trailing: AnyView(AudioBars())))
    }

    nonisolated private static func statusScript(_ s: MediaSource) -> String {
        let duration = s == .spotify ? "((duration of t) / 1000)" : "(duration of t)"
        let id = s == .spotify ? "(id of t)" : "(persistent ID of t)"
        let art = s == .spotify ? "(artwork url of t)" : "\"\""
        return """
        if application "\(s.appName)" is running then
            tell application "\(s.appName)"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as text) & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & \(duration) & tab & player position & tab & \(id) & tab & \(art)
            end tell
        end if
        return "stopped"
        """
    }

    // MARK: Artwork (only on track change)

    private func loadArtwork(_ t: NowPlaying) {
        let id = t.trackID
        let set: @Sendable (NSImage?) -> Void = { img in
            Task { @MainActor in
                let me = MediaService.shared
                guard let img, me.track?.trackID == id else { return }
                me.artwork = img
                me.tint = Color(nsColor: MediaService.vivid(MediaService.averageColor(img)))
            }
        }
        if t.source == .spotify, let url = URL(string: t.artworkURL), url.scheme == "https" {
            Task.detached { set((try? await URLSession.shared.data(from: url)).flatMap { NSImage(data: $0.0) }) }
        } else if t.source == .appleMusic {
            // Raw bytes straight from the Apple Event descriptor; no temp file needed.
            Self.queue.async {
                let src = "if application \"Music\" is running then tell application \"Music\" to return raw data of artwork 1 of current track"
                var err: NSDictionary?
                let data = NSAppleScript(source: src)?.executeAndReturnError(&err).data
                set(err == nil ? data.flatMap(NSImage.init(data:)) : nil)
            }
        }
    }

    nonisolated static func averageColor(_ img: NSImage) -> NSColor {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.interpolationQuality = .medium
            ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
    }

    /// Album averages are muddy; lift brightness so bars read on black.
    nonisolated static func vivid(_ c: NSColor) -> NSColor {
        guard let c = c.usingColorSpace(.sRGB) else { return .white }
        return NSColor(hue: c.hueComponent, saturation: min(c.saturationComponent * 1.3, 1), brightness: max(c.brightnessComponent, 0.8), alpha: 1)
    }

    // MARK: Lyrics

    private func loadLyrics(_ t: NowPlaying) {
        guard MediaFeature.settings.value.showLyrics, !t.title.isEmpty else { return }
        let key = "\(t.artist)|\(t.title)"
        if let cached = lyricsCache[key] { lyrics = cached; return }
        Task {
            for delay in [0, 5, 30] {
                try? await Task.sleep(for: .seconds(delay))
                guard track?.trackID == t.trackID else { return }
                if let result = await LRCLIBLyricsProvider.lookup(t) {
                    lyricsCache[key] = result
                    if track?.trackID == t.trackID { lyrics = result }
                    return
                }
            }
            if track?.trackID == t.trackID { lyrics = .notFound }   // offline or server busy; not cached
        }
    }
}

// MARK: - Lyrics (LRCLIB)

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String

    /// Index of the line being sung at `time`, nil before the first line.
    static func index(in lines: [LyricLine], at time: TimeInterval) -> Int? { lines.lastIndex { $0.time <= time } }
}

enum LyricsLookupResult: Equatable {
    case synced([LyricLine]), instrumental, notFound
}

enum LRCLIBLyricsProvider {
    struct Record: Decodable {
        var trackName: String?
        var artistName: String?
        var albumName: String?
        var duration: Double?
        var instrumental: Bool?
        var syncedLyrics: String?
    }

    /// nil means a transient failure (offline, 5xx) that should not be cached.
    static func lookup(_ t: NowPlaying) async -> LyricsLookupResult? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [
            URLQueryItem(name: "track_name", value: t.title),
            URLQueryItem(name: "artist_name", value: t.artist),
            URLQueryItem(name: "album_name", value: t.album),
            URLQueryItem(name: "duration", value: String(Int(t.duration.rounded()))),
        ]
        guard let url = c.url else { return .notFound }
        var req = URLRequest(url: url)
        req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return .notFound }
        guard http.statusCode == 200, let r = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
        if r.instrumental == true { return .instrumental }
        let lines = parse(r.syncedLyrics ?? "")
        return lines.isEmpty ? .notFound : .synced(lines)
    }

    /// LRC: `[mm:ss.xx]text`, several stamps per line allowed; metadata tags like `[ar:…]` are skipped.
    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]"), let t = stamp(rest[rest.index(after: rest.startIndex)..<close]) {
                times.append(t)
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            out += times.map { LyricLine(time: $0, text: text) }
        }
        return out.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
    }

    private static func stamp(_ tag: Substring) -> TimeInterval? {
        let p = tag.split(separator: ":").map { Double($0) }
        guard p.count >= 2, p.count <= 3, !p.contains(nil) else { return nil }
        return p[0]! * 60 + p[1]! + (p.count == 3 ? p[2]! / 100 : 0)
    }
}

// MARK: - Shared views

private struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Theme.chip
                    Image(systemName: "music.note").font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Capsule track with a drag-to-set fill. `onCommit` fires when the drag ends.
struct CapsuleSlider: View {
    var value: Double
    var height: CGFloat = 6
    var tint: Color = .white
    var onChange: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void = { _ in }
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Color.white.opacity(0.15)
                tint.frame(width: g.size.width * min(max(dragValue ?? value, 0), 1))
            }
            .frame(height: dragValue == nil ? height : height + 2)
            .clipShape(Capsule())
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { d in
                    let v = min(max(d.location.x / max(g.size.width, 1), 0), 1)
                    dragValue = v
                    onChange(v)
                }
                .onEnded { _ in
                    if let v = dragValue { onCommit(v) }
                    dragValue = nil
                })
            .animation(Motion.snappy, value: dragValue == nil)
        }
        .frame(height: 16)
    }
}

private struct Transport: View {
    var size: CGFloat = 32
    var body: some View {
        let m = MediaService.shared
        HStack(spacing: 10) {
            RoundButton(symbol: "backward.fill", size: size) { m.previous() }
            RoundButton(symbol: m.track?.isPlaying == true ? "pause.fill" : "play.fill", size: size + 6, tint: .black, fill: .white) { m.playPause() }
            RoundButton(symbol: "forward.fill", size: size) { m.next() }
        }
    }
}

private struct SourceChip: View {
    let source: MediaSource
    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID)
        Button { if let url { NSWorkspace.shared.openApplication(at: url, configuration: .init()) } } label: {
            HStack(spacing: 5) {
                if let url { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 14, height: 14) }
                Text(source.title)
            }
            .font(Theme.caption.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.chip, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

private func clock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t.rounded(.down)))
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Music tab (560 × 156)

struct MusicView: View {
    var body: some View {
        let m = MediaService.shared
        let s = MediaFeature.settings.value
        if let t = m.track {
            HStack(spacing: 14) {
                Artwork(image: m.artwork, size: 156, radius: 14)
                VStack(alignment: .leading, spacing: 0) {
                    SourceChip(source: t.source)
                    Spacer(minLength: 6)
                    Text(t.title.isEmpty ? "Unknown" : t.title).font(Theme.title(16)).lineLimit(1)
                    Text(t.artist).font(Theme.body).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    Spacer(minLength: 6)
                    Scrubber(track: t)
                    Transport(size: 30).frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if s.showLyrics { LyricsColumn().frame(width: 170) }
            }
        } else {
            EmptyState(symbol: "music.note", title: "Nothing playing", subtitle: "Play something in Music or Spotify.")
        }
    }
}

private struct Scrubber: View {
    let track: NowPlaying
    @State private var preview: Double?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let elapsed = preview.map { $0 * track.duration } ?? MediaService.shared.elapsed(at: ctx.date)
            VStack(spacing: 0) {
                CapsuleSlider(value: track.duration > 0 ? elapsed / track.duration : 0, height: 5,
                              onChange: { preview = $0 },
                              onCommit: { MediaService.shared.seek(to: $0 * track.duration); preview = nil })
                HStack {
                    Text(clock(elapsed))
                    Spacer()
                    Text("-" + clock(track.duration - elapsed))
                }
                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}

private struct LyricsColumn: View {
    var body: some View {
        let m = MediaService.shared
        Group {
            switch m.lyrics {
            case .synced(let lines):
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                    let i = LyricLine.index(in: lines, at: m.elapsed(at: ctx.date) + 0.2)
                    let current = i.map { lines[$0].text } ?? "♪"
                    let next = lines.indices.contains((i ?? -1) + 1) ? lines[(i ?? -1) + 1].text : ""
                    VStack(alignment: .leading, spacing: 6) {
                        Text(current.isEmpty ? "♪" : current).font(Theme.title(14)).foregroundStyle(.white)
                        Text(next).font(Theme.body).foregroundStyle(Theme.tertiaryText)
                    }
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .id(i ?? -1)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                    .animation(Motion.snappy, value: i)
                }
            case .instrumental: note("Instrumental")
            case .notFound: note("No synced lyrics")
            case nil: note(m.track?.title.isEmpty == false ? "Looking for lyrics…" : "")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.widgetRadius, style: .continuous))
    }

    private func note(_ s: String) -> some View {
        Text(s).font(Theme.caption).foregroundStyle(Theme.tertiaryText).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Nook media widget (5 units ≈ 200 × 156)

struct MediaWidget: View {
    var body: some View {
        let m = MediaService.shared
        WidgetCard {
            if let t = m.track {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Artwork(image: m.artwork, size: 56, radius: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title.isEmpty ? "Unknown" : t.title).font(Theme.title(13)).lineLimit(2)
                            Text(t.artist).font(Theme.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if MediaFeature.settings.value.showPlaybackProgress {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            CapsuleSlider(value: t.duration > 0 ? m.elapsed(at: ctx.date) / t.duration : 0, height: 4,
                                          onCommit: { m.seek(to: $0 * t.duration) })
                        }
                    }
                    Transport(size: 30).frame(maxWidth: .infinity)
                }
                .foregroundStyle(.white)
            } else {
                EmptyState(symbol: "music.note", title: "Not playing")
            }
        }
    }
}

// MARK: - Media live activity (closed-notch wings)

private struct MediaActivityArt: View {
    var body: some View {
        Artwork(image: MediaService.shared.artwork, size: 20, radius: MediaFeature.activitySettings.value.albumCornerRadius)
    }
}

/// ponytail: fake level bars (sine mix), not real audio. The original taps the output with a CoreAudio process tap.
private struct AudioBars: View {
    private static let speeds: [Double] = [7.1, 9.3, 6.2, 8.4]
    var body: some View {
        let s = MediaFeature.activitySettings.value
        let tint = s.isAutomaticallyColored ? MediaService.shared.tint : .white
        if s.showVisualizer {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        let a = sin(t * Self.speeds[i] + Double(i) * 1.7), b = sin(t * Self.speeds[3 - i] * 0.53)
                        Capsule().fill(tint).frame(width: 3, height: 4 + 12 * (a * 0.6 + b * 0.4 + 1) / 2)
                    }
                }
                .frame(height: 16)
            }
        } else {
            Image(systemName: "waveform").font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
        }
    }
}

// MARK: - Volume (CoreAudio default output)

struct AudioOutputDevice: Equatable {
    enum Kind: String { case builtIn, headphones, bluetooth, airPlay, display, external }
    var name = ""
    var kind = Kind.builtIn
    var symbol: String {
        switch kind {
        case .builtIn: "laptopcomputer"
        case .headphones, .bluetooth: "headphones"
        case .airPlay: "airplay.audio"
        case .display: "tv"
        case .external: "hifispeaker"
        }
    }
}

// Plain C callbacks (no captures) so the same pointer can be removed again.
private let volumeChanged: AudioObjectPropertyListenerProc = { _, _, _, _ in
    Task { @MainActor in VolumeService.shared.refresh(showHUD: true) }
    return noErr
}
private let defaultDeviceChanged: AudioObjectPropertyListenerProc = { _, _, _, _ in
    Task { @MainActor in VolumeService.shared.attach() }
    return noErr
}

@MainActor @Observable
final class VolumeService {
    static let shared = VolumeService()

    private(set) var volume: Float = 0
    private(set) var isMuted = false
    private(set) var device = AudioOutputDevice()
    @ObservationIgnored private var deviceID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var ownChangeUntil = Date.distantPast
    @ObservationIgnored private var started = false

    private static let watched = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute]

    var symbol: String {
        if isMuted || volume == 0 { return "speaker.slash.fill" }
        return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    func start() {
        guard !started else { return }
        started = true
        var a = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &a, defaultDeviceChanged, nil)
        attach()
    }

    func attach() {
        for sel in Self.watched where deviceID != kAudioObjectUnknown {
            var a = Self.address(sel)
            AudioObjectRemovePropertyListener(deviceID, &a, volumeChanged, nil)
        }
        deviceID = Self.get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                            scope: kAudioObjectPropertyScopeGlobal, AudioObjectID(kAudioObjectUnknown)) ?? AudioObjectID(kAudioObjectUnknown)
        guard deviceID != kAudioObjectUnknown else { return }
        for sel in Self.watched {
            var a = Self.address(sel)
            AudioObjectAddPropertyListener(deviceID, &a, volumeChanged, nil)
        }
        let name = Self.get(deviceID, kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal, Unmanaged<CFString>?.none)??
            .takeRetainedValue() as String? ?? "Output"
        let transport = Self.get(deviceID, kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal, UInt32(0)) ?? 0
        let source = Self.get(deviceID, kAudioDevicePropertyDataSource, UInt32(0)) ?? 0
        let kind: AudioOutputDevice.Kind = switch transport {
        case kAudioDeviceTransportTypeBuiltIn: source == 0x6864_706E /* 'hdpn' */ ? .headphones : .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: .display
        default: .external
        }
        device = AudioOutputDevice(name: name, kind: kind)
        refresh(showHUD: false)
    }

    func refresh(showHUD: Bool) {
        let v = Self.get(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(0)) ?? volume
        let m = (Self.get(deviceID, kAudioDevicePropertyMute, UInt32(0)) ?? 0) != 0
        guard v != volume || m != isMuted else { return }
        volume = v; isMuted = m
        guard showHUD, Date() > ownChangeUntil else { return }
        // ponytail: shown next to the system volume OSD, not instead of it (the original swallows media keys).
        LiveActivityCenter.shared.show(LiveActivity(kind: .hud, priority: 100, leadingWidth: 24, trailingWidth: 44,
                                                    leading: AnyView(VolumeHUDIcon()), trailing: AnyView(VolumeHUDLevel())),
                                       duration: 1.5)
    }

    func setVolume(_ v: Float) {
        ownChangeUntil = Date().addingTimeInterval(0.6)
        volume = v
        Self.set(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(v))
        if isMuted, v > 0 { setMuted(false) }
    }

    func setMuted(_ m: Bool) {
        ownChangeUntil = Date().addingTimeInterval(0.6)
        isMuted = m
        Self.set(deviceID, kAudioDevicePropertyMute, UInt32(m ? 1 : 0))
    }

    private static func address(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput, _ initial: T) -> T? {
        guard id != kAudioObjectUnknown else { return nil }
        var a = address(sel, scope: scope)
        var v = initial
        var size = UInt32(MemoryLayout<T>.size)
        let err = withUnsafeMutablePointer(to: &v) { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0) }
        return err == noErr ? v : nil
    }

    private static func set<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ value: T) {
        guard id != kAudioObjectUnknown else { return }
        var a = address(sel)
        var v = value
        _ = withUnsafePointer(to: &v) { AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<T>.size), $0) }
    }
}

private struct VolumeHUDIcon: View {
    var body: some View {
        Image(systemName: VolumeService.shared.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
    }
}

private struct VolumeHUDLevel: View {
    var body: some View {
        let v = VolumeService.shared
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.2))
            Capsule().fill(.white).frame(width: 40 * CGFloat(v.isMuted ? 0 : v.volume))
        }
        .frame(width: 40, height: 5)
        .animation(Motion.snappy, value: v.volume)
    }
}

// MARK: - Volume widget (3 units ≈ 120 × 156)

struct VolumeWidget: View {
    var body: some View {
        let v = VolumeService.shared
        WidgetCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: v.device.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text(v.isMuted ? "Muted" : "\(Int((v.volume * 100).rounded()))%")
                        .font(Theme.title(13)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 4)
                if MediaFeature.volumeSettings.value.showsOutput {
                    Text(v.device.name).font(Theme.title(13)).lineLimit(2).padding(.bottom, 8)
                }
                HStack(spacing: 8) {
                    RoundButton(symbol: v.symbol, size: 28) { v.setMuted(!v.isMuted) }
                    CapsuleSlider(value: Double(v.isMuted ? 0 : v.volume), height: 8, onChange: { v.setVolume(Float($0)) })
                }
            }
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Settings pane

struct MusicPane: View {
    var body: some View {
        let s = MediaFeature.settings
        let a = MediaFeature.activitySettings
        let live = LiveActivityCenter.settings
        SettingsPane(title: "Music") {
            SettingsCard(title: "Player") {
                SettingsRow(title: "Preferred source", subtitle: "Used when several players have a track and none is playing.") {
                    Picker("", selection: s.binding(\.preferredSource)) {
                        ForEach(MediaSource.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                SettingsRow(title: "Show lyrics", subtitle: "Synced lyrics from LRCLIB (sends track name and artist to lrclib.net).") {
                    Toggle("", isOn: s.binding(\.showLyrics)).labelsHidden()
                }
                SettingsRow(title: "Show playback progress in Nook widget") {
                    Toggle("", isOn: s.binding(\.showPlaybackProgress)).labelsHidden()
                }
            }
            SettingsCard(title: "Live activity") {
                SettingsRow(title: "Show now playing in closed notch") {
                    Toggle("", isOn: Binding(
                        get: { !live.value.disabledKinds.contains(.media) },
                        set: { on in live.value.disabledKinds.removeAll { $0 == .media }; if !on { live.value.disabledKinds.append(.media) } }
                    )).labelsHidden()
                }
                SettingsRow(title: "Audio visualizer") { Toggle("", isOn: a.binding(\.showVisualizer)).labelsHidden() }
                SettingsRow(title: "Color from album art") { Toggle("", isOn: a.binding(\.isAutomaticallyColored)).labelsHidden() }
                SettingsRow(title: "Album corner radius") {
                    Slider(value: a.binding(\.albumCornerRadius), in: 0...10).frame(width: 140)
                }
            }
            SettingsCard(title: "Volume") {
                SettingsRow(title: "Replace volume HUD", subtitle: "Show volume changes in the notch.") {
                    Toggle("", isOn: live.binding(\.showHUDReplacement)).labelsHidden()
                }
                SettingsRow(title: "Show output device in widget") {
                    Toggle("", isOn: MediaFeature.volumeSettings.binding(\.showsOutput)).labelsHidden()
                }
            }
        }
    }
}
