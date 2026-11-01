import ServiceManagement
import SwiftUI

// First-run tour. Five short pages; every choice made here (widgets, Claude Code hooks,
// launch at login) is a normal setting that can be changed later in Settings.

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome, hover, nook, pet, ready
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Your notch, put to work"
        case .hover: "Point at it to open"
        case .nook: "Build your Nook"
        case .pet: "Meet your Claude pet"
        case .ready: "You're all set"
        }
    }

    var message: String {
        switch self {
        case .welcome: "Notchly turns the space around your camera into a small panel for music, files, your calendar, clipboard and coding agents."
        case .hover: "Move the pointer to the top of the screen and the notch opens. Move away and it tucks itself back in. Jump to any tab from anywhere:"
        case .nook: "Pick the widgets for your home tab. You can reorder them or add more later in Settings › Nook."
        case .pet: "It follows each Claude Code session: thinking, reading, running commands, waving when it needs you and celebrating when it's done."
        case .ready: "Notchly lives in the menu bar. Open it from Applications any time to come back to Settings."
        }
    }

    var glow: Color {
        switch self {
        case .welcome: Color(hex: 0x8A5CFF)
        case .hover: Color(hex: 0x3D7BFF)
        case .nook: Color(hex: 0x23B5A5)
        case .pet: Theme.claude
        case .ready: Theme.success
        }
    }
}

struct OnboardingView: View {
    @State private var page: OnboardingPage
    @State private var forward = true
    var onFinish: (_ openNotch: Bool) -> Void

    init(page: OnboardingPage = .welcome, onFinish: @escaping (_ openNotch: Bool) -> Void) {
        _page = State(initialValue: page)
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            OnboardingBackground(tint: page.glow)
            VStack(spacing: 0) {
                illustration
                    .frame(height: 262)
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: forward ? 40 : -40)),
                        removal: .opacity.combined(with: .offset(x: forward ? -40 : 40))))
                VStack(spacing: Space.m) {
                    Text(page.title)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                    Text(page.message)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.66))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .frame(maxWidth: 470)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id("text-\(page.rawValue)")
                .transition(.opacity)
                .padding(.top, Space.l)
                pageControls
                    .padding(.top, Space.l)
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 32).padding(.top, 34).padding(.bottom, 22)
        }
        .frame(width: 720, height: 600)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    // MARK: Pieces

    @ViewBuilder private var illustration: some View {
        switch page {
        case .welcome: DeskIllustration()
        case .hover: HoverIllustration()
        case .nook: NookPicker()
        case .pet: PetShowcase()
        case .ready:
            ZStack {
                ConfettiIllustration()
                PetView(mood: .celebrating, size: 170)
            }
        }
    }

    @ViewBuilder private var pageControls: some View {
        switch page {
        case .hover:
            HStack(spacing: Space.s) {
                KeyCap(label: "⌃")
                KeyCap(label: "⌘")
                KeyCap(label: "1")
                Text("…").foregroundStyle(.white.opacity(0.5))
                KeyCap(label: "7")
                Text("·  close with").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5)).padding(.leading, Space.xs)
                KeyCap(label: "esc")
            }
        case .pet: PetConnect()
        case .ready: ReadyOptions()
        default: EmptyView()
        }
    }

    private var footer: some View {
        HStack {
            Button(page == .ready ? "Close" : "Skip Tour") { onFinish(false) }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            PageDots(page: page) { go(to: $0) }
            Spacer()
            HStack(spacing: Space.m) {
                if page != .welcome {
                    Button("Back") { go(to: OnboardingPage(rawValue: page.rawValue - 1) ?? .welcome) }
                        .buttonStyle(GhostButtonStyle())
                }
                Button(page == .ready ? "Open Notchly" : (page == .welcome ? "Get Started" : "Continue")) {
                    if let next = OnboardingPage(rawValue: page.rawValue + 1) { go(to: next) } else { onFinish(true) }
                }
                .buttonStyle(FilledButtonStyle(tint: .white, foreground: .black))
                .keyboardShortcut(.defaultAction)
            }
            .frame(minWidth: 190, alignment: .trailing)
        }
    }

    private func go(to target: OnboardingPage) {
        guard target != page else { return }
        forward = target.rawValue > page.rawValue
        withAnimation(Motion.respecting(.spring(response: 0.5, dampingFraction: 0.86))) { page = target }
    }
}

private struct OnboardingBackground: View {
    let tint: Color
    var body: some View {
        ZStack {
            Color(hex: 0x0A0A0F)
            RadialGradient(colors: [tint.opacity(0.42), .clear], center: UnitPoint(x: 0.5, y: 0.05), startRadius: 0, endRadius: 430)
            RadialGradient(colors: [Theme.claude.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 380)
            // Fine grain of dots for texture.
            Canvas { g, size in
                let step: CGFloat = 22
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = (Int(y / step) % 2 == 0) ? 0 : step / 2
                    while x < size.width {
                        g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(.white.opacity(0.05)))
                        x += step
                    }
                    y += step
                }
            }
        }
        .animation(.easeInOut(duration: 0.6), value: tint)
        .ignoresSafeArea()
    }
}

