import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

// Session-persistent file shelf (Tray / TrayFileRecord in the original).

struct TraySettings: Codable, Equatable { var enabled = true }

/// TrayFileRecord: a plain (not security-scoped) bookmark, so renamed or moved files still resolve.
struct TrayFile: Codable, Identifiable, Equatable {
    var id = UUID()
    var bookmarkData: Data
    var addedAt = Date()
    var originalName: String
    var url = URL(fileURLWithPath: "/")   // resolved at load, not stored
    enum CodingKeys: String, CodingKey { case id, bookmarkData, addedAt, originalName }
}

@MainActor @Observable
final class TrayStore {
    static let shared = TrayStore()
    static let settings = Setting("traySettings", default: TraySettings())
    private(set) var files: [TrayFile] = []
    /// A tile is being dragged out of the tray; do not swap the row for the drop target.
    var draggingOut = false

    private init() {
        files = (DataFile.load("tray.json", as: [TrayFile].self) ?? []).compactMap(Self.resolve)
        save()
    }

    /// Resolves the bookmark; nil when the file is gone.
    private static func resolve(_ f: TrayFile) -> TrayFile? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: f.bookmarkData, options: .withoutUI, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        var f = f
        f.url = url
        if stale, let fresh = try? url.bookmarkData() { f.bookmarkData = fresh }
        return f
    }

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !files.contains(where: { $0.url.path == url.path }) {
            guard let data = try? url.bookmarkData() else { continue }
            files.append(TrayFile(bookmarkData: data, originalName: url.lastPathComponent, url: url))
        }
        save()
    }

    func remove(_ id: TrayFile.ID) { files.removeAll { $0.id == id }; save() }
    func clear() { files.removeAll(); save() }

    private func save() {
        DataFile.save(files, to: "tray.json")
        updateActivity()
    }

    /// Closed-notch wings: tray icon + file count while the tray holds files.
    func updateActivity() {
        guard !files.isEmpty, Self.settings.value.enabled else { LiveActivityCenter.shared.remove(.tray); return }
        LiveActivityCenter.shared.show(LiveActivity(
            kind: .tray, priority: 5,
            leading: AnyView(Image(systemName: "tray.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)),
            trailing: AnyView(Text("\(files.count)").font(Theme.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.white))))
    }

    /// Loads file URLs from a SwiftUI drop.
    func accept(_ providers: [NSItemProvider]) -> Bool {
        guard Self.settings.value.enabled else { return false }
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in TrayStore.shared.add([url]) }
            }
        }
        return true
    }

    static func airDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }
}

@MainActor
enum TrayFeature {
    static func start() { TrayStore.shared.updateActivity() }

    static func selfTest() {
        // Bookmark round trip: a missing file is dropped, an existing one resolves.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notchly-tray-test.txt")
        try? "x".write(to: tmp, atomically: true, encoding: .utf8)
        let rec = TrayFile(bookmarkData: try! tmp.bookmarkData(), originalName: tmp.lastPathComponent)
        let decoded = try! JSONDecoder().decode([TrayFile].self, from: JSONEncoder().encode([rec]))
        precondition(decoded.first?.id == rec.id && decoded.first?.originalName == rec.originalName)
        try? FileManager.default.removeItem(at: tmp)
        var stale = false
        let gone = (try? URL(resolvingBookmarkData: rec.bookmarkData, options: .withoutUI, bookmarkDataIsStale: &stale))
            .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        precondition(!gone, "deleted tray file must not resolve to an existing path")
    }
}

// MARK: - Views

/// QuickLook thumbnail with a Finder-icon fallback.
struct TrayThumbnail: View {
    let url: URL
    var size: CGFloat = 56
    @State private var image: NSImage?
    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable().aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .task(id: url) {
                let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
                if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { image = rep.nsImage }
            }
    }
}

/// Dashed drop target shown while files are dragged over the notch.
private struct TrayDropTarget: View {
    var highlighted: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.widgetRadius - 4, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .foregroundStyle(highlighted ? Color.white.opacity(0.8) : Theme.tertiaryText)
            .background((highlighted ? Theme.chipHover : Theme.chip), in: RoundedRectangle(cornerRadius: Theme.widgetRadius - 4, style: .continuous))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 20, weight: .semibold))
                    Text("Drop files here").font(Theme.title(13)).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                }
                .foregroundStyle(highlighted ? .white : Theme.secondaryText)
                .padding(10)
            }
            .animation(Motion.snappy, value: highlighted)
    }
}

