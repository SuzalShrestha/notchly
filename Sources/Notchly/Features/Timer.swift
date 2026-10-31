import SwiftUI

// MARK: - Model (same field names as NotchNook's TimerEntry / PomodoroSettings)

struct PomodoroSettings: Codable, Equatable {
    var focusMinutes = 10                 // settings-schema.json pomodoroSettings
    var breakMinutes = 5
    var showInNotch = true
    var rainDuringBreaks = true
}

struct TimerWidgetSettings: Codable, Equatable {
    var showSeconds = true
    var playSound = true
    var expirySound = "Glass"             // NSSound name (the original bundles its own sounds)
}

struct TimerEntry: Codable, Identifiable, Equatable {
    enum State: String, Codable { case running, paused, expired }
    var id = UUID()
    var label: String
    var totalSeconds: Int
    var remainingSeconds: Double
    var state: State = .running
    var startedAt: Date?
    var expiresAt: Date?
    var todoTaskID: UUID?

    func remaining(at now: Date = .now) -> Double {
        state == .running ? max(0, (expiresAt ?? now).timeIntervalSince(now)) : remainingSeconds
    }

    func progress(at now: Date = .now) -> Double { totalSeconds > 0 ? 1 - remaining(at: now) / Double(totalSeconds) : 1 }

    static func clock(_ seconds: Double) -> String {
        let t = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}

// MARK: - Store

@MainActor @Observable
final class TimerStore {
    static let shared = TimerStore()
    static let settings = Setting("timerWidgetSettings", default: TimerWidgetSettings())
    static let pomodoro = Setting("pomodoroSettings", default: PomodoroSettings())
    static let sounds = ["Glass", "Ping", "Hero", "Submarine", "Tink", "Purr", "Pop", "Funk", "Blow", "Bottle", "Frog", "Morse", "Sosumi", "Basso"]

    private(set) var entries = (DataFile.load("timers.json", as: [TimerEntry].self) ?? [])
        .filter { $0.state != .expired && $0.remaining() > 0 }
    @ObservationIgnored private var sound: NSSound?
    @ObservationIgnored private var started = false

    /// The timer the widget shows: the newest one.
    var active: TimerEntry? { entries.last }

    func start() {
        guard !started else { return }
        started = true
        updateActivity()
        Task {
            while !Task.isCancelled {
                let now = Date()
                for e in entries where e.state == .running && e.remaining(at: now) <= 0 { expire(e) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func start(label: String, seconds: Int, todoTaskID: UUID? = nil) {
        if let todoTaskID { entries.removeAll { $0.todoTaskID == todoTaskID } }
        entries.append(TimerEntry(label: label, totalSeconds: seconds, remainingSeconds: Double(seconds),
                                  startedAt: .now, expiresAt: .now.addingTimeInterval(Double(seconds)), todoTaskID: todoTaskID))
        changed()
    }

    func toggle(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        if entries[i].state == .running {
            entries[i].remainingSeconds = entries[i].remaining()
            entries[i].state = .paused
            entries[i].expiresAt = nil
        } else {
            entries[i].state = .running
            entries[i].expiresAt = .now.addingTimeInterval(entries[i].remainingSeconds)
        }
        changed()
    }

    func cancel(_ id: UUID) {
        entries.removeAll { $0.id == id }
        changed()
    }

    private func changed() {
        DataFile.save(entries, to: "timers.json")
        updateActivity()
    }

    private func expire(_ e: TimerEntry) {
        entries.removeAll { $0.id == e.id }
        changed()
        let s = Self.settings.value
        if s.playSound { sound = NSSound(named: s.expirySound) ?? NSSound(named: "Glass"); sound?.play() }
        let leading = Image(systemName: "bell.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
            .symbolEffect(.pulse)
        let trailing = Text(e.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent).lineLimit(1)
        LiveActivityCenter.shared.show(LiveActivity(kind: .timerExpired, priority: 45, leadingWidth: 24, trailingWidth: 80,
                                                    leading: AnyView(leading), trailing: AnyView(trailing)), duration: 6)
    }

    /// Closed-notch wings for the running timer that ends first.
    func updateActivity() {
        guard Self.pomodoro.value.showInNotch,
              let e = entries.filter({ $0.state == .running }).min(by: { ($0.expiresAt ?? .now) < ($1.expiresAt ?? .now) })
        else { LiveActivityCenter.shared.remove(.timerRunning); return }
        LiveActivityCenter.shared.show(LiveActivity(kind: .timerRunning, priority: 40, leadingWidth: 20, trailingWidth: 50,
                                                    leading: AnyView(TimerRing(entry: e, size: 16)),
                                                    trailing: AnyView(TimerClock(entry: e, size: 13))))
    }

    static func selfTest() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var e = TimerEntry(label: "Focus", totalSeconds: 300, remainingSeconds: 300, startedAt: t0, expiresAt: t0.addingTimeInterval(300))
        precondition(e.remaining(at: t0.addingTimeInterval(210)) == 90)
        precondition(e.remaining(at: t0.addingTimeInterval(400)) == 0)
        precondition(abs(e.progress(at: t0.addingTimeInterval(150)) - 0.5) < 1e-9)
        e.state = .paused
        e.remainingSeconds = 42
        precondition(e.remaining(at: t0.addingTimeInterval(9999)) == 42)
        precondition(TimerEntry.clock(90) == "01:30" && TimerEntry.clock(59.2) == "01:00" && TimerEntry.clock(0) == "00:00")
        precondition(TimerEntry.clock(25 * 60) == "25:00" && TimerEntry.clock(7200) == "120:00")
        precondition(PomodoroSettings().focusMinutes == 10 && PomodoroSettings().breakMinutes == 5)
    }
}

// MARK: - Live activity pieces

private struct TimerRing: View {
    let entry: TimerEntry
    let size: CGFloat
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.25), lineWidth: 2.5)
                Circle().trim(from: 0, to: 1 - entry.progress(at: ctx.date))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
        }
    }
}

private struct TimerClock: View {
    let entry: TimerEntry
    let size: CGFloat
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(TimerEntry.clock(entry.remaining(at: ctx.date)))
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.accent)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
    }
}

