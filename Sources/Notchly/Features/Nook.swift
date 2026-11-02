import AVFoundation
import SwiftUI

/// Starts every feature service once at launch.
@MainActor
enum Features {
    static func start() {
        MediaFeature.start()
        TrayFeature.start()
        ClipboardFeature.start()
        CalendarFeature.start()
        AgentsFeature.start()
    }

    /// `Notchly --selftest`: runs each feature's assert-based checks, then exits.
    static func selfTest() {
        MediaFeature.selfTest()
        TrayFeature.selfTest()
        ClipboardFeature.selfTest()
        CalendarFeature.selfTest()
        AgentsFeature.selfTest()
        AppInfo.selfTest()
        print("selftest: ok")
    }
}

/// Same case names as NotchNook's NookWidget enum.
enum NookWidget: String, Codable, CaseIterable, Identifiable {
    case media, calendar, weather, timer, todoList, activity, aiUsage, pulse, clipboard, notes, tray, volume, shortcuts, mirror, quickApps
    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Music"
        case .calendar: "Calendar"
        case .weather: "Weather"
        case .timer: "Timer"
        case .todoList: "To-dos"
        case .activity: "Activity"
        case .aiUsage: "AI Usage"
        case .pulse: "Pulse"
        case .clipboard: "Clipboard"
        case .notes: "Notes"
        case .tray: "Tray"
        case .volume: "Volume"
        case .shortcuts: "Shortcuts"
        case .mirror: "Mirror"
        case .quickApps: "Quick Apps"
        }
    }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .calendar: "calendar"
        case .weather: "cloud.sun.fill"
        case .timer: "timer"
        case .todoList: "checklist"
        case .activity: "square.grid.3x3.fill"
        case .aiUsage: "sparkles"
        case .pulse: "waveform.path.ecg"
        case .clipboard: "doc.on.clipboard"
        case .notes: "note.text"
        case .tray: "tray"
        case .volume: "speaker.wave.2.fill"
        case .shortcuts: "square.stack.3d.up.fill"
        case .mirror: "person.crop.square"
        case .quickApps: "app.badge"
        }
    }

    /// Width in grid units (NookGrid.Size; media default is 5 × 2).
    var units: CGFloat {
        switch self {
        case .media: 5
        case .calendar, .timer, .todoList, .aiUsage, .clipboard, .notes, .shortcuts: 4
        case .weather, .pulse, .tray, .volume, .quickApps, .activity: 3
        case .mirror: 2
        }
    }
}

struct NookSettings: Codable, Equatable {
    var enabledWidgets: [NookWidget] = [.media, .calendar, .timer, .weather]
    var showDividers = false
}

@MainActor
enum NookFeature {
    static let settings = Setting("nookSettings", default: NookSettings())
}

struct NookView: View {
    var body: some View {
        let widgets = NookFeature.settings.value.enabledWidgets
        if widgets.isEmpty {
            EmptyState(symbol: "square.grid.2x2", title: "Your Nook is empty", subtitle: "Add widgets in Settings → Nook.")
        } else {
            GeometryReader { geo in
                let gap: CGFloat = 10
                let total = widgets.reduce(0) { $0 + $1.units }
                let fitUnit = (geo.size.width - gap * CGFloat(widgets.count - 1)) / total
                let unit = max(fitUnit, 38)
                let row = HStack(spacing: gap) {
                    ForEach(widgets) { w in
                        NookWidgetView(widget: w).frame(width: w.units * unit, height: geo.size.height)
                    }
                }
                if unit > fitUnit {
                    ScrollView(.horizontal, showsIndicators: false) { row }
                } else {
                    row
                }
            }
        }
    }
}

struct NookWidgetView: View {
    let widget: NookWidget
    var body: some View {
        switch widget {
        case .media: MediaWidget()
        case .calendar: CalendarWidget()
        case .weather: WeatherWidget()
        case .timer: TimerWidget()
        case .todoList: TodoWidget()
        case .activity: TodoActivityWidget()
        case .aiUsage: AIUsageWidget()
        case .pulse: PulseWidget()
        case .clipboard: ClipboardWidget()
        case .notes: NotesWidget()
        case .tray: TrayWidget()
        case .volume: VolumeWidget()
        case .shortcuts: ShortcutsWidget()
        case .mirror: MirrorWidget()
        case .quickApps: QuickAppsWidget()
        }
    }
}

struct NookPane: View {
    var body: some View {
        let s = NookFeature.settings
        SettingsPane(title: "Nook") {
            SettingsCard(title: "Widgets in your Nook (drag to reorder)") {
                List {
                    ForEach(s.value.enabledWidgets) { w in
                        HStack {
                            Image(systemName: w.symbol).frame(width: 20)
                            Text(w.title)
                            Spacer()
                            Button { s.value.enabledWidgets.removeAll { $0 == w } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                                .buttonStyle(.plain)
                        }
                    }
                    .onMove { s.value.enabledWidgets.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(height: CGFloat(max(s.value.enabledWidgets.count, 1)) * 30 + 12)
                .scrollDisabled(true)
            }
            SettingsCard(title: "Add widgets") {
                ForEach(NookWidget.allCases.filter { !s.value.enabledWidgets.contains($0) }) { w in
                    SettingsRow(title: w.title) {
                        Button { s.value.enabledWidgets.append(w) } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.green) }
                            .buttonStyle(.plain)
                    }
                }
            }
            SettingsCard(title: "Quick Apps") { QuickAppsSettingsEditor() }
            SettingsCard(title: "Shortcuts widget") { ShortcutsWidgetSettings() }
        }
    }
}

// MARK: - Shortcuts widget (runs macOS Shortcuts by name)

struct ShortcutsSettings: Codable, Equatable { var names: [String] = [] }

@MainActor
enum ShortcutsFeature {
    static let settings = Setting("shortcutsWidgetSettings", default: ShortcutsSettings())

