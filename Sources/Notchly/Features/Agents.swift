import SwiftUI

// MARK: - Model (same case names as NotchNook's AgentPhase / AgentStep.Kind / AgentStep.State)

enum AgentPhase: String, Codable { case thinking, working, needsPermission, needsInput, done, idle
    var needsAttention: Bool { self == .needsPermission || self == .needsInput }
    var isBusy: Bool { self == .thinking || self == .working }

    var label: String {
        switch self {
        case .thinking: "Thinking"
        case .working: "Working"
        case .needsPermission: "Allow?"
        case .needsInput: "Needs input"
        case .done: "Done"
        case .idle: "Idle"
        }
    }

    var color: Color {
        switch self {
        case .thinking, .working: Theme.claude
        case .needsPermission, .needsInput: Theme.warning
        case .done: Theme.success
        case .idle: Theme.tertiaryText
        }
    }
}

struct AgentStep: Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case read, edit, write, command, search, web, task, question, other
        init(tool: String) {
            switch tool {
            case "Read", "NotebookRead": self = .read
            case "Edit", "MultiEdit", "NotebookEdit": self = .edit
            case "Write": self = .write
            case "Bash", "BashOutput": self = .command
            case "Grep", "Glob", "LS": self = .search
            case "WebFetch", "WebSearch": self = .web
            case "Task", "Agent": self = .task
            case "AskUserQuestion": self = .question
            default: self = .other
            }
        }
        var symbol: String {
            switch self {
            case .read: "doc.text"; case .edit: "pencil"; case .write: "square.and.pencil"; case .command: "terminal"
            case .search: "magnifyingglass"; case .web: "globe"; case .task: "person.2"; case .question: "questionmark.bubble"
            case .other: "wrench.and.screwdriver"
            }
        }
        var verb: String {
            switch self {
            case .read: "Read"; case .edit: "Edit"; case .write: "Write"; case .command: "Run"; case .search: "Search"
            case .web: "Fetch"; case .task: "Task"; case .question: "Ask"; case .other: ""
            }
        }
        /// What the pet says it is doing.
        var activity: String {
            switch self {
            case .read: "Reading files"; case .edit: "Editing code"; case .write: "Writing a file"
            case .command: "Running a command"; case .search: "Searching the code"; case .web: "Browsing the web"
            case .task: "Delegating to a subagent"; case .question: "Has a question"; case .other: "Using a tool"
            }
        }
        /// Plural noun for the activity legend.
        var noun: String {
            switch self {
            case .read: "reads"; case .edit: "edits"; case .write: "writes"; case .command: "commands"
            case .search: "searches"; case .web: "web"; case .task: "subagents"; case .question: "questions"; case .other: "other"
            }
        }
        /// One hue per kind, tuned to read on the black panel.
        var tint: Color {
            switch self {
            case .read: Color(hex: 0x7AB8FF); case .edit: Color(hex: 0xFFB45E); case .write: Color(hex: 0xFFD166)
            case .command: Color(hex: 0x6EE7A8); case .search: Color(hex: 0xB79CFF); case .web: Color(hex: 0x5ED6E6)
            case .task: Color(hex: 0xFF8FB1); case .question: Color(nsColor: .systemOrange); case .other: Color(white: 0.72)
            }
        }
    }
    enum State: String, Codable { case running, done, failed }

    var id: String
    var kind: Kind
    var tool: String
    var subject: String
    var state: State = .running
    var startedAt = Date()
    var endedAt: Date?

    func duration(at now: Date = Date()) -> TimeInterval { (endedAt ?? now).timeIntervalSince(startedAt) }

    /// Folder of a file subject, relative to the session's working directory when inside it.
    func detail(relativeTo cwd: String) -> String? {
        guard subject.hasPrefix("/") else { return nil }
        let dir = (subject as NSString).deletingLastPathComponent
        if !cwd.isEmpty, dir == cwd { return nil }
        if !cwd.isEmpty, dir.hasPrefix(cwd + "/") { return String(dir.dropFirst(cwd.count + 1)) }
        return (dir as NSString).abbreviatingWithTildeInPath
    }

    var title: String {
        let s = subject.hasPrefix("/") ? URL(fileURLWithPath: subject).lastPathComponent : subject
        let head = kind == .other ? tool : kind.verb
        return s.isEmpty ? head : "\(head) \(s)"
    }
}

