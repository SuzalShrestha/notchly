import QuartzCore
import SwiftUI

struct PrompterScript: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var content: String
    var updatedAt = Date()
}

struct PrompterSettings: Codable, Equatable {
    var scrollSpeed: Double = 40       // points per second
    var fontSize: Double = 24
    var selectedId: UUID?
}

@MainActor
enum PrompterFeature {
    static let settings = Setting("prompterSettings", default: PrompterSettings())
    static let speedRange = 10.0...200.0
}

@MainActor @Observable
final class PrompterViewModel {
    enum State: Equatable { case idle, countdown(Int), running, paused }

    static let shared = PrompterViewModel()
    /// Saved with a short debounce: the editor changes this on every keystroke.
    var scripts: [PrompterScript] { didSet { scheduleSave() } }
    private(set) var state: State = .idle
    private(set) var offset: CGFloat = 0
    @ObservationIgnored var contentHeight: CGFloat = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var countdown: Task<Void, Never>?
    @ObservationIgnored private var lastTick: CFTimeInterval = 0
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init() {
        scripts = DataFile.load("prompter.json", as: [PrompterScript].self) ?? [PrompterScript(
            title: "Welcome to Prompter",
            content: "This is your teleprompter. It sits right under the camera, so you can read while you look at your audience. Press play: after a short countdown the text scrolls up at a steady speed. Change the speed with the minus and plus buttons, or with Shift and the left and right arrow keys. Press the pencil to write your own script.")]
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PrompterViewModel.shared.saveNow() }
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [scripts] in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            DataFile.save(scripts, to: "prompter.json")
        }
    }

    func saveNow() {
        guard let pendingSave else { return }
        pendingSave.cancel()
        self.pendingSave = nil
        DataFile.save(scripts, to: "prompter.json")
    }

    var current: PrompterScript? { scripts.first { $0.id == PrompterFeature.settings.value.selectedId } ?? scripts.first }
    var isActive: Bool { if case .countdown = state { return true }; return state == .running }

    func toggle() { isActive ? pause() : start() }

    func start() {
        if offset >= contentHeight - 1 { offset = 0 }
        countdown?.cancel()
        countdown = Task { @MainActor [weak self] in
            for n in stride(from: 3, through: 1, by: -1) {
                self?.state = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.run()
        }
    }

    private func run() {
        state = .running
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in MainActor.assumeIsolated { PrompterViewModel.shared.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        offset += CGFloat(PrompterFeature.settings.value.scrollSpeed * (now - lastTick))
        lastTick = now
        if offset >= contentHeight { offset = contentHeight; pause() }
    }

    func pause() {
        countdown?.cancel(); countdown = nil
        timer?.invalidate(); timer = nil
        if state != .idle { state = .paused }
    }

    func restart() { pause(); offset = 0; state = .idle }

    func adjustSpeed(_ delta: Double) {
        let r = PrompterFeature.speedRange
        PrompterFeature.settings.value.scrollSpeed = min(max(PrompterFeature.settings.value.scrollSpeed + delta, r.lowerBound), r.upperBound)
    }

    func select(_ id: UUID) { PrompterFeature.settings.value.selectedId = id; restart() }

    func newScript() -> UUID {
        let s = PrompterScript(title: "Untitled script", content: "")
        scripts.append(s)
        select(s.id)
        return s.id
    }

    func delete(_ id: UUID) {
        guard scripts.count > 1 else { return }
        scripts.removeAll { $0.id == id }
        if PrompterFeature.settings.value.selectedId == id { select(scripts[0].id) }
    }

    func binding(_ id: UUID, _ keyPath: WritableKeyPath<PrompterScript, String>) -> Binding<String> {
        Binding(get: { self.scripts.first { $0.id == id }?[keyPath: keyPath] ?? "" },
                set: { v in
                    guard let i = self.scripts.firstIndex(where: { $0.id == id }) else { return }
                    self.scripts[i][keyPath: keyPath] = v
                    self.scripts[i].updatedAt = Date()
                })
    }
}

// MARK: - Tab view

struct PrompterView: View {
    @Environment(NotchModel.self) private var notch
    @State private var keyMonitor: Any?

    var body: some View {
        let vm = PrompterViewModel.shared
        let s = PrompterFeature.settings
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                Text(vm.current?.content ?? "")
                    .font(.system(size: s.value.fontSize, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(width: min(geo.size.width - 40, 520))
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { g in
                        Color.clear.onAppear { vm.contentHeight = g.size.height }
                            .onChange(of: g.size.height) { vm.contentHeight = $1 }
                    })
                    .offset(y: 28 - vm.offset)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                         .init(color: .black, location: 0.62), .init(color: .clear, location: 0.86)],
                                 startPoint: .top, endPoint: .bottom))

            HStack(spacing: 8) {
                Menu {
                    ForEach(vm.scripts) { script in
                        Button { vm.select(script.id) } label: {
                            if script.id == vm.current?.id { Label(script.title, systemImage: "checkmark") } else { Text(script.title) }
                        }
                    }
                    Divider()
                    Button("New Script") { PrompterEditor.open(vm.newScript()) }
                } label: {
                    Chip(title: vm.current?.title ?? "Scripts", symbol: "text.alignleft")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                RoundButton(symbol: "pencil", size: 26) { if let id = vm.current?.id { PrompterEditor.open(id) } }
                Spacer()
                RoundButton(symbol: "minus", size: 26) { vm.adjustSpeed(-10) }
                Text("\(Int(s.value.scrollSpeed))").font(Theme.caption.weight(.semibold)).monospacedDigit().frame(minWidth: 26)
                    .help("Scroll speed (⇧← / ⇧→)")
                RoundButton(symbol: "plus", size: 26) { vm.adjustSpeed(10) }
                RoundButton(symbol: "arrow.counterclockwise", size: 26) { vm.restart() }
                RoundButton(symbol: vm.isActive ? "pause.fill" : "play.fill", size: 30, tint: .black, fill: .white) { vm.toggle() }
            }

            if case .countdown(let n) = vm.state {
                Text("\(n)")
                    .font(.system(size: 44, weight: .bold)).monospacedDigit()
                    .frame(width: 80, height: 80).background(Theme.card, in: Circle())
                    .frame(maxHeight: .infinity)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Motion.snappy, value: n)
            }
        }
        .onChange(of: vm.isActive) { notch.keyboardPinned = $1 }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                guard e.window is NotchPanel, e.modifierFlags.contains(.shift) else { return e }
                switch e.keyCode {
                case 123: vm.adjustSpeed(-10); return nil
                case 124: vm.adjustSpeed(10); return nil
                default: return e
                }
            }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            vm.pause()
            notch.keyboardPinned = false
        }
    }
}