// MARK: - Nook widget (4 units, timerWidgetMock.png)

struct TimerWidget: View {
    @State private var isBreak = false

    var body: some View {
        let store = TimerStore.shared
        let p = TimerStore.pomodoro
        let active = store.active
        let breakSelected = active.map { $0.label == "Break" } ?? isBreak
        let minutes = active.map { $0.totalSeconds / 60 } ?? (isBreak ? p.value.breakMinutes : p.value.focusMinutes)
        WidgetCard(padding: 10) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    modeButton("Focus", selected: !breakSelected) { isBreak = false }
                    modeButton("Break", selected: breakSelected) { isBreak = true }
                }
                .disabled(active != nil)
                MinuteRuler(value: Binding(get: { minutes }, set: { m in
                    if isBreak { p.value.breakMinutes = m } else { p.value.focusMinutes = m }
                }), enabled: active == nil)
                HStack(spacing: 6) {
                    RoundButton(symbol: active?.state == .running ? "pause.fill" : "play.fill", size: 30, tint: Theme.accent, fill: Theme.accent.opacity(0.22)) {
                        if let a = active { store.toggle(a.id) } else { store.start(label: isBreak ? "Break" : "Focus", seconds: minutes * 60) }
                    }
                    if let a = active {
                        RoundButton(symbol: "stop.fill", size: 30, tint: Theme.secondaryText) { store.cancel(a.id) }
                    } else {
                        let on = TimerStore.settings.value.playSound
                        RoundButton(symbol: on ? "speaker.wave.2.fill" : "speaker.slash.fill", size: 30, tint: Theme.accent, fill: Theme.accent.opacity(0.22)) {
                            TimerStore.settings.value.playSound.toggle()
                        }
                    }
                    Spacer(minLength: 2)
                    if let a = active {
                        TimerClock(entry: a, size: 28)
                    } else {
                        Text(TimerEntry.clock(Double(minutes * 60)))
                            .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.accent).lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
            }
        }
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(Motion.snappy, action) } label: {
            Text(title)
                .font(Theme.title(12))
                .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                .padding(.horizontal, 12).frame(height: 22)
                .background(selected ? Theme.accent.opacity(0.22) : Theme.chip, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Horizontal minute ruler: drag to pick, one tick per minute, label every 5.
private struct MinuteRuler: View {
    @Binding var value: Int
    var enabled: Bool
    @State private var drag: CGFloat = 0
    private let spacing: CGFloat = 8
    private let range = 1...120

    var body: some View {
        let shown = min(max(Double(value) - Double(drag / spacing), Double(range.lowerBound)), Double(range.upperBound))
        let center = Int(shown.rounded())
        Canvas { ctx, size in
            let cx = size.width / 2
            let span = Double(cx / spacing)
            let lo = max(range.lowerBound, Int((shown - span).rounded(.down)))
            let hi = min(range.upperBound, Int((shown + span).rounded(.up)))
            guard lo <= hi else { return }
            for m in lo...hi {
                let x = cx + CGFloat(Double(m) - shown) * spacing
                let fade = 1 - min(1, abs(x - cx) / cx) * 0.85
                let isCenter = m == center
                ctx.fill(Path(roundedRect: CGRect(x: x - 0.75, y: isCenter ? 14 : 17, width: 1.5, height: isCenter ? 24 : 20), cornerRadius: 0.75),
                         with: .color(isCenter ? .white : Theme.accent.opacity(0.7 * fade)))
                if m % 5 == 0 || isCenter {
                    ctx.draw(Text("\(m)").font(.system(size: 10, weight: .bold))
                                .foregroundColor(isCenter ? .white : Theme.accent.opacity(0.55 * fade)),
                             at: CGPoint(x: x, y: 6))
                }
            }
            var tri = Path()
            tri.move(to: CGPoint(x: cx, y: 39)); tri.addLine(to: CGPoint(x: cx - 4, y: 45)); tri.addLine(to: CGPoint(x: cx + 4, y: 45))
            ctx.fill(tri, with: .color(Theme.accent))
        }
        .frame(height: 46)
        .opacity(enabled ? 1 : 0.6)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { drag = $0.translation.width }
            .onEnded { _ in value = center; drag = 0 },
                 including: enabled ? .all : .none)
    }
}