/// One Claude Code hook payload (hook_event_name, session_id, cwd, tool_name, tool_input, prompt, message, …).
struct HookEvent {
    enum Kind: Equatable {
        case prompt(String)
        case toolStart(AgentStep.Kind, tool: String, subject: String)
        case toolEnd(tool: String, failed: Bool)
        case attention(String, permission: Bool)
        case stop, end, other
    }
    var sessionID: String
    var cwd: String
    var toolUseID: String?
    var kind: Kind

    init?(json data: Data) {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = o["hook_event_name"] as? String, let sid = o["session_id"] as? String else { return nil }
        sessionID = sid
        cwd = o["cwd"] as? String ?? ""
        toolUseID = o["tool_use_id"] as? String
        let tool = o["tool_name"] as? String ?? ""
        switch name {
        case "UserPromptSubmit":
            let p = (o["prompt"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            kind = .prompt(String(p.prefix(600)))
        case "PreToolUse":
            let input = o["tool_input"] as? [String: Any] ?? [:]
            let raw = ["file_path", "notebook_path", "command", "pattern", "url", "query", "description", "path"]
                .lazy.compactMap { input[$0] as? String }.first ?? ""
            kind = .toolStart(AgentStep.Kind(tool: tool), tool: tool, subject: String(raw.split(separator: "\n").first ?? ""))
        case "PostToolUse":
            let r = o["tool_response"] as? [String: Any]
            kind = .toolEnd(tool: tool, failed: (r?["is_error"] as? Bool) == true || (r?["success"] as? Bool) == false)
        case "Notification":
            let msg = o["message"] as? String ?? ""
            let type = o["notification_type"] as? String ?? ""
            kind = .attention(msg, permission: type == "permission_prompt" || msg.localizedCaseInsensitiveContains("permission"))
        case "Stop": kind = .stop
        case "SessionEnd": kind = .end
        default: kind = .other
        }
    }
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    var cwd: String
    /// First line of the latest prompt; `prompt` keeps the full text (capped).
    var title = ""
    var prompt = ""
    var phase: AgentPhase = .idle
    var message = ""
    var steps: [AgentStep] = []
    var startedAt = Date()
    var updatedAt = Date()
    // Per-turn counters (reset on each prompt); `steps` keeps only the last 50.
    var turns = 0
    var toolCount = 0
    var failures = 0
    var kindCounts: [AgentStep.Kind: Int] = [:]
    var files: Set<String> = []
    var lastFailureAt: Date?

    var project: String { cwd.isEmpty ? "Claude Code" : URL(fileURLWithPath: cwd).lastPathComponent }
    var runningStep: AgentStep? { steps.last { $0.state == .running } }
    var currentLine: String {
        if phase.needsAttention { return message.isEmpty ? "Needs your input" : message }
        if let s = runningStep { return s.title }
        return phase == .thinking ? "Thinking…" : (steps.last?.title ?? title)
    }

    /// Wall time of the current turn: live while it runs, frozen once it stops.
    func elapsed(at now: Date = Date()) -> TimeInterval {
        (phase.isBusy || phase.needsAttention ? now : updatedAt).timeIntervalSince(startedAt)
    }

    mutating func apply(_ e: HookEvent.Kind, toolUseID: String?, at now: Date = Date()) {
        updatedAt = now
        switch e {
        case .prompt(let p):
            title = String(p.split(separator: "\n").first ?? ""); prompt = p
            phase = .thinking; message = ""; steps = []; startedAt = now
            turns += 1; toolCount = 0; failures = 0; kindCounts = [:]; files = []; lastFailureAt = nil
        case .toolStart(let kind, let tool, let subject):
            phase = .working; message = ""
            steps.append(AgentStep(id: toolUseID ?? UUID().uuidString, kind: kind, tool: tool, subject: subject, startedAt: now))
            if steps.count > 50 { steps.removeFirst(steps.count - 50) }
            toolCount += 1
            kindCounts[kind, default: 0] += 1
            if (kind == .edit || kind == .write), subject.hasPrefix("/") { files.insert(subject) }
        case .toolEnd(let tool, let failed):
            let i = steps.lastIndex { toolUseID != nil ? $0.id == toolUseID : ($0.tool == tool && $0.state == .running) }
            if let i { steps[i].state = failed ? .failed : .done; steps[i].endedAt = now }
            if failed { failures += 1; lastFailureAt = now }
            phase = .working; message = ""
        case .attention(let msg, let permission):
            phase = permission ? .needsPermission : .needsInput; message = msg
        case .stop:
            phase = .done; message = ""
            for i in steps.indices where steps[i].state == .running { steps[i].state = .done; steps[i].endedAt = now }
        case .end, .other: break
        }
    }
}

struct AgentsSettings: Codable, Equatable {
    enum Layout: String, Codable, CaseIterable {
        case focus, grid, list
        var title: String { switch self { case .focus: "Focus"; case .grid: "Grid"; case .list: "List" } }
    }
    var enabled = true
    var layout: Layout = .focus
    var showWorkingActivity = true
    var notifyFinished = true
    var notifyAttention = true
    var playsSound = false
    var showPet = true
}

extension AgentsSettings {
    /// Tolerates keys added in later versions, so an update never resets saved settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AgentsSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        layout = (try? c.decodeIfPresent(Layout.self, forKey: .layout)) ?? d.layout
        showWorkingActivity = try c.decodeIfPresent(Bool.self, forKey: .showWorkingActivity) ?? d.showWorkingActivity
        notifyFinished = try c.decodeIfPresent(Bool.self, forKey: .notifyFinished) ?? d.notifyFinished
        notifyAttention = try c.decodeIfPresent(Bool.self, forKey: .notifyAttention) ?? d.notifyAttention
        playsSound = try c.decodeIfPresent(Bool.self, forKey: .playsSound) ?? d.playsSound
        showPet = try c.decodeIfPresent(Bool.self, forKey: .showPet) ?? d.showPet
        // Before 1.1, Grid was the default and was saved with any other change: move those to the new Focus view.
        if !c.contains(.showPet), layout == .grid { layout = .focus }
    }
}

// MARK: - Store + live activities

@MainActor @Observable
final class AgentStore {
    static let shared = AgentStore()
    private(set) var sessions: [String: AgentSession] = [:]
    var listening = false
    /// Session shown in the Focus layout; nil follows the one that needs you, else the newest.
    var selectedID: String?
    private(set) var hooksInstalled = false
    private(set) var hookError: String?
    /// Project shown by the "finished" wing.
    private(set) var finishedProject = ""
    @ObservationIgnored private var showingAttention = false

