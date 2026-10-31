import SwiftUI

// MARK: - Model (same case names as NotchNook's AgentPhase / AgentStep.Kind / AgentStep.State)

enum AgentPhase: String, Codable { case thinking, working, needsPermission, needsInput, done, idle
    var needsAttention: Bool { self == .needsPermission || self == .needsInput }
    var isBusy: Bool { self == .thinking || self == .working }
}

struct AgentStep: Identifiable, Equatable {
    enum Kind: String, Codable { case read, edit, write, command, search, web, task, question, other
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
    }
    enum State: String, Codable { case running, done, failed }

    var id: String
    var kind: Kind
    var tool: String
    var subject: String
    var state: State = .running

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
            kind = .prompt(String(p.split(separator: "\n").first ?? ""))
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
    var title = ""
    var phase: AgentPhase = .idle
    var message = ""
    var steps: [AgentStep] = []
    var startedAt = Date()
    var updatedAt = Date()

    var project: String { cwd.isEmpty ? "Claude Code" : URL(fileURLWithPath: cwd).lastPathComponent }
    var currentLine: String {
        if phase.needsAttention { return message.isEmpty ? "Needs your input" : message }
        if let s = steps.last(where: { $0.state == .running }) { return s.title }
        return phase == .thinking ? "Thinking…" : (steps.last?.title ?? title)
    }

    mutating func apply(_ e: HookEvent.Kind, toolUseID: String?, at now: Date = Date()) {
        updatedAt = now
        switch e {
        case .prompt(let p):
            title = p; phase = .thinking; message = ""; steps = []; startedAt = now
        case .toolStart(let kind, let tool, let subject):
            phase = .working
            steps.append(AgentStep(id: toolUseID ?? UUID().uuidString, kind: kind, tool: tool, subject: subject))
            if steps.count > 50 { steps.removeFirst(steps.count - 50) }
        case .toolEnd(let tool, let failed):
            let i = steps.lastIndex { toolUseID != nil ? $0.id == toolUseID : ($0.tool == tool && $0.state == .running) }
            if let i { steps[i].state = failed ? .failed : .done }
            phase = .working; message = ""
        case .attention(let msg, let permission):
            phase = permission ? .needsPermission : .needsInput; message = msg
        case .stop:
            phase = .done; message = ""
            for i in steps.indices where steps[i].state == .running { steps[i].state = .done }
        case .end, .other: break
        }
    }
}

struct AgentsSettings: Codable, Equatable {
    enum Layout: String, Codable, CaseIterable { case grid, list }
    var enabled = true
    var layout: Layout = .grid
    var showWorkingActivity = true
    var notifyFinished = true
    var notifyAttention = true
    var playsSound = false
}

// MARK: - Store + live activities

@MainActor @Observable
final class AgentStore {
    static let shared = AgentStore()
    private(set) var sessions: [String: AgentSession] = [:]
    var listening = false

    var sorted: [AgentSession] { sessions.values.sorted { $0.startedAt > $1.startedAt } }

    init() {
        if CommandLine.arguments.contains("--snapshot") { seedDemo() }
    }