// MARK: - Script editor window

@MainActor
enum PrompterEditor {
    private static var window: NSWindow?

    static func open(_ id: UUID) {
        let w = window ?? {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 380),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.center()
            return w
        }()
        w.title = "Edit Script"
        w.contentView = NSHostingView(rootView: PrompterEditorView(id: id))
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

private struct PrompterEditorView: View {
    let id: UUID
    var body: some View {
        let vm = PrompterViewModel.shared
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: vm.binding(id, \.title)).textFieldStyle(.roundedBorder).font(.system(size: 15, weight: .semibold))
            TextEditor(text: vm.binding(id, \.content)).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(6).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 260)
    }
}

// MARK: - Settings pane

struct PrompterPane: View {
    var body: some View {
        let s = PrompterFeature.settings
        let vm = PrompterViewModel.shared
        SettingsPane(title: "Prompter") {
            SettingsCard(title: "Reading") {
                SettingsRow(title: "Scroll speed", subtitle: "\(Int(s.value.scrollSpeed)) points per second · ⇧← / ⇧→ in the notch") {
                    Slider(value: s.binding(\.scrollSpeed), in: PrompterFeature.speedRange, step: 5).frame(width: 200)
                }
                SettingsRow(title: "Text size", subtitle: "\(Int(s.value.fontSize)) pt") {
                    Slider(value: s.binding(\.fontSize), in: 16...40, step: 1).frame(width: 200)
                }
                SettingsRow(title: "Follow my voice", subtitle: "Not available yet; the prompter scrolls at a steady speed") { EmptyView() }
            }
            SettingsCard(title: "Scripts") {
                ForEach(vm.scripts) { script in
                    SettingsRow(title: script.title, subtitle: "Edited \(script.updatedAt.formatted(.relative(presentation: .named)))") {
                        HStack {
                            if script.id == vm.current?.id { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                            Button("Use") { vm.select(script.id) }.disabled(script.id == vm.current?.id)
                            Button("Edit") { PrompterEditor.open(script.id) }
                            Button { vm.delete(script.id) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                                .buttonStyle(.plain).disabled(vm.scripts.count < 2)
                        }
                    }
                }
                HStack { Spacer(); Button("New Script") { PrompterEditor.open(vm.newScript()) } }.padding(.vertical, 6)
            }
        }
    }
}