    var sorted: [AgentSession] { sessions.values.sorted { $0.startedAt > $1.startedAt } }
    var needsAttention: Bool { sessions.values.contains { $0.phase.needsAttention } }
    var isBusy: Bool { sessions.values.contains { $0.phase.isBusy } }

    var selected: AgentSession? {
        if let id = selectedID, let s = sessions[id] { return s }
        let list = sorted
        return list.first(where: \.phase.needsAttention) ?? list.first(where: \.phase.isBusy) ?? list.first
    }

    init() {
        if CommandLine.arguments.contains("--snapshot") { seedDemo() }
    }

    func receive(_ data: Data) {
        guard AgentsFeature.settings.value.enabled, let e = HookEvent(json: data) else { return }
        if e.kind == .end { dismiss(e.sessionID); return }
        var s = sessions[e.sessionID] ?? AgentSession(id: e.sessionID, cwd: e.cwd)
        let wasAttention = s.phase.needsAttention
        if !e.cwd.isEmpty { s.cwd = e.cwd }
        s.apply(e.kind, toolUseID: e.toolUseID)
        sessions[e.sessionID] = s
        let set = AgentsFeature.settings.value
        if s.phase.needsAttention, !wasAttention, set.playsSound { NSSound(named: "Ping")?.play() }
        if e.kind == .stop, set.notifyFinished, !needsAttention { showFinished(s.project) }
        refreshActivities()
    }

