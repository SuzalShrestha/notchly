import SwiftUI

// MARK: - Agents tab
//
// Focus (default): a mascot hero card plus one session in depth (header, attention banner,
// the agent's plan and its steps as a checklist in plain words). Grid / List: compact cards for every session.

struct AgentsView: View {
    var body: some View {
        let store = AgentStore.shared
        let sessions = store.sorted
        if sessions.isEmpty {
            AgentsEmptyView()
        } else {
            switch AgentsFeature.settings.value.layout {
            case .focus: AgentsFocusView(sessions: sessions, current: store.selected ?? sessions[0])
            case .grid: AgentsGridView(sessions: sessions, columns: 2)
            case .list: AgentsGridView(sessions: sessions, columns: 1)
            }
        }
    }
}

// MARK: Empty state

private struct AgentsEmptyView: View {
    var body: some View {
        let store = AgentStore.shared
        HStack(spacing: Space.xxl) {
            ZStack {
                Circle().fill(RadialGradient(colors: [Theme.claude.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 80))
                    .frame(width: 160, height: 160)
                PetView(mood: .sleeping, size: 112)
            }
            .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: Space.m) {
                Text("No agents running").font(Theme.title(17))
                Text(store.hooksInstalled
                     ? "Start Claude Code in any project and I'll follow along here: what it reads, edits and runs, and when it needs you."
                     : "Connect Claude Code and I'll follow each session live: what it reads, edits and runs, and when it needs you.")
                    .font(Theme.body).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if store.hooksInstalled {
                    HStack(spacing: Space.s) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                        Text("Connected. Run").foregroundStyle(Theme.secondaryText)
                        KeyCap(label: "claude", size: 11)
                        Text("in a terminal.").foregroundStyle(Theme.secondaryText)
                    }
                    .font(Theme.caption)
                    .padding(.top, Space.xs)
                } else {
                    HStack(spacing: Space.m) {
                        Button { store.setHooks(installed: true) } label: { Label("Connect Claude Code", systemImage: "link") }
                            .buttonStyle(FilledButtonStyle(tint: Theme.claude, foreground: .white))
                        Text("Adds hooks to ~/.claude/settings.json.\nYour own hooks stay; a backup is kept.")
                            .font(Theme.micro).foregroundStyle(Theme.tertiaryText)
                    }
                    .padding(.top, Space.xs)
                }
                if let err = store.hookError { Text(err).font(Theme.caption).foregroundStyle(Theme.danger).lineLimit(2) }
            }
            .frame(maxWidth: 400, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Focus layout

private struct AgentsFocusView: View {
    let sessions: [AgentSession]
    let current: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            AgentHeroCard(session: current, total: sessions.count).frame(width: 176)
            VStack(spacing: Space.m) {
                if sessions.count > 1 { SessionSwitcher(sessions: sessions, selectedID: current.id) }
                SessionDetailCard(session: current)
            }
        }
    }
}

/// Pet, what it is doing in words, and per-turn counters.
private struct AgentHeroCard: View {
    let session: AgentSession
    let total: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let mood = AgentStore.mood([session], at: ctx.date)
            VStack(spacing: Space.xs) {
                if AgentsFeature.settings.value.showPet {
                    PetView(mood: mood, harness: session.harness, size: 92).padding(.top, -6)
                } else {
                    Image(systemName: "asterisk").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.claude)
                        .frame(height: 86)
                }
                Text(mood.title).font(Theme.title(13)).lineLimit(1)
                    .contentTransition(.opacity)
                Text(subtitle(mood, now: ctx.date))
                    .font(Theme.caption).foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center).lineLimit(2)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                HStack(spacing: Space.xs) {
                    Stat(value: "\(session.toolCount)", label: "steps")
                    Stat(value: "\(session.files.count)", label: "files")
                    Stat(value: AgentFormat.clock(session.elapsed(at: ctx.date)), label: "time")
                }
            }
            .animation(Motion.respecting(Motion.snappy), value: mood)
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxHeight: .infinity)
            .background(
                RadialGradient(colors: [mood.tint.opacity(0.26), .clear], center: .top, startRadius: 0, endRadius: 150)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.widgetRadius, style: .continuous))
            )
            .cardSurface()
        }
    }

    private func subtitle(_ mood: PetMood, now: Date) -> String {
        switch mood {
        case .working: return session.runningStep?.title ?? session.currentLine
        case .thinking: return "\(AgentFormat.musing(at: now))\u{2026}"
        case .alert: return session.phase == .needsPermission ? "Waiting for your OK" : "Waiting for your reply"
        case .celebrating: return "Finished in \(AgentFormat.clock(session.elapsed(at: now)))"
        case .oops: return "A step went wrong; \(session.harness.short) is trying another way"
        case .idle: return total > 1 ? "\(total) sessions open" : "Ready for your next prompt"
        case .sleeping: return "Dozing until you're back"
        }
    }

    private struct Stat: View {
        let value: String
        let label: String
        var body: some View {
            VStack(spacing: 0) {
                Text(value).font(Theme.rounded(13, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(Theme.micro).foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

/// Capsules for each session; the selection pill slides between them.
private struct SessionSwitcher: View {
    let sessions: [AgentSession]
    let selectedID: String
    @Namespace private var ns

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(sessions) { s in
                    let selected = s.id == selectedID
                    Button {
                        withAnimation(Motion.respecting(Motion.snappy)) { AgentStore.shared.selectedID = s.id }
                    } label: {
                        HStack(spacing: Space.s) {
                            StatusDot(color: s.phase.color, size: 6, pulsing: s.phase.needsAttention || s.phase.isBusy)
                            Text(s.project).lineLimit(1)
                            if s.phase.needsAttention {
                                Text(s.phase.label).font(Theme.micro).foregroundStyle(Theme.warning)
                            }
                        }
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(selected ? .white : Theme.secondaryText)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background {
                            if selected {
                                Capsule().fill(Theme.chipHover).matchedGeometryEffect(id: "pill", in: ns)
                            } else {
                                Capsule().fill(Color.white.opacity(0.05))
                            }
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(s.project), \(s.phase.label)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .frame(height: 24)
    }
}

private struct SessionDetailCard: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header
            if session.phase.needsAttention {
                AttentionBanner(session: session)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            ActivityList(session: session)
            TurnSummary(session: session)
        }
        .animation(Motion.respecting(Motion.snappy), value: session.phase)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
        .contextMenu { SessionMenu(session: session) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(session.harness.tint)
                    Text(session.project).font(Theme.title(13)).lineLimit(1)
                    Text(session.harness.short).font(Theme.micro).foregroundStyle(session.harness.tint)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(session.harness.tint.opacity(0.14), in: Capsule())
                    if session.turns > 1 {
                        Text("turn \(session.turns)").font(Theme.micro).foregroundStyle(Theme.tertiaryText)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }
                }
                Text(session.title.isEmpty ? "Waiting for a prompt" : session.title)
                    .font(Theme.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    .help(session.prompt)
            }
            Spacer(minLength: Space.s)
            AgentElapsed(session: session).font(Theme.caption).foregroundStyle(Theme.tertiaryText)
            PhaseBadge(phase: session.phase)
            RoundButton(symbol: "terminal.fill", size: 22) { TerminalFocus.activate() }
                .help("Go to terminal")
                .accessibilityLabel("Go to terminal")
        }
    }
}

private struct AttentionBanner: View {
    let session: AgentSession
    var body: some View {
        let permission = session.phase == .needsPermission
        HStack(spacing: 10) {
            Image(systemName: permission ? "hand.raised.fill" : "text.bubble.fill")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                .frame(width: 26, height: 26).background(Theme.warning, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(permission ? "Needs your OK" : "Waiting for you").font(Theme.title(12)).foregroundStyle(Theme.warning)
                Text(session.attentionLine)
                    .font(Theme.caption).foregroundStyle(.white.opacity(0.82)).lineLimit(2)
            }
            Spacer(minLength: Space.s)
            Button("Go to Terminal") { TerminalFocus.activate() }
                .buttonStyle(FilledButtonStyle(tint: Theme.warning, compact: true))
        }
        .padding(Space.m)
        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.warning.opacity(0.35), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// The agent's own plan (when it keeps one), then its steps newest first, each with a
/// checkbox, spinner or cross. Words, not tool names: "Reading Design.swift", "Running tests".
private struct ActivityList: View {
    let session: AgentSession

    var body: some View {
        let plan = session.visiblePlan
        let steps = Array(session.steps.reversed())
        if plan.isEmpty && steps.isEmpty {
            HStack(spacing: Space.m) {
                if session.phase.isBusy { Spinner(tint: session.harness.tint) }
                TimelineView(.periodic(from: .now, by: 3)) { ctx in
                    Text(session.phase.isBusy ? "\(AgentFormat.musing(at: ctx.date))\u{2026}" : "Nothing done yet this turn")
                }
                .font(Theme.caption).foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if !plan.isEmpty {
                        SectionLabel(text: "Plan", trailing: "\(plan.filter { $0.status == .completed }.count) of \(plan.count) done")
                            .padding(.bottom, Space.xxs)
                        ForEach(plan, id: \.id) { PlanRow(todo: $0, tint: session.harness.tint) }
                    }
                    if !steps.isEmpty {
                        SectionLabel(text: plan.isEmpty ? "What it's doing" : "Latest steps")
                            .padding(.bottom, Space.xxs).padding(.top, plan.isEmpty ? 0 : Space.s)
                        ForEach(steps) { StepRow(step: $0, cwd: session.cwd, tint: session.harness.tint) }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Checkbox column: empty ring, spinner, check or cross.
private struct CheckMark: View {
    enum State { case pending, running, done, failed }
    let state: State
    var tint: Color = Theme.claude

    var body: some View {
        Group {
            switch state {
            case .pending: Circle().strokeBorder(Theme.hairlineStrong, lineWidth: 1.5)
            case .running: Spinner(tint: tint)
            case .done: Image(systemName: "checkmark.circle.fill").resizable().foregroundStyle(Theme.success)
            case .failed: Image(systemName: "xmark.circle.fill").resizable().foregroundStyle(Theme.danger)
            }
        }
        .frame(width: 13, height: 13)
        .frame(width: 18)
    }
}

/// Small arc spinner; drawn by hand so snapshots render it too.
private struct Spinner: View {
    var tint: Color = Theme.claude
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: Motion.reduceMotion)) { ctx in
            Circle().trim(from: 0, to: 0.72)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate * 400))
        }
        .frame(width: 12, height: 12)
    }
}

private struct PlanRow: View {
    let todo: AgentTodo
    let tint: Color
    var body: some View {
        let running = todo.status == .inProgress, done = todo.status == .completed
        HStack(spacing: Space.s) {
            CheckMark(state: done ? .done : (running ? .running : .pending), tint: tint)
            Text(todo.label)
                .font(Theme.caption.weight(running ? .semibold : .medium))
                .foregroundStyle(running ? .white : (done ? Theme.tertiaryText : Theme.secondaryText))
                .strikethrough(done, color: Theme.tertiaryText)
                .lineLimit(1)
                .shimmer(running)
            Spacer(minLength: 0)
        }
        .frame(height: 21)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "done" : (running ? "in progress" : "to do"))
    }
}

private struct StepRow: View {
    let step: AgentStep
    let cwd: String
    let tint: Color

    var body: some View {
        let running = step.state == .running, failed = step.state == .failed
        HStack(spacing: Space.s) {
            CheckMark(state: running ? .running : (failed ? .failed : .done), tint: tint)
            Image(systemName: step.kind.symbol)
                .font(.system(size: 9, weight: .bold)).foregroundStyle(step.kind.tint.opacity(running ? 1 : 0.7))
                .frame(width: 12)
            Text(step.title)
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(running ? .white : (failed ? Theme.danger.opacity(0.9) : Theme.secondaryText))
                .lineLimit(1).truncationMode(.middle)
                .shimmer(running)
                .layoutPriority(1)
            if let d = step.detail(relativeTo: cwd) {
                Text("in \(d)").font(Theme.micro).foregroundStyle(Theme.tertiaryText).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: Space.xs)
            Group {
                if running { Text(step.startedAt, style: .timer) } else { Text(AgentFormat.short(step.duration())) }
            }
            .font(Theme.mono(10)).foregroundStyle(running ? tint : Theme.tertiaryText)
        }
        .frame(height: 21)
        .help(step.subject.isEmpty ? step.tool : "\(step.tool): \(step.subject)")
        .accessibilityElement(children: .combine)
    }
}

/// One plain line about the turn: steps, files changed, problems.
private struct TurnSummary: View {
    let session: AgentSession
    var body: some View {
        if session.toolCount > 0 {
            HStack(spacing: 10) {
                Label("\(session.toolCount) step\(session.toolCount == 1 ? "" : "s")", systemImage: "checklist")
                if !session.files.isEmpty {
                    Label("\(session.files.count) file\(session.files.count == 1 ? "" : "s") changed", systemImage: "doc.badge.ellipsis")
                }
                if session.failures > 0 {
                    Label("\(session.failures) hiccup\(session.failures == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                }
                Spacer(minLength: 0)
            }
            .font(Theme.micro).foregroundStyle(Theme.tertiaryText).monospacedDigit()
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: Grid / List layout

private struct AgentsGridView: View {
    let sessions: [AgentSession]
    let columns: Int

    var body: some View {
        let grid = Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(stride(from: 0, to: sessions.count, by: columns)), id: \.self) { i in
                GridRow(alignment: .top) {
                    ForEach(sessions[i..<min(i + columns, sessions.count)]) { AgentCard(session: $0, compact: columns == 1) }
                }
            }
        }
        ViewThatFits(in: .vertical) {
            grid.frame(maxHeight: .infinity, alignment: .top)
            ScrollView(showsIndicators: false) { grid }
        }
    }
}

private struct AgentCard: View {
    let session: AgentSession
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                if AgentsFeature.settings.value.showPet {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        PetView(mood: AgentStore.mood([session], at: ctx.date), harness: session.harness, size: 30)
                    }
                    .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "asterisk")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.claude)
                        .frame(width: 26, height: 26).background(Theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.project).font(Theme.title(13)).lineLimit(1)
                    Text(session.title.isEmpty ? session.harness.name : session.title).font(Theme.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                Spacer(minLength: Space.xs)
                PhaseBadge(phase: session.phase)
            }
            HStack(spacing: Space.s) {
                if session.phase.needsAttention {
                    Image(systemName: "hand.raised.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.warning)
                } else if session.runningStep != nil {
                    Spinner(tint: session.harness.tint)
                }
                Text(session.currentLine).font(Theme.body).lineLimit(1)
                    .foregroundStyle(session.phase.needsAttention ? Theme.warning : .white)
                    .shimmer(session.runningStep != nil)
                Spacer(minLength: Space.xs)
                AgentElapsed(session: session).font(Theme.caption).foregroundStyle(Theme.tertiaryText)
            }
            if !compact {
                VStack(alignment: .leading, spacing: Space.xs) {
                    // The running step is already the headline above.
                    ForEach(session.steps.filter { $0.state != .running }.suffix(3).reversed()) { step in
                        HStack(spacing: Space.xs) {
                            CheckMark(state: step.state == .running ? .running : (step.state == .failed ? .failed : .done), tint: session.harness.tint)
                            Text(step.title).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(step.state == .running ? "" : AgentFormat.short(step.duration())).font(Theme.mono(10))
                        }
                        .font(Theme.caption)
                        .foregroundStyle(step.state == .running ? .white : Theme.secondaryText)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardSurface(stroke: session.phase.needsAttention ? Theme.warning.opacity(0.45) : Theme.hairline)
        .contentShape(RoundedRectangle(cornerRadius: Theme.widgetRadius, style: .continuous))
        .onTapGesture(count: 2) {
            AgentStore.shared.selectedID = session.id
            AgentsFeature.settings.value.layout = .focus
        }
        .contextMenu { SessionMenu(session: session) }
    }
}

// MARK: Shared pieces

private struct SessionMenu: View {
    let session: AgentSession
    var body: some View {
        Button("Go to Terminal") { TerminalFocus.activate() }
        if !session.cwd.isEmpty {
            Button("Reveal Project in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.cwd)]) }
        }
        if !session.prompt.isEmpty {
            Button("Copy Prompt") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.prompt, forType: .string)
            }
        }
        Divider()
        Button("Dismiss") { AgentStore.shared.dismiss(session.id) }
        Button("Clear Finished Sessions") { AgentStore.shared.clearFinished() }
    }
}

private struct AgentElapsed: View {
    let session: AgentSession
    var body: some View {
        Group {
            if session.phase.isBusy || session.phase.needsAttention {
                Text(session.startedAt, style: .timer)
            } else {
                Text(AgentFormat.clock(session.elapsed()))
            }
        }
        .monospacedDigit()
    }
}

struct PhaseBadge: View {
    let phase: AgentPhase
    var body: some View {
        HStack(spacing: 5) {
            switch phase {
            case .thinking, .working: StatusDot(color: Theme.claude, size: 6, pulsing: true)
            case .needsInput: Image(systemName: "text.bubble.fill")
            case .needsPermission: Image(systemName: "hand.raised.fill")
            case .done: Image(systemName: "checkmark")
            case .idle: EmptyView()
            }
            Text(phase.label)
        }
        .font(Theme.caption.weight(.semibold))
        .foregroundStyle(phase.needsAttention || phase == .done ? .black : .white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(phase.needsAttention || phase == .done ? phase.color : Theme.chip, in: Capsule())
        .fixedSize()
    }
}

enum AgentFormat {
    /// Words Claude Code shows while it thinks; one every few seconds.
    static let musings = ["Pondering", "Percolating", "Noodling", "Mulling", "Brewing", "Cogitating", "Ruminating",
                          "Simmering", "Musing", "Conjuring", "Tinkering", "Deliberating", "Hatching", "Marinating"]
    static func musing(at date: Date) -> String { musings[Int(date.timeIntervalSinceReferenceDate / 3) % musings.count] }

    /// m:ss, or h:mm:ss past an hour.
    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Compact step duration: "<1s", "12s", "3m 04s".
    static func short(_ t: TimeInterval) -> String {
        if t < 1 { return "<1s" }
        let s = Int(t)
        return s < 60 ? "\(s)s" : String(format: "%dm %02ds", s / 60, s % 60)
    }
}

// MARK: - Closed-notch wings (observe the store; created once per appearance)

/// Tiny pet beside the camera; falls back to a spinner when the pet is turned off.
struct AgentWingPet: View {
    var body: some View {
        if AgentsFeature.settings.value.showPet {
            AgentPet(size: 24)
        } else {
            ProgressView().controlSize(.mini).tint(Theme.claude)
        }
    }
}

struct AgentWorkingWingLabel: View {
    var body: some View {
        let busy = AgentStore.shared.sorted.first(where: \.phase.isBusy)
        HStack(spacing: 3) {
            Image(systemName: busy?.runningStep?.kind.symbol ?? "sparkle").font(.system(size: 9, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
            Text("\(busy?.toolCount ?? 0)").monospacedDigit().contentTransition(.numericText())
        }
        .font(Theme.caption.weight(.semibold))
        .foregroundStyle(busy?.runningStep?.kind.tint ?? Theme.claude)
        .animation(Motion.snappy, value: busy?.toolCount)
    }
}

struct AgentAlertWingLabel: View {
    var body: some View {
        let store = AgentStore.shared
        if let s = store.sorted.first(where: \.phase.needsAttention) {
            Text(s.phase == .needsPermission ? "Allow?" : "Input").font(Theme.caption.weight(.semibold))
                .foregroundStyle(Theme.warning).lineLimit(1)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                Text(store.finishedProject).lineLimit(1)
            }
            .font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.success)
        }
    }
}
