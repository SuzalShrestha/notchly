import SwiftUI

/// One JSON-encoded UserDefaults key per settings struct — same pattern as NotchNook
/// (`generalSettings`, `clipboardSettings`, …). A decode failure falls back to the default.
@MainActor @Observable
final class Setting<Value: Codable & Equatable> {
    var value: Value { didSet { if value != oldValue { save() } } }
    private let key: String

    init(_ key: String, default value: Value) {
        self.key = key
        let data = UserDefaults.standard.data(forKey: key)
        if let data, let decoded = try? JSONDecoder().decode(Value.self, from: data) {
            self.value = decoded
        } else {
            if let data { UserDefaults.standard.set(data, forKey: key + ".undecodable") }
            self.value = value
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    func binding<T>(_ keyPath: WritableKeyPath<Value, T>) -> Binding<T> {
        Binding(get: { self.value[keyPath: keyPath] }, set: { self.value[keyPath: keyPath] = $0 })
    }
}

/// Small JSON file store in Application Support for feature data (tray, clipboard, todos, …).
enum DataFile {
    static let folder: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        let url = folder.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let value = try? JSONDecoder().decode(T.self, from: data) { return value }
        // Keep the unreadable file so a later save cannot destroy it.
        try? data.write(to: url.appendingPathExtension("undecodable-\(Int(Date().timeIntervalSince1970))"))
        return nil
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}

// MARK: - General settings (subset of NotchNook GeneralSettings, same key names)

enum NotchOpenSpeed: String, Codable, CaseIterable {
    case standard, slower, slowest
    var multiplier: Double { switch self { case .standard: 1; case .slower: 0.8; case .slowest: 0.65 } }
}

enum NavigationDockStyle: String, Codable, CaseIterable { case compact, icons, dots }
enum DisplaySelection: String, Codable, CaseIterable { case all, notchedOnly, mainOnly }

struct GeneralSettings: Codable, Equatable {
    var alwaysOpenNotchOnHover = true
    var disableHaptics = false
    var enableOnNonNotchScreens = true
    var displaySelection: DisplaySelection = .all
    var notchOpenSpeed: NotchOpenSpeed = .standard
    var navigationDockStyle: NavigationDockStyle = .compact
    var contentPadding: Double = 12
    var notchWidthFineTune: Double = 0
    var notchHeightFineTune: Double = 0
    var handleWidth: Double = 184            // handleSize = [184, 8]
    var handleHeight: Double = 8
    var preventUnhoverCloseWhenTyping = true
    var hoverOpenDelay: Double = 0.05
    var navigationShortcutsEnabled = true
    var showNotchInScreenshots = true
    var hiddenModes: [NotchMode] = []
}

@MainActor
enum Settings {
    static let general = Setting("generalSettings", default: GeneralSettings())
}

// MARK: - Live activities (closed-notch "wings")

/// A closed-notch activity: content on each side of the camera housing.
struct LiveActivity: Identifiable {
    enum Kind: String, CaseIterable, Codable {
        // Same case names as NotchNook's LiveActivity enum (subset).
        case hud, media, timerRunning, timerExpired, agentWorking, agentAlert, batteryVisualizer, fileDownloading, tray, calendar
        var title: String {
            switch self {
            case .hud: "Volume & brightness HUD"
            case .media: "Now playing"
            case .timerRunning: "Running timer"
            case .timerExpired: "Timer finished"
            case .agentWorking: "Agent working"
            case .agentAlert: "Agent needs you"
            case .batteryVisualizer: "Battery"
            case .fileDownloading: "Downloads"
            case .tray: "Tray files"
            case .calendar: "Upcoming event"
            }
        }
    }

    let kind: Kind
    var priority: Int
    var leadingWidth: CGFloat = 30
    var trailingWidth: CGFloat = 30
    var leading: AnyView
    var trailing: AnyView
    var id: Kind { kind }
}

struct LiveActivitiesSettings: Codable, Equatable {
    var enabled = true
    var disabledKinds: [LiveActivity.Kind] = []
    var showHUDReplacement = true
}

@MainActor @Observable
final class LiveActivityCenter {
    static let shared = LiveActivityCenter()
    static let settings = Setting("liveActivitiesSettings", default: LiveActivitiesSettings())

    private(set) var activities: [LiveActivity.Kind: LiveActivity] = [:]
    private var expiry: [LiveActivity.Kind: Task<Void, Never>] = [:]

    /// The activity shown in the closed notch: highest priority among enabled ones.
    var current: LiveActivity? {
        let s = Self.settings.value
        guard s.enabled else { return nil }
        return activities.values
            .filter { !s.disabledKinds.contains($0.kind) && ($0.kind != .hud || s.showHUDReplacement) }
            .max { $0.priority < $1.priority }
    }

    /// Show or replace an activity; with `duration` it removes itself afterwards.
    func show(_ activity: LiveActivity, duration: TimeInterval? = nil) {
        withAnimation(Motion.snappy) { activities[activity.kind] = activity }
        expiry[activity.kind]?.cancel()
        guard let duration else { return }
        expiry[activity.kind] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.remove(activity.kind)
        }
    }

    func remove(_ kind: LiveActivity.Kind) {
        expiry[kind]?.cancel()
        withAnimation(Motion.snappy) { _ = activities.removeValue(forKey: kind) }
    }
}