    func dismiss(_ id: String) {
        sessions[id] = nil
        if selectedID == id { selectedID = nil }
        refreshActivities()
    }

    func clearFinished() {
        for s in sessions.values where !s.phase.isBusy && !s.phase.needsAttention { sessions[s.id] = nil }
        if let id = selectedID, sessions[id] == nil { selectedID = nil }
        refreshActivities()
    }

    // MARK: Hooks

    func refreshHookStatus() {
        hooksInstalled = (try? HookInstaller.isInstalled(HookInstaller.loadSettings())) ?? false
    }

    func setHooks(installed add: Bool) {
        do { try HookInstaller.apply(add: add); hookError = nil } catch { hookError = error.localizedDescription }
        refreshHookStatus()
    }

    // MARK: Pet

    /// Mood across every session: whoever needs you wins, then the busiest, then the most recent.
    func petMood(at now: Date) -> PetMood { Self.mood(Array(sessions.values), at: now) }

    nonisolated static func mood(_ list: [AgentSession], at now: Date) -> PetMood {
        if list.isEmpty { return .sleeping }
        if list.contains(where: \.phase.needsAttention) { return .alert }
        if let busy = list.filter(\.phase.isBusy).max(by: { $0.updatedAt < $1.updatedAt }) {
            if let f = busy.lastFailureAt, now.timeIntervalSince(f) < 3 { return .oops }
            if busy.phase == .working, let step = busy.runningStep { return .working(step.kind) }
            return .thinking
        }
        if list.contains(where: { $0.phase == .done && now.timeIntervalSince($0.updatedAt) < 6 }) { return .celebrating }
        let latest = list.map(\.updatedAt).max() ?? .distantPast
        return now.timeIntervalSince(latest) > 180 ? .sleeping : .idle
    }

    // MARK: Live activities
    //
    // The wing views read this store themselves, so a hook event only touches the activity center
    // when a wing has to appear or disappear (not on every tool call).

    private func showFinished(_ project: String) {
        finishedProject = project
        showingAttention = false
        LiveActivityCenter.shared.show(LiveActivity(
            kind: .agentAlert, priority: 90, leadingWidth: 26, trailingWidth: 76,
            leading: AnyView(AgentWingPet()), trailing: AnyView(AgentAlertWingLabel())
        ), duration: 4)
    }

    func refreshActivities() {
        let set = AgentsFeature.settings.value
        let center = LiveActivityCenter.shared
        let attention = set.notifyAttention && needsAttention
        if attention, !showingAttention || center.activities[.agentAlert] == nil {
            center.show(LiveActivity(
                kind: .agentAlert, priority: 90, leadingWidth: 26, trailingWidth: 76,
                leading: AnyView(AgentWingPet()), trailing: AnyView(AgentAlertWingLabel())
            ))
        } else if !attention, showingAttention {
            center.remove(.agentAlert)
        }
        showingAttention = attention

        let busy = set.showWorkingActivity && isBusy
        let shown = center.activities[.agentWorking] != nil
        if busy, !shown {
            center.show(LiveActivity(
                kind: .agentWorking, priority: 60, leadingWidth: 26, trailingWidth: 48,
                leading: AnyView(AgentWingPet()), trailing: AnyView(AgentWorkingWingLabel())
            ))
        } else if !busy, shown {
            center.remove(.agentWorking)
        }
    }

