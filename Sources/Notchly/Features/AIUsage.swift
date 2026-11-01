import SwiftUI

// Local-only AI usage: token counts read from Claude Code and Codex transcripts. No network.

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var title: String { self == .claude ? "Claude Code" : "Codex" }
    var symbol: String { self == .claude ? "asterisk" : "hexagon" }
    var tint: Color { self == .claude ? Color(hex: 0xD97757) : .white }
    var root: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return self == .claude ? home.appendingPathComponent(".claude/projects") : home.appendingPathComponent(".codex/sessions")
    }
}

struct AITokenCostSummary: Codable, Equatable {
    var todayTokens = 0
    var last30DaysTokens = 0
    var todayCostUSD: Double? = nil      // ponytail: no price table; costs stay nil until one is added
    var last30DaysCostUSD: Double? = nil
}

struct AIProviderStatus: Identifiable, Equatable {
    let provider: AIProvider
    var detected = false
    var tokenCost = AITokenCostSummary()
    var updatedAt = Date()
    var lastUsedAt: Date?
    var id: AIProvider { provider }
}

enum AIUsageScanner {
    struct Entry { var id: String; var date: Date; var tokens: Int }
    private struct FileScan { var modified: Date; var size: Int; var entries: [Entry] }
    nonisolated(unsafe) private static var cache: [String: FileScan] = [:]   // touched only on `queue`
    static let queue = DispatchQueue(label: "notchly.aiusage", qos: .utility)
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    /// Claude: assistant line with message.usage (deduped on message.id). Codex: event_msg token_count.
    static func entry(_ o: [String: Any], provider: AIProvider) -> Entry? {
        guard let ts = o["timestamp"] as? String, let date = iso.date(from: ts) ?? ISO8601DateFormatter().date(from: ts) else { return nil }
        switch provider {
        case .claude:
            guard o["type"] as? String == "assistant", let m = o["message"] as? [String: Any], let u = m["usage"] as? [String: Any] else { return nil }
            let t = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].reduce(0) { $0 + (u[$1] as? Int ?? 0) }
            return Entry(id: m["id"] as? String ?? "", date: date, tokens: t)
        case .codex:
            guard let p = o["payload"] as? [String: Any], p["type"] as? String == "token_count",
                  let info = p["info"] as? [String: Any], let last = info["last_token_usage"] as? [String: Any],
                  let t = last["total_tokens"] as? Int else { return nil }
            return Entry(id: "", date: date, tokens: t)
        }
    }

    static func entries(in data: Data, provider: AIProvider, since: Date) -> [Entry] {
        let needle = Data(#""output_tokens""#.utf8)
        return data.split(separator: 10).compactMap { line in
            guard line.range(of: needle) != nil,
                  let o = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let e = entry(o, provider: provider), e.date >= since else { return nil }
            return e
        }
    }

    static func summarize(_ entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> AITokenCostSummary {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        var seen = Set<String>(), s = AITokenCostSummary()
        for e in entries where e.date >= start && e.date <= now {
            if !e.id.isEmpty, !seen.insert(e.id).inserted { continue }
            s.last30DaysTokens += e.tokens
            if e.date >= today { s.todayTokens += e.tokens }
        }
        return s
    }

    /// Call on `queue`. Re-reads only files whose mtime or size changed; skips files older than 30 days.
    static func scan(_ provider: AIProvider, now: Date = Date()) -> AIProviderStatus {
        var status = AIProviderStatus(provider: provider, updatedAt: now)
        let fm = FileManager.default
        guard fm.fileExists(atPath: provider.root.path) else { return status }
        status.detected = true
        let since = now.addingTimeInterval(-31 * 86400)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        var all: [Entry] = []
        let files = fm.enumerator(at: provider.root, includingPropertiesForKeys: keys)?.compactMap { $0 as? URL } ?? []
        for url in files where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), let mod = v.contentModificationDate, mod >= since else { continue }
            let size = v.fileSize ?? 0
            if let c = cache[url.path], c.modified == mod, c.size == size { all += c.entries; continue }
            // Read, not mapped: Claude rewrites transcripts, and a mapped file that shrinks under us crashes (SIGBUS).
            guard let data = try? Data(contentsOf: url) else { continue }
            let found = entries(in: data, provider: provider, since: since)
            cache[url.path] = FileScan(modified: mod, size: size, entries: found)
            all += found
        }
        status.lastUsedAt = all.map(\.date).max()
        status.tokenCost = summarize(all, now: now)
        return status
    }

    static func selfTest() {
        let now = iso.date(from: "2026-10-31T15:00:00.000Z")!
        let claude = """
        {"type":"assistant","timestamp":"2026-10-31T11:32:53.152Z","message":{"id":"m1","usage":{"input_tokens":2,"output_tokens":453,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000}}}
        {"type":"assistant","timestamp":"2026-10-31T11:32:54.000Z","message":{"id":"m1","usage":{"input_tokens":2,"output_tokens":453,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000}}}
        {"type":"user","timestamp":"2026-10-31T11:33:00.000Z","message":{"content":"output_tokens"}}
        {"type":"assistant","timestamp":"2026-10-20T10:00:00.000Z","message":{"id":"m2","usage":{"input_tokens":10,"output_tokens":5}}}
        {"type":"assistant","timestamp":"2026-08-01T10:00:00.000Z","message":{"id":"m3","usage":{"input_tokens":10,"output_tokens":5}}}
        not json
        """
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let e = entries(in: Data(claude.utf8), provider: .claude, since: now.addingTimeInterval(-31 * 86400))
        assert(e.count == 3)
        let s = summarize(e, now: now, calendar: utc)
        assert(s.todayTokens == 1555 && s.last30DaysTokens == 1570)
        let codex = """
        {"timestamp":"2026-10-31T05:47:52.489Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"output_tokens":0,"total_tokens":1090},"last_token_usage":{"output_tokens":0,"total_tokens":1090}}}}
        {"timestamp":"2026-10-31T05:48:52.489Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"output_tokens":0,"total_tokens":1590},"last_token_usage":{"output_tokens":0,"total_tokens":500}}}}
        {"timestamp":"2026-10-31T05:49:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"output_tokens":1}}}
        """
        let c = summarize(entries(in: Data(codex.utf8), provider: .codex, since: .distantPast), now: now, calendar: utc)
        assert(c.todayTokens == 1590 && c.last30DaysTokens == 1590)
        assert(AIUsageStore.compact(1_234_567) == "1.2M" && AIUsageStore.compact(950) == "950" && AIUsageStore.compact(12_300) == "12.3K")
    }
}

