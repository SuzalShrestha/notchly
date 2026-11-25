import SwiftUI

// MARK: - Model (same case names as NotchNook's AgentPhase / AgentStep.Kind / AgentStep.State)

enum AgentPhase: String, Codable { case thinking, working, needsPermission, needsInput, done, stopped, idle
    var needsAttention: Bool { self == .needsPermission || self == .needsInput }
    var isBusy: Bool { self == .thinking || self == .working }

    var label: String {
        switch self {
        case .thinking: "Thinking"
        case .working: "Working"
        case .needsPermission: "Allow?"
        case .needsInput: "Needs input"
        case .done: "Done"
        case .stopped: "Stopped"
        case .idle: "Idle"
        }
    }

    var color: Color {
        switch self {
        case .thinking, .working: Theme.claude
        case .needsPermission, .needsInput: Theme.warning
        case .done: Theme.success
        case .stopped, .idle: Theme.tertiaryText
        }
    }
}

struct AgentStep: Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case read, edit, write, command, search, web, task, question, other
        /// Claude Code, Gemini CLI, Codex, Grok Build, Antigravity and Factory Droid tool names.
        init(tool: String) {
            switch tool {
            case "Read", "NotebookRead", "read_file", "read_many_files", "view_file", "view_file_outline", "view_code_item": self = .read
            case "Edit", "MultiEdit", "NotebookEdit", "replace", "apply_patch", "ApplyPatch", "search_replace", "hashline_edit",
                 "replace_file_content", "multi_replace_file_content": self = .edit
            case "Write", "write_file", "write", "write_to_file", "Create": self = .write
            case "Bash", "BashOutput", "run_shell_command", "shell", "exec_command", "run_terminal_command", "run_command",
                 "send_command_input", "command_status", "Execute": self = .command
            case "Grep", "Glob", "LS", "glob", "search_file_content", "list_directory", "grep", "list_dir", "grep_search",
                 "find_by_name", "codebase_search": self = .search
            case "WebFetch", "WebSearch", "google_web_search", "web_fetch", "web_search", "search_web", "read_url_content",
                 "FetchUrl": self = .web
            case "Task", "Agent", "spawn_subagent": self = .task
            case "AskUserQuestion": self = .question
            default: self = tool.hasPrefix("browser_") ? .web : .other
            }
        }
        var symbol: String {
            switch self {
            case .read: "doc.text"; case .edit: "pencil"; case .write: "square.and.pencil"; case .command: "terminal"
            case .search: "magnifyingglass"; case .web: "globe"; case .task: "person.2"; case .question: "questionmark.bubble"
            case .other: "wrench.and.screwdriver"
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

    /// What the step does, in words for someone who does not read code.
    var title: String {
        let file = subject.hasPrefix("/") ? URL(fileURLWithPath: subject).lastPathComponent : subject
        switch kind {
        case .read: return file.isEmpty ? "Reading files" : "Reading \(file)"
        case .edit: return file.isEmpty ? "Updating code" : "Updating \(file)"
        case .write: return file.isEmpty ? "Creating a file" : "Creating \(file)"
        case .command: return Self.describe(command: subject)
        case .search: return subject.isEmpty ? "Searching the project" : "Looking for \u{201C}\(subject)\u{201D}"
        case .web:
            if tool.localizedCaseInsensitiveContains("search") { return subject.isEmpty ? "Researching online" : "Researching \u{201C}\(subject)\u{201D}" }
            return URL(string: subject)?.host.map { "Reading \($0)" } ?? "Reading a web page"
        case .task: return subject.isEmpty ? "Asking a helper agent" : "Helper: \(subject)"
        case .question: return "Asking you a question"
        case .other: return Self.describe(tool: tool, subject: subject)
        }
    }

    /// First rule whose pattern matches the command; `rtk git push` still reads as git. The act is what the mascot plays.
    private static let commandRules: [(String, String, PetAct)] = [
        ("Saving a checkpoint", #"\bgit (commit|add)\b"#, .git),
        ("Sharing changes", #"\bgit push\b|\bgh pr\b"#, .ship),
        ("Checking the change history", #"\bgit\b"#, .git),
        ("Running tests", #"\b(test|tests|pytest|jest|vitest|rspec|selftest)\b"#, .test),
        ("Building the project", #"\b(build|make|tsc|xcodebuild|compile|cargo b)\b"#, .build),
        ("Installing packages", #"\b(install|npm i|pnpm add|yarn add|pip|brew|pod)\b"#, .install),
        ("Deleting files", #"\brm\b"#, .delete),
        ("Downloading from the web", #"\b(curl|wget)\b"#, .download),
        ("Moving files", #"\b(mv|cp|mkdir)\b"#, .terminal),
        ("Looking through files", #"\b(ls|cat|find|grep|rg|head|tail|wc|sed|tree)\b"#, .search),
    ]

    private static func rule(_ command: String) -> (String, String, PetAct)? {
        commandRules.first { command.range(of: $0.1, options: [.regularExpression, .caseInsensitive]) != nil }
    }
    static func describe(command: String) -> String { rule(command)?.0 ?? "Running a command" }
    static func act(command: String) -> PetAct { rule(command)?.2 ?? .terminal }

    /// `mcp__github__create_issue` → "Using Github: create issue"; other tools by name.
    static func describe(tool: String, subject: String) -> String {
        let parts = tool.components(separatedBy: "__")
        if parts.count >= 3, parts[0] == "mcp" {
            let server = parts[1]
            // Connector IDs are UUIDs, which mean nothing to a reader.
            let app = server.count > 24 || server.filter(\.isNumber).count > 4 ? "a connected app" : humanize(server).capitalized
            return "Using \(app): \(humanize(parts[2...].joined(separator: " ")))"
        }
        switch tool {
        case "Skill": return subject.isEmpty ? "Using a skill" : "Using the \(subject) skill"
        case "EnterPlanMode": return "Making a plan"
        case "ExitPlanMode": return "Sharing the plan"
        default: return "Using \(humanize(tool))"
        }
    }

    /// snake_case, kebab-case and CamelCase to lowercase words.
    static func humanize(_ s: String) -> String {
        var out = ""
        for (i, c) in s.enumerated() {
            if c == "_" || c == "-" { out.append(" "); continue }
            if c.isUppercase, i > 0, let p = out.last, p.isLowercase { out.append(" ") }
            out.append(c)
        }
        return out.lowercased()
    }
}

/// One item of the agent's own task list (Claude Code's TodoWrite, or TaskCreate / TaskUpdate).
struct AgentTodo: Equatable {
    enum Status: String { case pending, inProgress = "in_progress", completed, deleted }
    var id: String
    var text: String
    /// Present-tense form shown while the item runs ("Running tests").
    var active: String
    var status: Status = .pending

    var label: String { status == .inProgress && !active.isEmpty ? active : text }
}

/// Which coding agent sent the events. Each one has its own mascot.
enum Harness: String, Codable, CaseIterable {
    case claude, codex, gemini, grok, antigravity, droid
    var name: String {
        switch self {
        case .claude: "Claude Code"; case .codex: "Codex"; case .gemini: "Gemini CLI"
        case .grok: "Grok Build"; case .antigravity: "Antigravity"; case .droid: "Factory Droid"
        }
    }
    var short: String {
        switch self {
        case .claude: "Claude"; case .codex: "Codex"; case .gemini: "Gemini"
        case .grok: "Grok"; case .antigravity: "Antigravity"; case .droid: "Droid"
        }
    }
    var tint: Color {
        switch self {
        case .claude: Theme.claude; case .codex: Color(hex: 0xE6E6E6); case .gemini: Color(hex: 0x6E9BFF)
        case .grok: Color(hex: 0xB9B9C6); case .antigravity: Color(hex: 0x3FC1C9); case .droid: Color(hex: 0xFF8A3D)
        }
    }

    /// `agent` is the name the hook script was given; otherwise the payload tells: Antigravity sends a
    /// conversationId, Grok camelCase keys beside Claude's, Gemini its own event names, and every
    /// agent keeps transcripts in its own dot folder.
    init(payload o: [String: Any], event: String, agent: String? = nil) {
        if let agent, let h = Harness(rawValue: agent) { self = h; return }
        let transcript = (o["transcript_path"] ?? o["transcriptPath"]) as? String ?? ""
        if o["conversationId"] != nil || transcript.contains("/.gemini/antigravity") { self = .antigravity }
        else if transcript.contains("/.factory/") { self = .droid }
        else if o["hookEventName"] != nil || transcript.contains("/.grok/") { self = .grok }
        else if transcript.contains("/.gemini/") || ["BeforeTool", "AfterTool", "BeforeAgent", "AfterAgent"].contains(event) { self = .gemini }
        else if transcript.contains("/.codex/") { self = .codex }
        else { self = .claude }
    }
}

/// One Claude Code hook payload (hook_event_name, session_id, cwd, tool_name, tool_input, prompt, message, …).
struct HookEvent {
    enum Kind: Equatable {
        case prompt(String)
        case toolStart(AgentStep.Kind, tool: String, subject: String)
        case toolEnd(tool: String, failed: Bool)
        case attention(String, permission: Bool)
        /// TodoWrite: the whole list. TaskCreate / TaskUpdate: one item.
        case plan([AgentTodo])
        case planAdd(text: String, active: String)
        case planUpdate(id: String, status: AgentTodo.Status)
        /// You pressed Esc: Claude Code sends no hook for it, Notchly reads it from the transcript.
        case stop, interrupted, end, other
        /// Antigravity calls the model again: the tools it ran are finished (it sends no PostToolUse).
        case settle
    }
    var sessionID: String
    var cwd: String
    var transcriptPath = ""
    var toolUseID: String?
    var harness: Harness
    var kind: Kind

    /// Claude-style snake_case payloads, Grok's camelCase beside them, and Antigravity's own
    /// (`conversationId`, `toolCall`). Agents whose payload has no event name come wrapped by the hook
    /// script: `{"notchly":{"agent":…,"event":…},"payload":{…}}`.
    init?(json data: Data) {
        guard var o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var agent: String?, event = ""
        if let env = o["notchly"] as? [String: Any], let inner = o["payload"] as? [String: Any] {
            agent = env["agent"] as? String; event = env["event"] as? String ?? ""; o = inner
        }
        func str(_ keys: String...) -> String? { keys.lazy.compactMap { o[$0] as? String }.first }
        let call = o["toolCall"] as? [String: Any] ?? [:]
        let name = event.isEmpty ? str("hook_event_name") ?? "" : event
        // A subagent's own events (Grok) would show up as a separate session.
        guard !name.isEmpty, let sid = str("session_id", "sessionId", "conversationId"), o["subagentType"] == nil else { return nil }
        sessionID = sid
        cwd = str("cwd") ?? (o["workspacePaths"] as? [String])?.first ?? ""
        toolUseID = str("tool_use_id", "toolUseId") ?? call["id"] as? String
        transcriptPath = str("transcript_path", "transcriptPath") ?? ""
        harness = Harness(payload: o, event: name, agent: agent)
        let tool = str("tool_name", "toolName") ?? call["name"] as? String ?? ""
        let input = (o["tool_input"] ?? o["toolInput"] ?? call["args"]) as? [String: Any] ?? [:]
        func text(_ key: String) -> String { String((input[key] as? String ?? "").prefix(200)) }
        switch name {
        case "UserPromptSubmit", "BeforeAgent":
            let p = (o["prompt"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            kind = .prompt(String(p.prefix(600)))
        case "PreInvocation":
            // Antigravity: the first model call of a turn starts it.
            let p = (o["lastUserInput"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            kind = (o["invocationNum"] as? Int ?? 0) == 0 ? .prompt(String(p.prefix(600))) : .settle
        case "PostInvocation":
            kind = .settle
        case "PreToolUse" where tool == "TodoWrite":
            let todos = (input["todos"] as? [[String: Any]] ?? []).prefix(50).enumerated().map { i, t in
                AgentTodo(id: "\(i + 1)", text: String((t["content"] as? String ?? "").prefix(200)),
                          active: String((t["activeForm"] as? String ?? "").prefix(200)),
                          status: AgentTodo.Status(rawValue: t["status"] as? String ?? "") ?? .pending)
            }
            kind = .plan(Array(todos))
        case "PreToolUse" where tool == "TaskCreate":
            kind = .planAdd(text: text("subject"), active: text("activeForm"))
        case "PreToolUse" where tool == "TaskUpdate":
            let id = input["taskId"] as? String ?? (input["taskId"] as? Int).map(String.init) ?? ""
            if let st = AgentTodo.Status(rawValue: text("status")) { kind = .planUpdate(id: id, status: st) } else { kind = .other }
        case "PreToolUse", "BeforeTool":
            let raw = ["file_path", "absolute_path", "target_file", "AbsolutePath", "TargetFile", "notebook_path", "command", "CommandLine",
                       "pattern", "url", "Url", "query", "Query", "description", "path", "SearchPath", "DirectoryPath", "skill", "prompt"]
                .lazy.compactMap { input[$0] as? String }.first ?? ""
            kind = .toolStart(AgentStep.Kind(tool: tool), tool: tool, subject: String(raw.split(separator: "\n").first ?? ""))
        case "PostToolUse", "AfterTool", "PostToolUseFailure":
            let r = (o["tool_response"] ?? o["toolResult"]) as? [String: Any]
            let failed = name == "PostToolUseFailure" || !(str("error") ?? "").isEmpty
                || (r?["is_error"] as? Bool) == true || (r?["success"] as? Bool) == false
            kind = .toolEnd(tool: tool, failed: failed)
        case "Notification":
            let msg = o["message"] as? String ?? ""
            let type = str("notification_type", "notificationType") ?? ""
            // Grok also tells hooks that a task finished; that is its Stop, not a request.
            kind = type == "task_complete" ? .other
                : .attention(msg, permission: type == "permission_prompt" || type == "ToolPermission" || msg.localizedCaseInsensitiveContains("permission"))
        case "Stop", "AfterAgent":
            // Grok sends one more Stop at shutdown, after SessionEnd; only `end_turn` ends a turn.
            if harness == .grok, let reason = str("reason"), reason != "end_turn" { kind = .other }
            else if !(str("error") ?? "").isEmpty { kind = .interrupted }   // Antigravity stopped on an error
            else { kind = .stop }
        case "StopCancelled", "StopFailure": kind = .interrupted   // Grok: you interrupted it, or the API failed
        case "SessionEnd": kind = .end
        default: kind = .other
        }
    }
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    var cwd: String
    var harness: Harness = .claude
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
    /// The agent's own task list; it spans turns, as it does in the agent.
    var plan: [AgentTodo] = []
    /// Claude Code's transcript and how far Notchly has read it, to see an Esc that sends no hook.
    var transcript = ""
    var transcriptOffset: UInt64 = 0

    var project: String { cwd.isEmpty ? harness.name : URL(fileURLWithPath: cwd).lastPathComponent }
    var visiblePlan: [AgentTodo] { plan.filter { $0.status != .deleted } }
    var runningStep: AgentStep? { steps.last { $0.state == .running } }
    /// What the agent waits for, in plain words: the step it wants to take, else its own message.
    var attentionLine: String {
        if phase == .needsPermission, let s = runningStep { return "OK to go ahead with \u{201C}\(s.title)\u{201D}?" }
        return message.isEmpty ? "Waiting for your reply" : message
    }

    var currentLine: String {
        if phase.needsAttention { return attentionLine }
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
        case .plan(let todos):
            plan = todos
        case .planAdd(let text, let active):
            plan.append(AgentTodo(id: "\(plan.count + 1)", text: text, active: active))
        case .planUpdate(let id, let status):
            if let i = plan.firstIndex(where: { $0.id == id }) { plan[i].status = status }
        case .stop:
            phase = .done; message = ""
            for i in steps.indices where steps[i].state == .running { steps[i].state = .done; steps[i].endedAt = now }
        case .interrupted:
            phase = .stopped; message = ""
            for i in steps.indices where steps[i].state == .running { steps[i].state = .failed; steps[i].endedAt = now }
        case .settle:
            // A model call with no turn running starts one (Antigravity may count calls across turns).
            if !phase.isBusy && !phase.needsAttention { apply(.prompt(""), toolUseID: nil, at: now); return }
            for i in steps.indices where steps[i].state == .running { steps[i].state = .done; steps[i].endedAt = now }
            phase = .thinking; message = ""
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
    /// Mascots walk over the desktop and drop out of the notch to tell you things.
    var roams = true
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
        roams = try c.decodeIfPresent(Bool.self, forKey: .roams) ?? d.roams
        // Before 1.1, Grid was the default and was saved with any other change: move those to the new Focus view.
        if !c.contains(.showPet), layout == .grid { layout = .focus }
    }
}

// MARK: - Store + live activities

@MainActor @Observable
final class AgentStore {
    static let shared = AgentStore()
    /// Oldest finished sessions are dropped beyond this, so a flood of fake session IDs cannot grow memory.
    static let maxSessions = 32
    private(set) var sessions: [String: AgentSession] = [:]
    var listening = false
    /// Session shown in the Focus layout; nil follows the one that needs you, else the newest.
    var selectedID: String?
    /// Agents whose hooks point at Notchly.
    private(set) var installed: Set<Harness> = []
    var hooksInstalled: Bool { !installed.isEmpty }
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
        if sessions[e.sessionID] == nil, sessions.count >= Self.maxSessions,
           let oldest = sessions.values.filter({ !$0.phase.isBusy && !$0.phase.needsAttention }).min(by: { $0.updatedAt < $1.updatedAt })
            ?? sessions.values.min(by: { $0.updatedAt < $1.updatedAt }) {
            sessions[oldest.id] = nil
            if selectedID == oldest.id { selectedID = nil }
        }
        var s = sessions[e.sessionID] ?? AgentSession(id: e.sessionID, cwd: e.cwd, harness: e.harness)
        let wasAttention = s.phase.needsAttention
        if !e.cwd.isEmpty { s.cwd = e.cwd }
        if !e.transcriptPath.isEmpty, e.transcriptPath != s.transcript { s.transcript = e.transcriptPath; s.transcriptOffset = 0 }
        // Everything up to here is before this event, so an old Esc there does not count.
        s.transcriptOffset = Self.fileSize(s.transcript) ?? s.transcriptOffset
        s.apply(e.kind, toolUseID: e.toolUseID)
        sessions[e.sessionID] = s
        let set = AgentsFeature.settings.value
        if s.phase.needsAttention, !wasAttention, set.playsSound { NSSound(named: "Ping")?.play() }
        if e.kind == .stop, set.notifyFinished, !needsAttention { showFinished(s.project) }
        refreshActivities()
    }

    // MARK: Interrupts

    nonisolated static let interruptMarker = Data("[Request interrupted by user".utf8)

    nonisolated static func fileSize(_ path: String) -> UInt64? {
        path.isEmpty ? nil : (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt64
    }

    /// Esc in Claude Code fires no Stop hook; it writes a user entry "[Request interrupted by user…]".
    /// ponytail: polls every 2 s while a session runs; a file watcher if that ever shows up in Instruments.
    func checkInterrupts() {
        // Other agents send their own stop event (Grok: StopCancelled) and write other transcript formats.
        for s in sessions.values where s.harness == .claude && (s.phase.isBusy || s.phase.needsAttention) && !s.transcript.isEmpty {
            guard let h = FileHandle(forReadingAtPath: s.transcript) else { continue }
            defer { try? h.close() }
            guard (try? h.seek(toOffset: s.transcriptOffset)) != nil, let data = try? h.readToEnd(), !data.isEmpty else { continue }
            // Read only whole lines; a line Claude Code is still writing is read again next time.
            guard let end = data.lastIndex(of: UInt8(ascii: "\n")) else { continue }
            var next = s
            next.transcriptOffset += UInt64(end - data.startIndex + 1)
            if Self.isInterrupt(data[...end]) { next.apply(.interrupted, toolUseID: nil) }
            sessions[s.id] = next
            if next.phase == .stopped { refreshActivities() }
        }
    }

    /// True if any whole JSONL line in `data` is Claude Code's own interrupt entry (not a tool result quoting it).
    nonisolated static func isInterrupt(_ data: Data) -> Bool {
        data.split(separator: UInt8(ascii: "\n")).contains { line in
            guard line.range(of: interruptMarker) != nil,
                  let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], o["type"] as? String == "user",
                  let content = (o["message"] as? [String: Any])?["content"] else { return false }
            let blocks = content as? [[String: Any]] ?? []
            let texts = (content as? String).map { [$0] } ?? blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            return texts.contains { $0.hasPrefix("[Request interrupted by user") }
        }
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
        installed = Set(HookTarget.all.filter { (try? HookInstaller.isInstalled(HookInstaller.load($0), $0)) ?? false }.map(\.harness))
    }

    func setHooks(_ harness: Harness = .claude, installed add: Bool) {
        guard let target = HookTarget.all.first(where: { $0.harness == harness }) else { return }
        do { try HookInstaller.apply(add: add, target: target); hookError = nil } catch { hookError = "\(harness.name): \(error.localizedDescription)" }
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
            if busy.phase == .working, let step = busy.runningStep { return .working(PetAct(step)) }
            return .thinking
        }
        if list.contains(where: { $0.phase == .done && now.timeIntervalSince($0.updatedAt) < 6 }) { return .celebrating }
        if list.contains(where: { $0.phase == .stopped && now.timeIntervalSince($0.updatedAt) < 6 }) { return .stopped }
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
        a.apply(.plan([AgentTodo(id: "1", text: "Find where tabs are defined", active: "", status: .completed),
                       AgentTodo(id: "2", text: "Add the countdown view", active: "", status: .completed),
                       AgentTodo(id: "3", text: "Build and test", active: "Building and testing", status: .inProgress),
                       AgentTodo(id: "4", text: "Update the README", active: "")]), toolUseID: nil, at: t0 + 1)
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
        var c = AgentSession(id: "demo3", cwd: "/Users/me/docs", harness: .gemini)
        c.apply(.prompt("Research notch sizes for every MacBook"), toolUseID: nil, at: t0 - 30)
        c.apply(.toolStart(.web, tool: "google_web_search", subject: "MacBook Pro notch height points"), toolUseID: "g1", at: t0 - 20)
        sessions = [a.id: a, b.id: b, c.id: c]
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
        // Connections are read in parallel (a slow client must not hold up Claude's hooks), at most 8 at a time.
        let slots = DispatchSemaphore(value: 8)
        let workers = DispatchQueue(label: "notchly.agents.bridge", attributes: .concurrent)
        Thread.detachNewThread {
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { if errno == EINTR || errno == ECONNABORTED { continue } else { break } }
                // Only our own user: the 0600 mode already says so, this also holds if the mode is ever loosened.
                var uid = uid_t(), gid = gid_t()
                guard getpeereid(c, &uid, &gid) == 0, uid == getuid() else { close(c); continue }
                slots.wait()
                workers.async {
                    if let data = readPayload(c) { onPayload(data) }
                    close(c)
                    slots.signal()
                }
            }
        }
        return true
    }

    static let maxPayload = 16 << 20

    /// Reads until EOF or until one complete JSON object has arrived (nc keeps the socket open until we close).
    private static func readPayload(_ c: Int32) -> Data? {
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var scan = JSONObjectEnd()
        var buf = [UInt8](repeating: 0, count: 65536)
        while data.count < maxPayload {
            let n = read(c, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
            if scan.feed(buf[0..<n]) { break }
        }
        return data.isEmpty || data.count > maxPayload ? nil : data
    }
}

/// Finds where a top-level JSON object ends in one pass over the bytes, without parsing them again per chunk.
struct JSONObjectEnd {
    private var depth = 0, started = false, inString = false, escaped = false

    /// Feeds the next bytes; true once the outermost `{…}` has closed.
    mutating func feed<S: Sequence>(_ bytes: S) -> Bool where S.Element == UInt8 {
        for b in bytes {
            if inString {
                if escaped { escaped = false } else if b == UInt8(ascii: "\\") { escaped = true } else if b == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch b {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1; started = true
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                if started && depth <= 0 { return true }
            default: break
            }
        }
        return false
    }
}

// MARK: - Hook installer (button press only; backs up each settings file first)

/// Where one agent reads its hooks, and which events Notchly listens to there.
struct HookTarget {
    let harness: Harness
    /// Settings file, under the home folder.
    let path: String
    let events: [String]
    /// Folders that show the agent is on this Mac.
    let homes: [String]
    /// Matcher for tool events; nil leaves it out (Codex and Grok then match every tool).
    var matcher: String? = "*"
    /// Passed to the hook script, which then wraps the payload with it; nil when the payload says who sent it.
    var agent: String?
    /// Antigravity: one named hook whose non-tool events take handlers directly, and no event name in the payload.
    var named = false
    /// Notchly's own file (Grok reads every file in its hooks folder): removed, not emptied.
    var ownFile = false

    static let toolEvents: Set = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "BeforeTool", "AfterTool"]
    private static let claudeEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    static let claude = HookTarget(harness: .claude, path: ".claude/settings.json", events: claudeEvents, homes: [".claude"])
    static let all: [HookTarget] = [
        claude,
        // Grok also runs ~/.claude/settings.json hooks; the same command in both places runs once.
        HookTarget(harness: .grok, path: ".grok/hooks/notchly.json",
                   events: ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification", "Stop",
                            "StopCancelled", "StopFailure", "SessionEnd"],
                   homes: [".grok"], matcher: nil, ownFile: true),
        HookTarget(harness: .antigravity, path: ".gemini/config/hooks.json",
                   events: ["PreInvocation", "PreToolUse", "PostToolUse", "PostInvocation", "Stop"],
                   homes: [".gemini/antigravity-cli", ".gemini/antigravity", ".antigravity"], agent: "antigravity", named: true),
        HookTarget(harness: .codex, path: ".codex/hooks.json", events: ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"],
                   homes: [".codex"], matcher: nil, agent: "codex"),
        HookTarget(harness: .gemini, path: ".gemini/settings.json",
                   events: ["BeforeAgent", "BeforeTool", "AfterTool", "AfterAgent", "Notification", "SessionEnd"],
                   homes: [".gemini/tmp", ".gemini/history"], agent: "gemini"),
        HookTarget(harness: .droid, path: ".factory/settings.json", events: claudeEvents, homes: [".factory"], agent: "droid"),
    ]

    var url: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path) }
    var isPresent: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return homes.contains { FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path) }
    }

    /// The hook command for one event: the script, then the agent and (for Antigravity) the event name.
    func command(_ event: String, script: String) -> String {
        [script, agent, named ? event : nil].compactMap { $0 }.joined(separator: " ")
    }
}

enum HookInstaller {
    static let marker = "notchly-hook.sh"
    static let namedKey = "notchly"
    static var scriptURL: URL { DataFile.folder.appendingPathComponent(marker) }
    static var command: String { shellQuoted(scriptURL.path) }

    /// One POSIX shell word: single quotes, with any `'` inside written as `'\''`.
    static func shellQuoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// With arguments (agent, event) the payload goes out wrapped, for agents that do not name themselves
    /// or the event; Antigravity reads a JSON reply, so that case prints `{}`.
    static func script(socket: String) -> String {
        let nc = "/usr/bin/nc -U -w 1 \(shellQuoted(socket)) >/dev/null 2>&1"
        return """
        #!/bin/sh
        # Notchly: forwards coding agent hook events to the notch. Never blocks the agent.
        if [ -n "$1" ]; then
          { printf '{"notchly":{"agent":"%s","event":"%s"},"payload":' "$1" "$2"; cat; printf '}'; } | \(nc)
          [ -n "$2" ] && printf '{}\\n'
        else
          \(nc)
        fi
        exit 0

        """
    }

    /// Rewrites an installed script, so a new version of the script reaches hooks installed before it.
    static func refreshScript() {
        guard FileManager.default.fileExists(atPath: scriptURL.path) else { return }
        try? script(socket: AgentBridgeServer.socketPath).write(to: scriptURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
    }

    private static func isOurs(_ handler: [String: Any]) -> Bool { (handler["command"] as? String)?.contains(marker) ?? false }

    /// Removes our entries from every event, then (if `add`) appends one group per event. nil = malformed hooks.
    static func merged(_ root: [String: Any], add: Bool, target t: HookTarget = .claude, command: String = HookInstaller.command) -> [String: Any]? {
        var root = root
        if t.named {
            guard root[namedKey] == nil || root[namedKey] is [String: Any] else { return nil }
            root[namedKey] = add ? Dictionary(uniqueKeysWithValues: t.events.map { e -> (String, [[String: Any]]) in
                let h: [String: Any] = ["type": "command", "command": t.command(e, script: command), "timeout": 5]
                return (e, HookTarget.toolEvents.contains(e) ? [["matcher": "*", "hooks": [h]]] : [h])
            }) : nil
            return root
        }
        guard var hooks = (root["hooks"] ?? [String: Any]()) as? [String: Any] else { return nil }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { return nil }
            let kept: [[String: Any]] = groups.compactMap { g in
                guard let hs = g["hooks"] as? [[String: Any]] else { return g }
                let rest = hs.filter { !isOurs($0) }
                if rest.count == hs.count { return g }
                if rest.isEmpty { return nil }
                var g = g; g["hooks"] = rest; return g
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        if add {
            for e in t.events {
                var g: [String: Any] = ["hooks": [["type": "command", "command": t.command(e, script: command), "timeout": 5]]]
                if HookTarget.toolEvents.contains(e), let m = t.matcher { g["matcher"] = m }
                hooks[e] = (hooks[e] as? [[String: Any]] ?? []) + [g]
            }
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return root
    }

    static func isInstalled(_ root: [String: Any], _ t: HookTarget = .claude) -> Bool {
        if t.named { return root[namedKey] is [String: Any] }
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        return t.events.allSatisfy { e in
            (hooks[e] as? [[String: Any]] ?? []).contains { g in (g["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs) }
        }
    }

    static func load(_ t: HookTarget) throws -> [String: Any] { try parse(try? Data(contentsOf: t.url), name: t.url.lastPathComponent) }

    private static func parse(_ data: Data?, name: String) throws -> [String: Any] {
        guard let data else { return [:] }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Notchly", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name) is not a JSON object"])
        }
        return o
    }

    static func apply(add: Bool, target t: HookTarget) throws {
        let fm = FileManager.default
        let name = t.url.lastPathComponent
        // Write through a symlinked settings file (dotfile repos) instead of replacing the link with a file.
        let file = t.url.resolvingSymlinksInPath()
        let before = try? Data(contentsOf: file)
        guard let root = merged(try parse(before, name: name), add: add, target: t) else {
            throw NSError(domain: "Notchly", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(name) has an unexpected hooks layout; not changed"])
        }
        if t.ownFile, root.isEmpty {
            if before != nil { try fm.removeItem(at: file) }
            return
        }
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The first backup is kept as is: it is the file from before Notchly ever touched it.
        let backup = t.url.appendingPathExtension("notchly-backup")
        if before != nil, !t.ownFile, !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: file, to: backup) }
        if add {
            try script(socket: AgentBridgeServer.socketPath).write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        }
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        // Settings files can hold API keys: keep the file's mode (owner-only when new), not the umask default.
        let mode = (try? fm.attributesOfItem(atPath: file.path))?[.posixPermissions] as? NSNumber ?? 0o600
        // The agent may have saved the file since we read it; do not overwrite that change.
        guard (try? Data(contentsOf: file)) == before else {
            throw NSError(domain: "Notchly", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(name) changed while updating; try again"])
        }
        try out.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
    }
}

// MARK: - Feature entry

@MainActor
enum AgentsFeature {
    static let settings = Setting("agentsSettings", default: AgentsSettings())

    static func start() {
        HookInstaller.refreshScript()
        AgentStore.shared.refreshHookStatus()
        AgentStore.shared.listening = AgentBridgeServer.start(path: AgentBridgeServer.socketPath) { data in
            DispatchQueue.main.async { MainActor.assumeIsolated { AgentStore.shared.receive(data) } }
        }
        MascotRoamer.shared.start()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { AgentStore.shared.checkInterrupts() } }
    }

    static func selfTest() {
        func ev(_ s: String, line: Int = #line) -> HookEvent {
            guard let e = HookEvent(json: Data(s.utf8)) else { fatalError("line \(line): payload not parsed: \(s)") }
            return e
        }
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
        assert(AgentStore.mood([s], at: t0 + 3) == .working(.build))
        s.apply(post.kind, toolUseID: post.toolUseID, at: t0 + 4)
        assert(s.steps[0].state == .done && s.steps[1].state == .running && s.currentLine == "Building the project")
        assert(s.steps[0].endedAt == t0 + 4 && s.steps[0].duration() == 3)
        s.apply(.toolEnd(tool: "Bash", failed: true), toolUseID: nil, at: t0 + 5)
        assert(s.failures == 1 && s.steps[1].state == .failed && AgentStore.mood([s], at: t0 + 6) == .oops)
        assert(AgentStore.mood([s], at: t0 + 20) == .thinking)
        s.apply(perm.kind, toolUseID: nil, at: t0 + 21)
        assert(s.phase == .needsPermission && s.currentLine.contains("permission") && AgentStore.mood([s], at: t0 + 21) == .alert)
        assert(MascotWalker.note([s], now: t0 + 21) == "proj: Claude needs your permission to use Bash")
        var asking = s
        asking.apply(bash.kind, toolUseID: nil, at: t0 + 22)
        asking.apply(perm.kind, toolUseID: nil, at: t0 + 22)
        assert(asking.attentionLine == "OK to go ahead with \u{201C}Building the project\u{201D}?")
        s.apply(ev(#"{"hook_event_name":"Stop","session_id":"s1"}"#).kind, toolUseID: nil, at: t0 + 30)
        assert(s.phase == .done && s.steps.allSatisfy { $0.state != .running } && s.elapsed(at: t0 + 999) == 30)
        assert(AgentStore.mood([s], at: t0 + 32) == .celebrating && AgentStore.mood([s], at: t0 + 60) == .idle)
        assert(MascotWalker.note([s], now: t0 + 32) == "Done! Fix the bug" && MascotWalker.note([s], now: t0 + 60) == nil)
        assert(AgentStore.mood([s], at: t0 + 600) == .sleeping && AgentStore.mood([], at: t0) == .sleeping)
        s.apply(ev(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"Again"}"#).kind, toolUseID: nil, at: t0 + 40)
        assert(s.turns == 2 && s.toolCount == 0 && s.files.isEmpty && s.steps.isEmpty)
        assert(AgentStep(id: "", kind: .read, tool: "Read", subject: "/x/y.txt").title == "Reading y.txt")
        // Plain words: commands by intent, MCP tools by app and action, connector UUIDs hidden.
        assert(AgentStep.describe(command: "rtk git push origin main") == "Sharing changes")
        assert(AgentStep.describe(command: "npm test") == "Running tests" && AgentStep.describe(command: "./make-app.sh") == "Building the project")
        assert(AgentStep.describe(command: "rm -rf dist") == "Deleting files" && AgentStep.describe(command: "echo hi") == "Running a command")
        assert(AgentStep(id: "", kind: .other, tool: "mcp__github__create_issue", subject: "").title == "Using Github: create issue")
        assert(AgentStep(id: "", kind: .other, tool: "mcp__1a59c906-04da-521d-bda7-7f71b9f9e01c__batch", subject: "").title == "Using a connected app: batch")
        assert(AgentStep(id: "", kind: .web, tool: "WebFetch", subject: "https://claude.com/x").title == "Reading claude.com")
        assert(AgentStep.humanize("NotebookEdit") == "notebook edit")

        // Harness from the payload; Gemini event names map to the same phases.
        let gem = ev(#"{"hook_event_name":"BeforeTool","session_id":"g","tool_name":"run_shell_command","tool_input":{"command":"pytest"}}"#)
        assert(gem.harness == .gemini && gem.kind == .toolStart(.command, tool: "run_shell_command", subject: "pytest"))
        assert(ev(#"{"hook_event_name":"Stop","session_id":"c","transcript_path":"/u/.codex/s.jsonl"}"#).harness == .codex && p.harness == .claude)

        // Task list: TodoWrite replaces it, TaskCreate / TaskUpdate edit it; not shown as steps.
        var t = AgentSession(id: "t", cwd: "")
        t.apply(ev(#"{"hook_event_name":"PreToolUse","session_id":"t","tool_name":"TodoWrite","tool_input":{"todos":[{"content":"Fix it","activeForm":"Fixing it","status":"in_progress"},{"content":"Test","status":"pending"}]}}"#).kind, toolUseID: nil)
        assert(t.plan.count == 2 && t.plan[0].label == "Fixing it" && t.plan[1].status == .pending && t.steps.isEmpty)
        t.apply(ev(#"{"hook_event_name":"PreToolUse","session_id":"t","tool_name":"TaskCreate","tool_input":{"subject":"Ship","activeForm":"Shipping"}}"#).kind, toolUseID: nil)
        t.apply(ev(#"{"hook_event_name":"PreToolUse","session_id":"t","tool_name":"TaskUpdate","tool_input":{"taskId":"3","status":"completed"}}"#).kind, toolUseID: nil)
        t.apply(ev(#"{"hook_event_name":"PreToolUse","session_id":"t","tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"deleted"}}"#).kind, toolUseID: nil)
        assert(t.plan[2].text == "Ship" && t.plan[2].status == .completed && t.visiblePlan.count == 2)
        let nested = AgentStep(id: "", kind: .edit, tool: "Edit", subject: "/tmp/proj/Sources/App/main.swift")
        assert(nested.detail(relativeTo: "/tmp/proj") == "Sources/App" && AgentStep(id: "", kind: .edit, tool: "Edit", subject: "/tmp/proj/a.swift").detail(relativeTo: "/tmp/proj") == nil)

        // Settings saved by older versions decode, and pre-pet Grid moves to Focus.
        let old = try! JSONDecoder().decode(AgentsSettings.self, from: Data(#"{"enabled":true,"layout":"grid","showWorkingActivity":false,"notifyFinished":true,"notifyAttention":true,"playsSound":true}"#.utf8))
        assert(old.layout == .focus && old.playsSound && !old.showWorkingActivity && old.showPet && old.roams)
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

        // Shell quoting survives a quote in the path; the payload scanner ignores braces inside strings.
        assert(HookInstaller.shellQuoted("/a b/it's") == #"'/a b/it'\''s'"#)
        func ends(_ chunks: [String]) -> Int? {
            var scan = JSONObjectEnd()
            return chunks.firstIndex { scan.feed(Array($0.utf8)) }
        }
        assert(ends([#"{"a":"}{\"}"#, #"","b":{"c":[1,{}]}"#, "}\n"]) == 2)
        assert(ends([#"{"a":"x"#, "y\"}"]) == 1 && ends([#"{"a":1"#]) == nil && ends(["  \n{}"]) == 0)

        // End to end: generated hook script → nc → socket server (a quote in the path checks the quoting).
        let sock = NSTemporaryDirectory() + "notchly-test-'q-\(getpid()).sock"
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
        // With agent and event arguments the script wraps the payload and answers Antigravity with `{}`.
        let wrap = Process()
        wrap.executableURL = URL(fileURLWithPath: "/bin/sh")
        wrap.arguments = ["-c", HookInstaller.script(socket: sock), "sh", "antigravity", "Stop"]
        let input = Pipe(), output = Pipe()
        wrap.standardInput = input
        wrap.standardOutput = output
        try! wrap.run()
        input.fileHandleForWriting.write(Data(#"{"conversationId":"e2e-ag","terminationReason":"NO_TOOL_CALL","error":""}"#.utf8) + Data("\n".utf8))
        try! input.fileHandleForWriting.close()
        assert(got.wait(timeout: .now() + 3) == .success)
        wrap.waitUntilExit()
        let wrapped = HookEvent(json: received.data)
        assert(wrap.terminationStatus == 0 && wrapped?.sessionID == "e2e-ag" && wrapped?.harness == .antigravity && wrapped?.kind == .stop)
        assert(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) == "{}\n")
        unlink(sock)

        // Esc: only Claude Code's own user entry counts, not a tool result or command that quotes it.
        let esc = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
        let quoted = #"{"type":"user","message":{"content":[{"type":"tool_result","content":"[Request interrupted by user]"}]}}"#
        let said = #"{"type":"assistant","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
        assert(AgentStore.isInterrupt(Data("{\"type\":\"mode\"}\n\(esc)\n".utf8)) && AgentStore.isInterrupt(Data(#"{"type":"user","message":{"content":"[Request interrupted by user]"}}"#.utf8)))
        assert(!AgentStore.isInterrupt(Data("\(quoted)\n\(said)\n".utf8)) && !AgentStore.isInterrupt(Data()))
        var cut = AgentSession(id: "x", cwd: "")
        cut.apply(p.kind, toolUseID: nil); cut.apply(bash.kind, toolUseID: nil); cut.apply(.interrupted, toolUseID: nil)
        assert(cut.phase == .stopped && !cut.phase.isBusy && cut.steps.allSatisfy { $0.state == .failed })
        assert(AgentStore.mood([cut], at: Date()) == .stopped && AgentStore.mood([cut], at: Date() + 30) == .idle)

        // Grok Build, from payloads it sent on 2026-11-24 (grok 1.0.70): camelCase keys beside Claude's.
        let gp = ev(#"{"hookEventName":"user_prompt_submit","sessionId":"gk","cwd":"/p","workspaceRoot":"/p","prompt":"Read notes.txt","hook_event_name":"UserPromptSubmit","session_id":"gk"}"#)
        assert(gp.harness == .grok && gp.kind == .prompt("Read notes.txt") && gp.cwd == "/p")
        let gread = ev(#"{"hookEventName":"pre_tool_use","sessionId":"gk","cwd":"/p","toolName":"read_file","toolUseId":"c-0","toolInput":{"target_file":"/p/notes.txt"},"hook_event_name":"PreToolUse","session_id":"gk","tool_name":"read_file","tool_input":{"target_file":"/p/notes.txt"},"tool_use_id":"c-0"}"#)
        assert(gread.kind == .toolStart(.read, tool: "read_file", subject: "/p/notes.txt") && gread.toolUseID == "c-0")
        let gcmd = ev(#"{"hookEventName":"pre_tool_use","sessionId":"gk","toolName":"run_terminal_command","toolInput":{"command":"ls","description":"List files"},"hook_event_name":"PreToolUse"}"#)
        assert(gcmd.kind == .toolStart(.command, tool: "run_terminal_command", subject: "ls") && gcmd.harness == .grok)
        assert(ev(#"{"hookEventName":"stop","sessionId":"gk","reason":"end_turn","hook_event_name":"Stop","session_id":"gk"}"#).kind == .stop)
        assert(ev(#"{"hookEventName":"stop","sessionId":"gk","reason":"shutdown","hook_event_name":"Stop","session_id":"gk"}"#).kind == .other)
        assert(ev(#"{"hookEventName":"stop_cancelled","sessionId":"gk","hook_event_name":"StopCancelled"}"#).kind == .interrupted)
        assert(ev(#"{"hookEventName":"notification","sessionId":"gk","notificationType":"task_complete","hook_event_name":"Notification"}"#).kind == .other)
        assert(ev(#"{"hookEventName":"post_tool_use_failure","sessionId":"gk","toolName":"x","hook_event_name":"PostToolUseFailure"}"#).kind == .toolEnd(tool: "x", failed: true))
        assert(HookEvent(json: Data(#"{"hookEventName":"stop","sessionId":"child","subagentType":"explore","hook_event_name":"Stop"}"#.utf8)) == nil)

        // Antigravity CLI 1.2.12 sends no event name: the hook script wraps the payload with it.
        func agy(_ event: String, _ body: String) -> HookEvent {
            ev(#"{"notchly":{"agent":"antigravity","event":""# + event + #""},"payload":{"conversationId":"ag","workspacePaths":["/w"],"transcriptPath":"/u/.gemini/antigravity-cli/brain/ag/t.jsonl""# + body + "}}")
        }
        let a0 = agy("PreInvocation", #","invocationNum":0,"initialNumSteps":1"#)
        assert(a0.harness == .antigravity && a0.sessionID == "ag" && a0.cwd == "/w" && a0.kind == .prompt(""))
        let aview = agy("PreToolUse", #","stepIdx":2,"toolCall":{"id":"t1","name":"view_file","args":{"AbsolutePath":"/w/notes.txt","toolAction":"Viewing notes.txt"}}"#)
        assert(aview.kind == .toolStart(.read, tool: "view_file", subject: "/w/notes.txt") && aview.toolUseID == "t1")
        let arun = agy("PreToolUse", #","toolCall":{"name":"run_command","args":{"CommandLine":"npm test","Cwd":"/w"}}"#)
        assert(arun.kind == .toolStart(.command, tool: "run_command", subject: "npm test"))
        assert(agy("PostInvocation", #","invocationNum":1"#).kind == .settle && agy("PreInvocation", #","invocationNum":2"#).kind == .settle)
        assert(agy("Stop", #","terminationReason":"NO_TOOL_CALL","error":"","fullyIdle":true"#).kind == .stop)
        assert(agy("Stop", #","terminationReason":"error","error":"quota""#).kind == .interrupted)
        assert(HookEvent(json: Data(#"{"conversationId":"ag","invocationNum":0}"#.utf8)) == nil)
        var ag = AgentSession(id: "ag", cwd: "/w", harness: .antigravity)
        for e in [a0, aview] { ag.apply(e.kind, toolUseID: e.toolUseID, at: t0) }
        assert(ag.phase == .working && AgentStore.mood([ag], at: t0) == .working(.read))
        ag.apply(.settle, toolUseID: nil, at: t0 + 1)
        assert(ag.phase == .thinking && ag.steps.allSatisfy { $0.state == .done })
        ag.apply(.stop, toolUseID: nil, at: t0 + 2); ag.apply(.settle, toolUseID: nil, at: t0 + 9)
        assert(ag.phase == .thinking && ag.turns == 2 && ag.steps.isEmpty)
        assert(ev(#"{"notchly":{"agent":"codex","event":""},"payload":{"hook_event_name":"Stop","session_id":"cx"}}"#).harness == .codex)
        assert(ev(#"{"hook_event_name":"Stop","session_id":"d","transcript_path":"/u/.factory/sessions/d.jsonl","hookEventName":"Stop"}"#).harness == .droid)

        // What the mascot acts out: command intent, MCP apps and plans.
        assert(AgentStep.act(command: "npm test") == .test && AgentStep.act(command: "rtk git push") == .ship && AgentStep.act(command: "echo") == .terminal)
        assert(PetAct(AgentStep(id: "", kind: .other, tool: "mcp__github__create_issue", subject: "")) == .connector)
        assert(PetAct(AgentStep(id: "", kind: .other, tool: "linear__save_issue", subject: "")) == .connector)
        assert(PetAct(AgentStep(id: "", kind: .other, tool: "EnterPlanMode", subject: "")) == .plan)
        assert(PetAct(AgentStep(id: "", kind: .command, tool: "Bash", subject: "rm -rf dist")) == .delete)

        // Motion: a hop crouches, stretches on the way up, peaks, and squashes on landing; noise repeats.
        let crouch = PetPainter.hop(0.1, height: 0.1), rise = PetPainter.hop(0.3, height: 0.1)
        let apex = PetPainter.hop(0.49, height: 0.1), land = PetPainter.hop(0.88, height: 0.1)
        assert(crouch.lift == 0 && crouch.squash > 0 && rise.lift > 0 && rise.squash < 0)
        assert(abs(apex.lift - 0.1) < 0.001 && land.lift == 0 && land.squash > 0 && PetPainter.hop(1, height: 0.1).squash < 0.001)
        assert(PetPainter.noise(42, 3) == PetPainter.noise(42, 3) && (0..<1).contains(PetPainter.noise(-7)))
        assert(abs(PetPainter.spring(3) - 1) < 0.01 && PetPainter.bounce(1) == 1 && PetPainter.bounce(0) == 0)

        // Installers: Antigravity's named hook keeps other named hooks; per-agent commands and matchers.
        let ant = HookTarget.all.first { $0.harness == .antigravity }!
        let other: [String: Any] = ["lint": ["PostToolUse": [["matcher": "run_command", "hooks": [["command": "./lint.sh"]]]]]]
        let withUs = HookInstaller.merged(other, add: true, target: ant, command: "'/x/notchly-hook.sh'")!
        let ours = withUs["notchly"] as! [String: Any]
        assert(HookInstaller.isInstalled(withUs, ant) && withUs["lint"] != nil && Set(ours.keys) == Set(ant.events))
        assert(((ours["Stop"] as! [[String: Any]])[0]["command"] as! String) == "'/x/notchly-hook.sh' antigravity Stop")
        assert(((ours["PreToolUse"] as! [[String: Any]])[0]["matcher"] as! String) == "*")
        assert(NSDictionary(dictionary: HookInstaller.merged(withUs, add: false, target: ant)!).isEqual(to: other))
        let grokT = HookTarget.all.first { $0.harness == .grok }!, codexT = HookTarget.all.first { $0.harness == .codex }!
        let gk = (HookInstaller.merged([:], add: true, target: grokT, command: "'/x/notchly-hook.sh'")!["hooks"] as! [String: Any])
        let gpre = (gk["PreToolUse"] as! [[String: Any]])[0]
        assert(gpre["matcher"] == nil && ((gpre["hooks"] as! [[String: Any]])[0]["command"] as! String) == "'/x/notchly-hook.sh'")
        let cx = (HookInstaller.merged([:], add: true, target: codexT, command: "'/x/notchly-hook.sh'")!["hooks"] as! [String: Any])
        assert((((cx["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]["command"] as! String) == "'/x/notchly-hook.sh' codex")

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
                        Text(store.hooksInstalled ? "Your agents are connected" : "Connect your coding agents").font(.headline)
                        Text("Notchly adds a small script to each agent's hooks so the notch can follow every session. Your other hooks stay, and the first time a backup of the settings file is saved beside it (.notchly-backup).")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if let error = store.hookError { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
            }
            SettingsCard(title: "Agents") {
                ForEach(Array(HookTarget.all.enumerated()), id: \.offset) { i, t in
                    if i > 0 { Divider() }
                    AgentHookRow(target: t, installed: store.installed.contains(t.harness), showPet: s.value.showPet)
                }
            }
            SettingsCard(title: "Status") {
                SettingsRow(title: "Notch bridge", subtitle: AgentBridgeServer.socketPath) {
                    Text(store.listening ? "Listening" : "Not running").foregroundStyle(.secondary)
                }
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
                SettingsRow(title: "Mascots", subtitle: "One per agent. It acts out each step (reading, building, testing…) and reacts when the agent needs you, finishes or is stopped.") {
                    Toggle("", isOn: s.binding(\.showPet)).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsRow(title: "Roam the screen", subtitle: "Mascots walk on your windows and drop out of the notch when an agent needs you or finishes.") {
                    Toggle("", isOn: s.binding(\.roams)).labelsHidden().toggleStyle(.switch).disabled(!s.value.showPet)
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

/// One agent: its mascot, where its hooks live, and a button to connect or disconnect it.
private struct AgentHookRow: View {
    let target: HookTarget
    let installed: Bool
    let showPet: Bool

    var body: some View {
        let present = target.isPresent
        SettingsRow(title: target.harness.name, subtitle: subtitle(present)) {
            HStack(spacing: 8) {
                if installed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Remove") { AgentStore.shared.setHooks(target.harness, installed: false) }
                } else {
                    Button("Connect") { AgentStore.shared.setHooks(target.harness, installed: true) }
                        .tint(target.harness.tint)
                        .disabled(!present)
                }
            }
        }
        .overlay(alignment: .leading) {
            PetView(mood: installed ? .idle : .sleeping, harness: target.harness, size: 30, animated: showPet && installed)
                .offset(x: -38)
                .accessibilityHidden(true)
        }
        .padding(.leading, 38)
    }

    private func subtitle(_ present: Bool) -> String {
        if installed { return "Connected in ~/\(target.path)" }
        if !present { return "Not found on this Mac" }
        if target.harness == .grok, AgentStore.shared.installed.contains(.claude) { return "Already follows Grok through Claude Code's hooks" }
        return "Adds hooks to ~/\(target.path)"
    }
}