    private func seedDemo() {
        let t0 = Date().addingTimeInterval(-94)
        var a = AgentSession(id: "demo1", cwd: "/Users/me/Notchly")
        a.apply(.prompt("Add a teleprompter tab with a countdown\nand speed control"), toolUseID: nil, at: t0)
        a.apply(.toolStart(.search, tool: "Grep", subject: "NotchMode"), toolUseID: "t0", at: t0 + 3)
        a.apply(.toolEnd(tool: "Grep", failed: false), toolUseID: "t0", at: t0 + 4)
        a.apply(.toolStart(.read, tool: "Read", subject: "/Users/me/Notchly/Sources/Core/Design.swift"), toolUseID: "t1", at: t0 + 6)
        a.apply(.toolEnd(tool: "Read", failed: false), toolUseID: "t1", at: t0 + 7)
        a.apply(.toolStart(.edit, tool: "Edit", subject: "/Users/me/Notchly/Sources/Features/Prompter.swift"), toolUseID: "t2", at: t0 + 21)
        a.apply(.toolEnd(tool: "Edit", failed: false), toolUseID: "t2", at: t0 + 23)
        a.apply(.toolStart(.write, tool: "Write", subject: "/Users/me/Notchly/Sources/Features/Countdown.swift"), toolUseID: "t5", at: t0 + 40)
        a.apply(.toolEnd(tool: "Write", failed: false), toolUseID: "t5", at: t0 + 41)
        a.apply(.toolStart(.command, tool: "Bash", subject: "swift build"), toolUseID: "t3", at: t0 + 60)
        var b = AgentSession(id: "demo2", cwd: "/Users/me/website")
        b.apply(.prompt("Fix the header layout"), toolUseID: nil, at: t0 - 200)
        b.apply(.toolStart(.command, tool: "Bash", subject: "rm -rf dist"), toolUseID: "t4", at: t0 - 180)
        b.apply(.attention("Claude needs your permission to use Bash", permission: true), toolUseID: nil, at: t0 - 179)
        sessions = [a.id: a, b.id: b]
        selectedID = a.id
    }
}

/// Activates the terminal Claude Code most likely runs in. Hook payloads carry no PID or app,
/// so this picks the first running app from a list of terminals and editors with terminals.
@MainActor
enum TerminalFocus {
    static let bundleIDs = [
        "com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "io.alacritty", "com.apple.Terminal", "dev.zed.Zed",
        "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode", "com.exafunction.windsurf",
    ]

    static var runningApp: NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications
        for id in bundleIDs { if let app = running.first(where: { $0.bundleIdentifier == id }) { return app } }
        return nil
    }

    static func activate() {
        if let app = runningApp { _ = app.activate() }
        else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}

// MARK: - Unix socket bridge (hook script → nc -U → here)

enum AgentBridgeServer {
    static var socketPath: String { DataFile.folder.appendingPathComponent("agents.sock").path }

    /// Binds a stream socket at `path` and calls `onPayload` (on a background thread) once per connection.
    @discardableResult
    static func start(path: String, onPayload: @escaping @Sendable (Data) -> Void) -> Bool {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in bytes.withUnsafeBytes { dst.copyMemory(from: $0) } }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); return false }
        chmod(path, 0o600)
        Thread.detachNewThread {
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { if errno == EINTR { continue } else { break } }
                if let data = readPayload(c) { onPayload(data) }
                close(c)
            }
        }
        return true
    }

    /// Reads until EOF or until the bytes form one complete JSON object (nc keeps the socket open until we close).
    private static func readPayload(_ c: Int32) -> Data? {
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while data.count < 16 << 20 {
            let n = read(c, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
            if let last = data.last(where: { !($0 == 10 || $0 == 13 || $0 == 32) }), last == UInt8(ascii: "}"),
               (try? JSONSerialization.jsonObject(with: data)) != nil { break }
        }
        return data.isEmpty ? nil : data
    }
}

// MARK: - Hook installer (button press only; backs up settings.json first)