struct TrayView: View {
    @Environment(NotchModel.self) private var notch
    @State private var targeted = false
    var body: some View {
        let store = TrayStore.shared
        Group {
            if !TrayStore.settings.value.enabled {
                EmptyState(symbol: "tray", title: "Tray is off", subtitle: "Turn it on in Settings → Tray.")
            } else if (notch.isDraggingFiles && !store.draggingOut) || targeted {
                TrayDropTarget(highlighted: targeted)
            } else if store.files.isEmpty {
                EmptyState(symbol: "tray.and.arrow.down", title: "Drop files here", subtitle: "Files stay here until you remove them.")
            } else {
                HStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(store.files) { TrayTile(file: $0) } }
                    }
                    VStack(spacing: 8) {
                        RoundButton(symbol: "dot.radiowaves.left.and.right") { TrayStore.airDrop(store.files.map(\.url)) }
                            .help("AirDrop all")
                        RoundButton(symbol: "trash") { withAnimation(Motion.snappy) { store.clear() } }
                            .help("Clear tray")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $targeted) { store.accept($0) }
        .onChange(of: notch.isDraggingFiles) { if !notch.isDraggingFiles { store.draggingOut = false } }
    }
}

private struct TrayTile: View {
    let file: TrayFile
    @State private var hovering = false
    var body: some View {
        VStack(spacing: 6) {
            TrayThumbnail(url: file.url, size: 64)
            Text(file.url.lastPathComponent)
                .font(Theme.caption).lineLimit(2).truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .padding(8)
        .frame(width: 96, height: 126)
        .background(hovering ? Theme.chip : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { withAnimation(Motion.snappy) { TrayStore.shared.remove(file.id) } } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        .frame(width: 18, height: 18).background(Color(white: 0.3), in: Circle())
                }
                .buttonStyle(PressableStyle()).padding(4)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(file.url) }
        .onDrag {
            TrayStore.shared.draggingOut = true
            return NSItemProvider(contentsOf: file.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(file.url) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            Button("AirDrop") { TrayStore.airDrop([file.url]) }
            ShareLink("Share…", item: file.url)
            Divider()
            Button("Remove") { TrayStore.shared.remove(file.id) }
        }
        .help(file.url.lastPathComponent)
    }
}

struct TrayWidget: View {
    @Environment(NotchModel.self) private var notch
    @State private var targeted = false
    var body: some View {
        let files = TrayStore.shared.files
        WidgetCard {
            if files.isEmpty || targeted {
                TrayDropTarget(highlighted: targeted)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ZStack {
                        ForEach(Array(files.suffix(3).enumerated()), id: \.element.id) { i, f in
                            TrayThumbnail(url: f.url, size: 54)
                                .rotationEffect(.degrees(Double(i - 1) * 9))
                                .offset(x: CGFloat(i - 1) * 14)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text("\(files.count) file\(files.count == 1 ? "" : "s")").font(Theme.title(13))
                    Text("Tray").font(Theme.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { notch.select(.tray) }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { TrayStore.shared.accept($0) }
    }
}

struct TrayPane: View {
    var body: some View {
        let s = TrayStore.settings
        let store = TrayStore.shared
        let live = LiveActivityCenter.settings
        SettingsPane(title: "Tray") {
            SettingsCard {
                SettingsRow(title: "Enable tray", subtitle: "Drop files on the notch to keep them close at hand.") {
                    Toggle("", isOn: s.binding(\.enabled)).labelsHidden()
                }
                SettingsRow(title: "Show file count in the closed notch") {
                    Toggle("", isOn: Binding(
                        get: { !live.value.disabledKinds.contains(.tray) },
                        set: { on in live.value.disabledKinds.removeAll { $0 == .tray }; if !on { live.value.disabledKinds.append(.tray) } }
                    )).labelsHidden()
                }
            }
            SettingsCard(title: "Files") {
                SettingsRow(title: "\(store.files.count) file\(store.files.count == 1 ? "" : "s") in the tray") {
                    Button("Clear tray") { store.clear() }.disabled(store.files.isEmpty)
                }
            }
        }
        .onChange(of: s.value) { store.updateActivity() }
    }
}