private struct PageDots: View {
    let page: OnboardingPage
    let select: (OnboardingPage) -> Void
    var body: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingPage.allCases) { p in
                Button { select(p) } label: {
                    Capsule()
                        .fill(.white.opacity(p == page ? 0.95 : 0.25))
                        .frame(width: p == page ? 22 : 7, height: 7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(p.rawValue + 1): \(p.title)")
            }
        }
        .animation(Motion.respecting(Motion.snappy), value: page)
    }
}

// MARK: - Nook picker

private struct NookPicker: View {
    var body: some View {
        let s = NookFeature.settings
        let enabled = s.value.enabledWidgets
        VStack(spacing: Space.m) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(118), spacing: 10), count: 5), spacing: 10) {
                ForEach(NookWidget.allCases) { w in
                    let on = enabled.contains(w)
                    Button {
                        withAnimation(Motion.respecting(Motion.snappy)) {
                            if on { s.value.enabledWidgets.removeAll { $0 == w } } else { s.value.enabledWidgets.append(w) }
                        }
                    } label: {
                        HStack(spacing: Space.m) {
                            Image(systemName: w.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(w.tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(w.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).frame(height: 40)
                        .background(Color.white.opacity(on ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(on ? w.tint.opacity(0.9) : Theme.hairline, lineWidth: on ? 1.5 : 0.5))
                        .overlay(alignment: .topTrailing) {
                            if on {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.black, w.tint)
                                    .offset(x: 5, y: -5)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(w.title)
                    .accessibilityValue(on ? "In your Nook" : "Not added")
                }
            }
            Text(enabled.isEmpty ? "Pick at least one widget" : "\(enabled.count) widget\(enabled.count == 1 ? "" : "s") · \(enabled.map(\.title).joined(separator: ", "))")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
        .padding(.top, 10)
    }
}

extension NookWidget {
    /// Icon tile color in onboarding and settings.
    var tint: Color {
        switch self {
        case .media: .pink
        case .calendar: .red
        case .weather: .cyan
        case .timer: .orange
        case .todoList: .yellow
        case .activity: .green
        case .aiUsage: Theme.claude
        case .pulse: .mint
        case .clipboard: .teal
        case .notes: .blue
        case .tray: .indigo
        case .volume: .purple
        case .shortcuts: Color(hex: 0xE0569B)
        case .mirror: .gray
        case .quickApps: Color(hex: 0x5E8BFF)
        }
    }
}

// MARK: - Pet showcase

private struct PetShowcase: View {
    private static let moods: [PetMood] = [.thinking, .working(.read), .working(.edit), .working(.command), .alert, .celebrating]
    @State private var pinned: PetMood?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2.4)) { ctx in
            let auto = Self.moods[Int(ctx.date.timeIntervalSinceReferenceDate / 2.4) % Self.moods.count]
            let mood = pinned ?? auto
            VStack(spacing: Space.l) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [mood.tint.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 110))
                        .frame(width: 220, height: 220)
                    PetView(mood: mood, size: 170)
                }
                .frame(height: 190)
                .animation(.easeInOut(duration: 0.4), value: mood)
                HStack(spacing: Space.s) {
                    ForEach(Array(Self.moods.enumerated()), id: \.offset) { _, m in
                        let selected = m == mood
                        Button { pinned = pinned == m ? nil : m } label: {
                            Text(m.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selected ? .black : .white.opacity(0.75))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(selected ? m.tint : Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .animation(Motion.respecting(Motion.snappy), value: mood)
            }
        }
    }
}

private struct PetConnect: View {
    var body: some View {
        let store = AgentStore.shared
        VStack(spacing: Space.s) {
            if store.hooksInstalled {
                Label("Claude Code is connected", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.success)
            } else {
                Button { store.setHooks(installed: true) } label: { Label("Connect Claude Code", systemImage: "link") }
                    .buttonStyle(FilledButtonStyle(tint: Theme.claude, foreground: .white))
                Text("Adds a hook script to ~/.claude/settings.json. Your other hooks stay, and a backup is kept.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.42))
            }
            if let err = store.hookError { Text(err).font(.system(size: 11)).foregroundStyle(Theme.danger) }
        }
    }
}

// MARK: - Ready

private struct ReadyOptions: View {
    @State private var login = SMAppService.mainApp.status == .enabled
    var body: some View {
        HStack(spacing: Space.xl) {
            Toggle(isOn: Binding(get: { login }, set: { on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
                login = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            })) { Text("Launch at login") }
            Toggle("Open on hover", isOn: Settings.general.binding(\.alwaysOpenNotchOnHover))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, Space.xl).padding(.vertical, Space.m)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}