enum HookInstaller {
    static let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]
    static let marker = "notchly-hook.sh"
    static var settingsURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }
    static var scriptURL: URL { DataFile.folder.appendingPathComponent(marker) }
    static var command: String { "'\(scriptURL.path)'" }

    static func script(socket: String) -> String {
        "#!/bin/sh\n# Notchly: forwards Claude Code hook events to the notch. Never blocks Claude.\n"
            + "/usr/bin/nc -U -w 1 '\(socket)' >/dev/null 2>&1\nexit 0\n"
    }

    /// Removes our entries from every event, then (if `add`) appends one group per event. nil = malformed hooks.
    static func merged(_ root: [String: Any], add: Bool, command: String = HookInstaller.command) -> [String: Any]? {
        var root = root
        guard var hooks = (root["hooks"] ?? [String: Any]()) as? [String: Any] else { return nil }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { return nil }
            let kept: [[String: Any]] = groups.compactMap { g in
                guard let hs = g["hooks"] as? [[String: Any]] else { return g }
                let rest = hs.filter { !(($0["command"] as? String)?.contains(marker) ?? false) }
                if rest.count == hs.count { return g }
                if rest.isEmpty { return nil }
                var g = g; g["hooks"] = rest; return g
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        if add {
            for e in events {
                var g: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]]]
                if e == "PreToolUse" || e == "PostToolUse" { g["matcher"] = "*" }
                hooks[e] = (hooks[e] as? [[String: Any]] ?? []) + [g]
            }
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return root
    }

    static func isInstalled(_ root: [String: Any]) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { e in
            (hooks[e] as? [[String: Any]] ?? []).contains { g in
                (g["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) ?? false }
            }
        }
    }

    static func loadSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Notchly", code: 1, userInfo: [NSLocalizedDescriptionKey: "settings.json is not a JSON object"])
        }
        return o
    }

    static func apply(add: Bool) throws {
        let fm = FileManager.default
        guard let root = merged(try loadSettings(), add: add) else {
            throw NSError(domain: "Notchly", code: 2, userInfo: [NSLocalizedDescriptionKey: "settings.json has an unexpected \"hooks\" layout; not changed"])
        }
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("notchly-backup")
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: settingsURL, to: backup) }
        }
        if add {
            try script(socket: AgentBridgeServer.socketPath).write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        }
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: settingsURL, options: .atomic)
    }
}

// MARK: - Feature entry

@MainActor
enum AgentsFeature {
    static let settings = Setting("agentsSettings", default: AgentsSettings())

    static func start() {
        AgentStore.shared.refreshHookStatus()
        AgentStore.shared.listening = AgentBridgeServer.start(path: AgentBridgeServer.socketPath) { data in
            DispatchQueue.main.async { MainActor.assumeIsolated { AgentStore.shared.receive(data) } }
        }
    }