    func receive(_ data: Data) {
        guard AgentsFeature.settings.value.enabled, let e = HookEvent(json: data) else { return }
        if e.kind == .end { sessions[e.sessionID] = nil; refreshActivities(); return }
        var s = sessions[e.sessionID] ?? AgentSession(id: e.sessionID, cwd: e.cwd)
        let wasAttention = s.phase.needsAttention
        if !e.cwd.isEmpty { s.cwd = e.cwd }
        s.apply(e.kind, toolUseID: e.toolUseID)
        sessions[e.sessionID] = s
        refreshActivities()
        let set = AgentsFeature.settings.value
        if s.phase.needsAttention, !wasAttention, set.playsSound { NSSound(named: "Ping")?.play() }
        if e.kind == .stop, set.notifyFinished, !sessions.values.contains(where: \.phase.needsAttention) {
            LiveActivityCenter.shared.show(LiveActivity(
                kind: .agentAlert, priority: 90, leadingWidth: 24, trailingWidth: 70,
                leading: AnyView(Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.green)),
                trailing: AnyView(Text(s.project).font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.green).lineLimit(1))
            ), duration: 4)
        }
    }

    func dismiss(_ id: String) { sessions[id] = nil; refreshActivities() }

    private func refreshActivities() {
        let set = AgentsFeature.settings.value
        let center = LiveActivityCenter.shared
        if set.notifyAttention, let s = sorted.first(where: \.phase.needsAttention) {
            center.show(LiveActivity(
                kind: .agentAlert, priority: 90, leadingWidth: 24, trailingWidth: 70,
                leading: AnyView(Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)),
                trailing: AnyView(Text(s.phase == .needsPermission ? "Allow?" : "Input").font(Theme.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent).lineLimit(1))
            ))
        } else {
            center.remove(.agentAlert)
        }
        if set.showWorkingActivity, let s = sorted.first(where: \.phase.isBusy) {
            center.show(LiveActivity(
                kind: .agentWorking, priority: 60, leadingWidth: 24, trailingWidth: 44,
                leading: AnyView(ProgressView().controlSize(.mini).tint(Theme.accent)),
                trailing: AnyView(HStack(spacing: 3) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .bold))
                    Text("\(s.steps.count)").monospacedDigit()
                }.font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.accent))
            ))
        } else {
            center.remove(.agentWorking)
        }
    }

    private func seedDemo() {
        var a = AgentSession(id: "demo1", cwd: "/Users/me/Notchly")
        a.apply(.prompt("Add a teleprompter tab"), toolUseID: nil)
        a.apply(.toolStart(.read, tool: "Read", subject: "/Users/me/Notchly/Core/Design.swift"), toolUseID: "t1")
        a.apply(.toolEnd(tool: "Read", failed: false), toolUseID: "t1")
        a.apply(.toolStart(.edit, tool: "Edit", subject: "/Users/me/Notchly/Features/Prompter.swift"), toolUseID: "t2")
        a.apply(.toolEnd(tool: "Edit", failed: false), toolUseID: "t2")
        a.apply(.toolStart(.command, tool: "Bash", subject: "swift build"), toolUseID: "t3")
        var b = AgentSession(id: "demo2", cwd: "/Users/me/website")
        b.apply(.prompt("Fix the header layout"), toolUseID: nil)
        b.apply(.toolStart(.command, tool: "Bash", subject: "rm -rf dist"), toolUseID: "t4")
        b.apply(.attention("Claude needs your permission to use Bash", permission: true), toolUseID: nil)
        sessions = [a.id: a, b.id: b]
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
        AgentStore.shared.listening = AgentBridgeServer.start(path: AgentBridgeServer.socketPath) { data in
            DispatchQueue.main.async { MainActor.assumeIsolated { AgentStore.shared.receive(data) } }
        }
    }

    static func selfTest() {
        func ev(_ s: String) -> HookEvent { HookEvent(json: Data(s.utf8))! }
        let p = ev(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/proj","prompt":"Fix the bug\nmore"}"#)
        assert(p.kind == .prompt("Fix the bug") && p.cwd == "/tmp/proj")
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
        for e in [p, pre, bash] { s.apply(e.kind, toolUseID: e.toolUseID) }
        assert(s.phase == .working && s.steps.count == 2 && s.title == "Fix the bug" && s.project == "proj")
        s.apply(post.kind, toolUseID: post.toolUseID)
        assert(s.steps[0].state == .done && s.steps[1].state == .running && s.currentLine == "Run swift build")
        s.apply(perm.kind, toolUseID: nil)
        assert(s.phase == .needsPermission && s.currentLine.contains("permission"))
        s.apply(ev(#"{"hook_event_name":"Stop","session_id":"s1"}"#).kind, toolUseID: nil)
        assert(s.phase == .done && s.steps.allSatisfy { $0.state == .done })
        assert(AgentStep(id: "", kind: .read, tool: "Read", subject: "/x/y.txt").title == "Read y.txt")

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

// MARK: - Tab view

struct AgentsView: View {
    var body: some View {
        let sessions = AgentStore.shared.sorted
        if sessions.isEmpty {
            EmptyState(symbol: "sparkles", title: "No agent sessions",
                       subtitle: "Connect Claude Code in Settings → Agents, then start a session in your terminal.")
        } else {
            let cols = AgentsFeature.settings.value.layout == .grid ? 2 : 1
            let grid = Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(Array(stride(from: 0, to: sessions.count, by: cols)), id: \.self) { i in
                    GridRow(alignment: .top) {
                        ForEach(sessions[i..<min(i + cols, sessions.count)]) { AgentCard(session: $0, compact: cols == 1) }
                    }
                }
            }
            ViewThatFits(in: .vertical) {
                grid.frame(maxHeight: .infinity, alignment: .top)
                ScrollView(showsIndicators: false) { grid }
            }
        }
    }
}

private struct AgentCard: View {
    let session: AgentSession
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "asterisk")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0xD97757))
                    .frame(width: 26, height: 26).background(Theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.project).font(Theme.title(13)).lineLimit(1)
                    Text(session.title.isEmpty ? "Claude Code" : session.title).font(Theme.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 4)
                PhaseBadge(phase: session.phase)
            }
            HStack(spacing: 6) {
                Text(session.currentLine).font(Theme.body).lineLimit(1)
                    .foregroundStyle(session.phase.needsAttention ? Theme.accent : .white)
                Spacer(minLength: 4)
                Group {
                    if session.phase.isBusy || session.phase.needsAttention {
                        Text(session.startedAt, style: .timer)
                    } else {
                        Text(Duration.seconds(session.updatedAt.timeIntervalSince(session.startedAt)).formatted(.time(pattern: .minuteSecond)))
                    }
                }
                .font(Theme.caption).monospacedDigit().foregroundStyle(Theme.tertiaryText)
            }
            if !compact {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(session.steps.suffix(3).reversed()) { step in
                        HStack(spacing: 6) {
                            Image(systemName: step.state == .failed ? "xmark" : step.kind.symbol)
                                .frame(width: 14)
                                .foregroundStyle(step.state == .failed ? .red : Theme.secondaryText)
                            Text(step.title).lineLimit(1)
                            Spacer(minLength: 0)
                            if step.state == .running { ProgressView().controlSize(.mini) }
                        }
                        .font(Theme.caption)
                        .foregroundStyle(step.state == .running ? .white : Theme.secondaryText)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.widgetRadius, style: .continuous))
        .contextMenu { Button("Dismiss") { AgentStore.shared.dismiss(session.id) } }
    }
}