@MainActor @Observable
final class AIUsageStore {
    static let shared = AIUsageStore()
    private(set) var statuses: [AIProviderStatus] = []
    var selected: AIProvider?
    @ObservationIgnored private var timer: Timer?

    init() {
        // Snapshot renders synchronously, so scan before the first frame there.
        if CommandLine.arguments.contains("--snapshot") { statuses = AIUsageScanner.queue.sync { AIProvider.allCases.map { AIUsageScanner.scan($0) } } }
    }

    var detected: [AIProviderStatus] { statuses.filter(\.detected) }
    var current: AIProviderStatus? {
        detected.first { $0.provider == selected } ?? detected.max { ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast) }
    }

    func startIfNeeded() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in MainActor.assumeIsolated { AIUsageStore.shared.refresh() } }
    }

    func refresh() {
        AIUsageScanner.queue.async {
            let result = AIProvider.allCases.map { AIUsageScanner.scan($0) }
            DispatchQueue.main.async { MainActor.assumeIsolated { AIUsageStore.shared.statuses = result } }
        }
    }

    func cycle() {
        let d = detected.map(\.provider)
        guard let c = current?.provider, let i = d.firstIndex(of: c), d.count > 1 else { return }
        selected = d[(i + 1) % d.count]
    }

    nonisolated static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000_000...: String(format: "%.1fB", Double(n) / 1e9)
        case 1_000_000...: String(format: "%.1fM", Double(n) / 1e6)
        case 1_000...: String(format: "%.1fK", Double(n) / 1e3)
        default: "\(n)"
        }
    }
}

struct AIUsageWidget: View {
    var body: some View {
        let store = AIUsageStore.shared
        WidgetCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.secondaryText)
                    Text("AI Usage").font(Theme.title(13))
                    Spacer(minLength: 0)
                    if store.detected.count > 1 { Text("\(store.detected.count)").font(Theme.caption).foregroundStyle(Theme.tertiaryText) }
                }
                if let s = store.current {
                    let t = s.tokenCost
                    let avg = Double(t.last30DaysTokens) / 30
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().stroke(Theme.chip, lineWidth: 6)
                            Circle().trim(from: 0, to: avg > 0 ? min(Double(t.todayTokens) / avg, 1) : 0)
                                .stroke(Theme.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(AIUsageStore.compact(t.todayTokens)).font(Theme.title(12)).monospacedDigit().minimumScaleFactor(0.6)
                        }
                        .frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: s.provider.symbol)
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(s.provider.tint)
                                .frame(width: 26, height: 26).background(Theme.chip, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(s.provider.title).font(Theme.title(13)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    Text("\(AIUsageStore.compact(t.todayTokens)) tokens today · \(AIUsageStore.compact(t.last30DaysTokens)) last 30 days")
                        .font(Theme.caption).foregroundStyle(Theme.secondaryText).lineLimit(2)
                } else {
                    Spacer(minLength: 0)
                    Text(store.statuses.isEmpty ? "Reading transcripts…" : "No Claude Code or Codex history found")
                        .font(Theme.caption).foregroundStyle(Theme.tertiaryText)
                    Spacer(minLength: 0)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.cycle() }
        .onAppear { store.startIfNeeded() }
    }
}