    static func selfTest() {
        func ev(_ s: String) -> HookEvent { HookEvent(json: Data(s.utf8))! }
        let p = ev(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/proj","prompt":"Fix the bug\nmore"}"#)
        assert(p.kind == .prompt("Fix the bug\nmore") && p.cwd == "/tmp/proj")
        let pre = ev(#"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Edit","tool_use_id":"u1","tool_input":{"file_path":"/a/b.swift","old_string":"x"}}"#)
        assert(pre.kind == .toolStart(.edit, tool: "Edit", subject: "/a/b.swift") && pre.toolUseID == "u1")
        let bash = ev(#"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash","tool_input":{"command":"swift build\necho hi"}}"#)
        assert(bash.kind == .toolStart(.command, tool: "Bash", subject: "swift build"))
        assert(ev(#"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Glob","tool_input":{"pattern":"**/*.md"}}"#).kind
               == .toolStart(.search, tool: "Glob", subject: "**/*.md"))
        assert(AgentStep.Kind(tool: "WebSearch") == .web && AgentStep.Kind(tool: "Task") == .task && AgentStep.Kind(tool: "mcp__x") == .other)
        let post = ev(#"{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"Edit","tool_use_id":"u1","tool_response":{"success":true}}"#)
        let perm = ev(#"{"hook_event_name":"Notification","session_id":"s1","message":"Claude needs your permission to use Bash"}"#)
        assert(perm.kind == .attention("Claude needs your permission to use Bash", permission: true))
        assert(ev(#"{"hook_event_name":"Notification","session_id":"s1","message":"Claude is waiting for your input"}"#).kind
               == .attention("Claude is waiting for your input", permission: false))
        assert(ev(#"{"hook_event_name":"SessionEnd","session_id":"s1"}"#).kind == .end)
        assert(HookEvent(json: Data("{}".utf8)) == nil && HookEvent(json: Data("nope".utf8)) == nil)

        var s = AgentSession(id: "s1", cwd: "/tmp/proj")
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for (i, e) in [p, pre, bash].enumerated() { s.apply(e.kind, toolUseID: e.toolUseID, at: t0 + Double(i)) }
        assert(s.phase == .working && s.steps.count == 2 && s.title == "Fix the bug" && s.prompt == "Fix the bug\nmore" && s.project == "proj")
        assert(s.turns == 1 && s.toolCount == 2 && s.kindCounts[.edit] == 1 && s.kindCounts[.command] == 1 && s.files == ["/a/b.swift"])
        assert(AgentStore.mood([s], at: t0 + 3) == .working(.command))
        s.apply(post.kind, toolUseID: post.toolUseID, at: t0 + 4)
        assert(s.steps[0].state == .done && s.steps[1].state == .running && s.currentLine == "Run swift build")
        assert(s.steps[0].endedAt == t0 + 4 && s.steps[0].duration() == 3)
        s.apply(.toolEnd(tool: "Bash", failed: true), toolUseID: nil, at: t0 + 5)
        assert(s.failures == 1 && s.steps[1].state == .failed && AgentStore.mood([s], at: t0 + 6) == .oops)
        assert(AgentStore.mood([s], at: t0 + 20) == .thinking)
        s.apply(perm.kind, toolUseID: nil, at: t0 + 21)
        assert(s.phase == .needsPermission && s.currentLine.contains("permission") && AgentStore.mood([s], at: t0 + 21) == .alert)
        s.apply(ev(#"{"hook_event_name":"Stop","session_id":"s1"}"#).kind, toolUseID: nil, at: t0 + 30)
        assert(s.phase == .done && s.steps.allSatisfy { $0.state != .running } && s.elapsed(at: t0 + 999) == 30)
        assert(AgentStore.mood([s], at: t0 + 32) == .celebrating && AgentStore.mood([s], at: t0 + 60) == .idle)
        assert(AgentStore.mood([s], at: t0 + 600) == .sleeping && AgentStore.mood([], at: t0) == .sleeping)
        s.apply(ev(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"Again"}"#).kind, toolUseID: nil, at: t0 + 40)
        assert(s.turns == 2 && s.toolCount == 0 && s.files.isEmpty && s.steps.isEmpty)
        assert(AgentStep(id: "", kind: .read, tool: "Read", subject: "/x/y.txt").title == "Read y.txt")
        let nested = AgentStep(id: "", kind: .edit, tool: "Edit", subject: "/tmp/proj/Sources/App/main.swift")
        assert(nested.detail(relativeTo: "/tmp/proj") == "Sources/App" && AgentStep(id: "", kind: .edit, tool: "Edit", subject: "/tmp/proj/a.swift").detail(relativeTo: "/tmp/proj") == nil)

        // Settings saved by older versions decode, and pre-pet Grid moves to Focus.
        let old = try! JSONDecoder().decode(AgentsSettings.self, from: Data(#"{"enabled":true,"layout":"grid","showWorkingActivity":false,"notifyFinished":true,"notifyAttention":true,"playsSound":true}"#.utf8))
        assert(old.layout == .focus && old.playsSound && !old.showWorkingActivity && old.showPet)
        let new = try! JSONDecoder().decode(AgentsSettings.self, from: JSONEncoder().encode(AgentsSettings(layout: .grid, showPet: false)))
        assert(new.layout == .grid && !new.showPet)

        // Hook merge keeps foreign hooks, is idempotent, and removes cleanly.
        let foreign: [String: Any] = ["model": "x", "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "rtk hook"]]]]]]
        let once = HookInstaller.merged(foreign, add: true, command: "'/x/notchly-hook.sh'")!
        let twice = HookInstaller.merged(once, add: true, command: "'/x/notchly-hook.sh'")!
        assert(HookInstaller.isInstalled(twice) && !HookInstaller.isInstalled(foreign))
        assert(((twice["hooks"] as! [String: Any])["PreToolUse"] as! [Any]).count == 2)
        assert(((twice["hooks"] as! [String: Any])["Stop"] as! [Any]).count == 1)
        let removed = HookInstaller.merged(twice, add: false)!
        assert(NSDictionary(dictionary: removed).isEqual(to: foreign))
        assert(HookInstaller.merged(["hooks": "bad"], add: true) == nil)

        // End to end: generated hook script → nc → socket server.
        let sock = NSTemporaryDirectory() + "notchly-test-\(getpid()).sock"
        let got = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var data = Data() }
        let received = Box()
        assert(AgentBridgeServer.start(path: sock) { received.data = $0; got.signal() })
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", HookInstaller.script(socket: sock)]
        let pipe = Pipe()
        proc.standardInput = pipe
        try! proc.run()
        pipe.fileHandleForWriting.write(Data(#"{"hook_event_name":"Stop","session_id":"e2e"}"#.utf8))
        try! pipe.fileHandleForWriting.close()
        assert(got.wait(timeout: .now() + 3) == .success)
        proc.waitUntilExit()
        assert(proc.terminationStatus == 0 && HookEvent(json: received.data)?.sessionID == "e2e")
        unlink(sock)

        AIUsageScanner.selfTest()
        PulseSampler.selfTest()
    }
}

// MARK: - Settings pane

struct AgentsPane: View {
    var body: some View {
        let s = AgentsFeature.settings
        let store = AgentStore.shared
        SettingsPane(title: "Agents") {
            SettingsCard {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Theme.claude.opacity(0.16))
                        PetView(mood: store.hooksInstalled ? .celebrating : .sleeping, size: 64, animated: s.value.showPet)
                    }
                    .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.hooksInstalled ? "Claude Code is connected" : "Connect Claude Code").font(.headline)
                        Text(store.hooksInstalled
                             ? "New sessions appear in the Agents tab. The pet in the notch shows what each one is doing."
                             : "Notchly adds a small script to your Claude Code hooks so the notch can follow each session. Your other hooks stay, and the first time a backup is saved as settings.json.notchly-backup.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if let error = store.hookError { Text(error).font(.caption).foregroundStyle(.red) }
                        HStack {
                            Button(store.hooksInstalled ? "Reinstall Hooks" : "Install Hooks") { store.setHooks(installed: true) }
                                .buttonStyle(.borderedProminent).tint(Theme.claude)
                            if store.hooksInstalled { Button("Remove Hooks") { store.setHooks(installed: false) } }
                        }
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
            }
            SettingsCard(title: "Status") {
                SettingsRow(title: "Hooks", subtitle: store.hooksInstalled ? "Installed in ~/.claude/settings.json" : "Not installed") {
                    Image(systemName: store.hooksInstalled ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(store.hooksInstalled ? .green : .secondary)
                }
                Divider()
                SettingsRow(title: "Notch bridge", subtitle: AgentBridgeServer.socketPath) {
                    Text(store.listening ? "Listening" : "Not running").foregroundStyle(.secondary)
                }
                Divider()
                SettingsRow(title: "Events", subtitle: HookInstaller.events.joined(separator: ", ")) { EmptyView() }
            }
            SettingsCard(title: "Agents tab") {
                SettingsRow(title: "Show agent sessions") { Toggle("", isOn: s.binding(\.enabled)).labelsHidden().toggleStyle(.switch) }
                Divider()
                SettingsRow(title: "Layout", subtitle: "Focus shows one session in depth; Grid and List show them all.") {
                    Picker("", selection: s.binding(\.layout)) {
                        ForEach(AgentsSettings.Layout.allCases, id: \.self) { Text($0.title) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 190)
                }
                Divider()
                SettingsRow(title: "Claude pet", subtitle: "A companion that reacts as the agent thinks, works, needs you and finishes.") {
                    Toggle("", isOn: s.binding(\.showPet)).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsCard(title: "Notch alerts") {
                SettingsRow(title: "Working live activity", subtitle: "The pet (or a spinner) beside the notch while an agent works") {
                    Toggle("", isOn: s.binding(\.showWorkingActivity)).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsRow(title: "Alert when an agent needs you") { Toggle("", isOn: s.binding(\.notifyAttention)).labelsHidden().toggleStyle(.switch) }
                Divider()
                SettingsRow(title: "Show when an agent finishes") { Toggle("", isOn: s.binding(\.notifyFinished)).labelsHidden().toggleStyle(.switch) }
                Divider()
                SettingsRow(title: "Play a sound on alerts") { Toggle("", isOn: s.binding(\.playsSound)).labelsHidden().toggleStyle(.switch) }
            }
        }
        .onAppear { store.refreshHookStatus() }
    }
}