private struct PhaseBadge: View {
    let phase: AgentPhase
    var body: some View {
        switch phase {
        case .thinking, .working:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(phase == .thinking ? "Thinking" : "Working")
            }
            .font(Theme.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.chip, in: Capsule())
        case .needsInput: Chip(title: "Needs input", symbol: "exclamationmark.bubble.fill", tint: .black, fill: Theme.accent)
        case .needsPermission: Chip(title: "Allow?", symbol: "hand.raised.fill", tint: .black, fill: Theme.accent)
        case .done: Chip(title: "Done", symbol: "checkmark", tint: .black, fill: Theme.green)
        case .idle: Chip(title: "Idle")
        }
    }
}

// MARK: - Settings pane

struct AgentsPane: View {
    @State private var installed = false
    @State private var error: String?

    var body: some View {
        let s = AgentsFeature.settings
        SettingsPane(title: "Agents") {
            SettingsCard(title: "Claude Code") {
                SettingsRow(title: "Hooks", subtitle: installed ? "Installed in ~/.claude/settings.json" : "Not installed") {
                    Image(systemName: installed ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(installed ? .green : .secondary)
                }
                SettingsRow(title: "Notch bridge", subtitle: AgentBridgeServer.socketPath) {
                    Text(AgentStore.shared.listening ? "Listening" : "Not running").foregroundStyle(.secondary)
                }
                HStack {
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Spacer()
                    Button("Remove hooks") { run(add: false) }.disabled(!installed)
                    Button(installed ? "Reinstall hooks" : "Install hooks") { run(add: true) }.buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 6)
                Text("Adds a small script to the UserPromptSubmit, PreToolUse, PostToolUse, Notification, Stop and SessionEnd hooks. Existing hooks stay; a backup is saved as settings.json.notchly-backup. New Claude Code sessions pick it up.")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
            }
            SettingsCard(title: "Behavior") {
                SettingsRow(title: "Show agent sessions") { Toggle("", isOn: s.binding(\.enabled)).labelsHidden() }
                SettingsRow(title: "Layout") {
                    Picker("", selection: s.binding(\.layout)) {
                        ForEach(AgentsSettings.Layout.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 140)
                }
                SettingsRow(title: "Working live activity", subtitle: "Spinner beside the notch while an agent works") {
                    Toggle("", isOn: s.binding(\.showWorkingActivity)).labelsHidden()
                }
                SettingsRow(title: "Alert when an agent needs you") { Toggle("", isOn: s.binding(\.notifyAttention)).labelsHidden() }
                SettingsRow(title: "Show when an agent finishes") { Toggle("", isOn: s.binding(\.notifyFinished)).labelsHidden() }
                SettingsRow(title: "Play a sound on alerts") { Toggle("", isOn: s.binding(\.playsSound)).labelsHidden() }
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        installed = (try? HookInstaller.isInstalled(HookInstaller.loadSettings())) ?? false
    }

    private func run(add: Bool) {
        do { try HookInstaller.apply(add: add); error = nil } catch { self.error = error.localizedDescription }
        refresh()
    }
}