    static func allShortcuts() async -> [String] {
        await Task.detached { (try? Shell.run("/usr/bin/shortcuts", ["list"]))?.split(separator: "\n").map(String.init) ?? [] }.value
    }

    static func run(_ name: String) {
        Task.detached { _ = try? Shell.run("/usr/bin/shortcuts", ["run", name]) }
    }
}

struct ShortcutsWidget: View {
    var body: some View {
        let names = ShortcutsFeature.settings.value.names
        if names.isEmpty {
            WidgetCard { EmptyState(symbol: "square.stack.3d.up", title: "No shortcuts", subtitle: "Pick them in Settings → Nook") }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(names.prefix(6), id: \.self) { name in
                    Button { ShortcutsFeature.run(name) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").foregroundStyle(.yellow)
                            Text(name).lineLimit(1)
                        }
                        .font(Theme.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(Theme.card, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct ShortcutsWidgetSettings: View {
    @State private var all: [String] = []
    var body: some View {
        let s = ShortcutsFeature.settings
        Group {
            if all.isEmpty { Text("No shortcuts found in the Shortcuts app.").foregroundStyle(.secondary).padding(.vertical, 6) }
            ForEach(all, id: \.self) { name in
                SettingsRow(title: name) {
                    Toggle("", isOn: Binding(
                        get: { s.value.names.contains(name) },
                        set: { on in s.value.names.removeAll { $0 == name }; if on { s.value.names.append(name) } }
                    )).labelsHidden()
                }
            }
        }
        .task { all = await ShortcutsFeature.allShortcuts() }
    }
}

// MARK: - Quick Apps widget

struct QuickAppsSettings: Codable, Equatable {
    var paths: [String] = ["/System/Applications/Notes.app", "/System/Applications/Calendar.app",
                           "/System/Applications/Utilities/Terminal.app", "/System/Library/CoreServices/Finder.app"]
}

@MainActor
enum QuickAppsFeature { static let settings = Setting("quickAppsWidgetSettings", default: QuickAppsSettings()) }

struct QuickAppsWidget: View {
    var body: some View {
        WidgetCard {
            let paths = QuickAppsFeature.settings.value.paths
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 8) {
                ForEach(paths, id: \.self) { path in
                    Button { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) } label: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 34, height: 34)
                    }
                    .buttonStyle(PressableStyle())
                    .help(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

extension QuickAppsSettings {
    @MainActor static func pickApp() -> String? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// Settings list for Quick Apps (add with an open panel, remove with the minus button).
struct QuickAppsSettingsEditor: View {
    var body: some View {
        let s = QuickAppsFeature.settings
        ForEach(s.value.paths, id: \.self) { path in
            SettingsRow(title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) {
                Button { s.value.paths.removeAll { $0 == path } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                    .buttonStyle(.plain)
            }
        }
        HStack { Spacer(); Button("Add App…") { if let p = QuickAppsSettings.pickApp() { s.value.paths.append(p) } } }
            .padding(.vertical, 6)
    }
}

// MARK: - Mirror widget (camera preview, starts on tap: MirrorWidgetSettings.startInstantly = false)

struct MirrorWidget: View {
    @State private var running = false
    var body: some View {
        ZStack {
            if running {
                CameraPreview().clipShape(RoundedRectangle(cornerRadius: Theme.widgetRadius, style: .continuous))
            } else {
                WidgetCard {
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.square").font(.system(size: 24, weight: .semibold))
                        Text("Mirror").font(Theme.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { running.toggle() }
    }
}

private struct CameraPreview: NSViewRepresentable {
    final class Coordinator { let session = AVCaptureSession() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let session = context.coordinator.session
        if let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))   // mirrored
        view.layer = layer
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        let session = coordinator.session
        DispatchQueue.global().async { session.stopRunning() }
    }
}

// MARK: - Shell helper shared by features

enum Shell {
    /// Runs a tool synchronously and returns stdout. Call off the main thread.
    @discardableResult
    static func run(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        // An unread stderr pipe fills at 64 KB and blocks the tool forever.
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs AppleScript source and returns the string result, or nil on error.
    static func appleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }
}

/// Bounds for image bytes from other apps, web pages and servers (pasteboard, artwork). A small compressed
/// file can declare huge dimensions, so check the header before any decode and never decode at full size.
enum UntrustedImage {
    static let maxBytes = 20 << 20
    static let maxPixels = 50_000_000      // a 6K-display screenshot is about 20 MP

    /// Whether `data` is an image ImageIO can read whose header is within the byte and pixel limits.
    static func isAcceptable(_ data: Data) -> Bool {
        guard data.count <= maxBytes, let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return false }
        return Double(w) * Double(h) <= Double(maxPixels)
    }

    /// A decoded thumbnail no larger than `maxSide` pixels, or nil if `data` is not acceptable.
    static func thumbnail(_ data: Data, maxSide: Int = 512) -> NSImage? {
        guard isAcceptable(data), let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
