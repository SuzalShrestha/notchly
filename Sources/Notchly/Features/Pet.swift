import SwiftUI

// MARK: - Agent mascots
//
// A small pixel companion per coding agent that mirrors what the agent is doing. It is drawn in one
// Canvas (a single layer, no view tree per limb), and its TimelineView pauses whenever the pet is
// static: under Reduce Motion, or when `animated` is false (snapshots, settings previews).

enum PetMood: Equatable {
    case sleeping                 // no sessions, or nothing has happened for a while
    case idle                     // sessions exist, all quiet
    case thinking                 // prompt submitted, no tool yet
    case working(AgentStep.Kind)  // running a tool; the prop shows which kind
    case alert                    // waiting for permission or input
    case celebrating              // a turn just finished
    case oops                     // the last tool failed a moment ago

    var title: String {
        switch self {
        case .sleeping: "Napping"
        case .idle: "All caught up"
        case .thinking: "Thinking it through"
        case .working(let k): k.activity
        case .alert: "Needs you"
        case .celebrating: "All done!"
        case .oops: "Hit a snag"
        }
    }

    /// Accent used for glows, badges and the hero card tint.
    var tint: Color {
        switch self {
        case .sleeping, .idle: Theme.claude
        case .thinking: Theme.claudeLight
        case .working(let k): k.tint
        case .alert: Theme.warning
        case .celebrating: Theme.success
        case .oops: Theme.danger
        }
    }
}

struct PetView: View {
    var mood: PetMood
    var harness: Harness = .claude
    var size: CGFloat = 64
    var animated = true
    /// Legs step and the body bobs (the roaming mascot sets this while it walks).
    var walking = false
    var facingLeft = false

    var body: some View {
        let still = !animated || Motion.reduceMotion
        // Tiny pets in the closed notch tick slower (nobody can see 30 fps at 24 pt), and a sleeping pet barely moves.
        let rate: Double = mood == .sleeping && !walking ? 1.0 / 12 : (size < 34 ? 1.0 / 20 : 1.0 / 30)
        TimelineView(.animation(minimumInterval: rate, paused: still)) { ctx in
            let t = still ? 0.6 : ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, sz in
                PetPainter(mood: mood, sprite: .of(harness), t: t, detail: size >= 34, walking: walking, facingLeft: facingLeft).draw(&g, sz)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(harness.short) mascot: \(mood.title)")
    }
}

/// Pet whose mood comes from the live agent sessions. Mood changes that depend on time
/// (celebrating fades to idle, idle dozes off) are resolved per frame from the timeline date.
struct AgentPet: View {
    var size: CGFloat = 64
    var body: some View {
        let store = AgentStore.shared
        let list = store.sorted
        let harness = (list.first(where: \.phase.needsAttention) ?? list.first(where: \.phase.isBusy) ?? list.first)?.harness ?? .claude
        if Motion.reduceMotion {
            PetView(mood: store.petMood(at: Date()), harness: harness, size: size, animated: false)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                PetView(mood: store.petMood(at: ctx.date), harness: harness, size: size)
            }
        }
    }
}

// MARK: - Sprites
//
// Pixel characters, one per harness. Claude is a blocky crab-like critter in the spirit of the
// Claude Code terminal mascot; Codex is a small terminal robot; Gemini is a four-point star.
// Eyes, arms and legs are drawn on top so each mood can move them.

private struct Sprite {
    /// `#` body, `d` shade, `s` screen, `a` antenna light (mood tint), `.` empty.
    let rows: [String]
    /// Left and right eye: top cell of a 1×2 eye.
    let eyes: [(Int, Int)]
    /// Two-cell arm stubs beside the body at this row (nil = no arms).
    let armRow: Int?
    let legs: [Int]
    let colors: (top: Color, bottom: Color, shade: Color, screen: Color, eye: Color)

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count + (legs.isEmpty ? 0 : 2) }

    static func of(_ h: Harness) -> Sprite {
        switch h {
        case .claude: claude
        case .codex: codex
        case .gemini: gemini
        }
    }

    static let claude = Sprite(rows: [
        "..############..",
        "..############..",
        "..############..",
        "..############..",
        "..dddddddddddd..",
    ], eyes: [(4, 1), (11, 1)], armRow: 2, legs: [3, 5, 10, 12],
       colors: (Color(hex: 0xE5866A), Color(hex: 0xD97757), Color(hex: 0xB65A3B), .clear, Color(hex: 0x2A1712)))

    static let codex = Sprite(rows: [
        ".......a........",
        ".......#........",
        "...##########...",
        "..############..",
        "..#ssssssssss#..",
        "..#ssssssssss#..",
        "..#ssssssssss#..",
        "..#ssssssssss#..",
        "..############..",
        "...dddddddddd...",
    ], eyes: [(5, 5), (10, 5)], armRow: 6, legs: [4, 6, 9, 11],
       colors: (Color(hex: 0xF4F4F4), Color(hex: 0xD9D9D9), Color(hex: 0xA8A8A8), Color(hex: 0x1C1C1E), Color(hex: 0x7CF0B0)))

    static let gemini = Sprite(rows: [
        ".......#.......",
        "......###......",
        "......###......",
        ".....#####.....",
        "...#########...",
        ".#############.",
        "###############",
        ".#############.",
        "...#########...",
        ".....#####.....",
        "......###......",
        "......###......",
        ".......#.......",
    ], eyes: [(5, 5), (9, 5)], armRow: nil, legs: [],
       colors: (Color(hex: 0x5B8CFF), Color(hex: 0xA77BFF), Color(hex: 0x8A6BE8), .clear, Color(hex: 0x14193A)))
}

// MARK: - Painter

private struct PetPainter {
    let mood: PetMood
    let sprite: Sprite
    let t: Double
    let detail: Bool
    var walking = false
    var facingLeft = false

    func draw(_ g: inout GraphicsContext, _ size: CGSize) {
        let s = min(size.width, size.height)
        let ox = (size.width - s) / 2, oy = (size.height - s) / 2
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        func R(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s) }

        // Motion: hop lifts the whole sprite (pixel art does not squash).
        var hop = 0.0
        switch mood {
        case .sleeping: hop = 0
        case .idle: hop = (sin(t * 2) + 1) * 0.008
        case .thinking: hop = (sin(t * 2.4) + 1) * 0.01
        case .working: hop = abs(sin(t * 6)) * 0.022
        case .alert: hop = max(0, sin(t * 7)) * 0.06
        case .celebrating: hop = abs(sin(t * 6.5)) * 0.085
        case .oops: hop = 0
        }
        // No legs: walking is a string of small hops.
        if walking { hop = sprite.legs.isEmpty ? abs(sin(t * 9)) * 0.08 : abs(sin(t * 16)) * 0.015 }
        let shake = mood == .oops ? sin(t * 18) * 0.006 * (1 + sin(t * 1.5)) : 0

        let cell = 0.78 * s / 16
        let spriteW = Double(sprite.width) * cell, spriteH = Double(sprite.height) * cell
        let feet = 0.86 - hop
        let x0 = ox + 0.5 * s - spriteW / 2 + shake * s, y0 = oy + feet * s - spriteH

        // Ground light: a soft glow that shrinks while the pet is in the air.
        let glowW = 0.52 * (1 - hop * 3.5)
        g.fill(Path(ellipseIn: R(0.5 - glowW / 2, 0.875, glowW, 0.06)), with: .color(mood.tint.opacity(0.28)))

        var c = g
        if facingLeft {
            c.translateBy(x: x0 * 2 + spriteW, y: 0)
            c.scaleBy(x: -1, y: 1)
        }
        func px(_ x: Int, _ y: Int, _ color: Color) {
            // A hair of overlap hides seams between cells.
            c.fill(Path(CGRect(x: x0 + Double(x) * cell, y: y0 + Double(y) * cell, width: cell + 0.4, height: cell + 0.4)), with: .color(color))
        }

        // Body: a vertical gradient from top to bottom colour, row by row.
        let n = max(sprite.rows.count - 1, 1)
        for (y, row) in sprite.rows.enumerated() {
            let fill = mix(sprite.colors.top, sprite.colors.bottom, Double(y) / Double(n))
            for (x, ch) in row.enumerated() {
                switch ch {
                case "#": px(x, y, fill)
                case "d": px(x, y, sprite.colors.shade)
                case "s": px(x, y, sprite.colors.screen)
                case "a": px(x, y, mood == .sleeping ? sprite.colors.shade : mood.tint)
                default: break
                }
            }
        }

        // Arms: two cells each side; raised one row per step.
        if let ay = sprite.armRow {
            let (l, r) = armLift()
            let w = sprite.width
            for (x, lift) in [(0, l), (1, l), (w - 2, r), (w - 1, r)] { px(x, ay - lift, sprite.colors.bottom) }
        }

        // Legs: two cells tall; while walking, alternate pairs lift.
        if !sprite.legs.isEmpty {
            let ly = sprite.rows.count
            let phase = Int(t * 8) % 2
            for (i, x) in sprite.legs.enumerated() {
                let lifted = (walking || mood == .celebrating) && i % 2 == phase
                px(x, ly, sprite.colors.shade)
                if !lifted { px(x, ly + 1, sprite.colors.shade) }
            }
        }

        // Eyes: a few cell patterns per mood; the right eye mirrors the left.
        let (pattern, look) = eyePattern()
        for (i, e) in sprite.eyes.enumerated() {
            let mirror = i == 1 ? -1 : 1
            for (dx, dy) in pattern { px(e.0 + dx * mirror + look.0, e.1 + dy + look.1, sprite.colors.eye) }
        }

        // Props and effects.
        guard detail || mood == .alert else { return }
        switch mood {
        case .sleeping: drawZs(&g, s: s, P)
        case .thinking: drawThoughts(&g, s: s, P)
        case .working(let k): drawProp(&g, kind: k, s: s, center: P(0.84, 0.74 - hop * 0.5))
        case .alert: drawAlertBubble(&g, s: s, center: P(0.80, 0.20))
        case .celebrating: drawConfetti(&g, s: s, P)
        case .oops: drawSweat(&g, s: s, at: CGPoint(x: x0 + spriteW - cell, y: y0 + cell))
        case .idle: break
        }
    }

    private func mix(_ a: Color, _ b: Color, _ f: Double) -> Color {
        let x = NSColor(a).usingColorSpace(.sRGB) ?? .white, y = NSColor(b).usingColorSpace(.sRGB) ?? .white
        return Color(red: x.redComponent + (y.redComponent - x.redComponent) * f,
                     green: x.greenComponent + (y.greenComponent - x.greenComponent) * f,
                     blue: x.blueComponent + (y.blueComponent - x.blueComponent) * f)
    }

    /// Rows each arm is raised (left, right).
    private func armLift() -> (Int, Int) {
        switch mood {
        case .alert: return (0, Int(t * 6) % 2 + 1)                       // waving
        case .celebrating: return (Int(t * 8) % 2 + 1, Int(t * 8 + 1) % 2 + 1)
        case .thinking: return (0, 1)                                      // hand to chin
        case .working(let k):
            switch k {
            case .command, .edit, .write: return (Int(t * 14) % 2, Int(t * 14 + 1) % 2)   // typing
            default: return (0, 0)
            }
        default: return (0, 0)
        }
    }

    /// Cells of the left eye relative to its anchor, and a gaze shift in cells.
    private func eyePattern() -> ([(Int, Int)], (Int, Int)) {
        switch mood {
        case .sleeping: return ([(-1, 1), (0, 1), (1, 1)], (0, 0))
        case .celebrating: return ([(-1, 1), (0, 0), (1, 1)], (0, 0))
        case .oops: return ([(-1, 0), (0, 1), (-1, 2)], (0, 0))
        case .alert: return ([(0, 0), (0, 1), (1, 0), (1, 1)], (0, 0))
        default: break
        }
        var look = (0, 0)
        switch mood {
        case .thinking: look = (1, -1)
        case .working(let k) where k == .read || k == .search || k == .web: look = (sin(t * 2.4) > 0 ? 1 : -1, 0)
        case .idle: look = (sin(t * 0.55) > 0.6 ? 1 : (sin(t * 0.55) < -0.6 ? -1 : 0), 0)
        default: break
        }
        // Blink: one row for a moment every few seconds.
        let blink = t.truncatingRemainder(dividingBy: 3.8) < 0.13
        return (blink ? [(0, 1)] : [(0, 0), (0, 1)], look)
    }

    // MARK: Parts

    private func drawZs(_ g: inout GraphicsContext, s: Double, _ P: (Double, Double) -> CGPoint) {
        for i in 0..<3 {
            let ph = (t * 0.32 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            var c = g
            c.opacity = sin(ph * .pi) * 0.85
            let text = Text("z").font(.system(size: (0.10 + ph * 0.07) * s, weight: .heavy, design: .rounded)).foregroundColor(Color(hex: 0xBFD4FF))
            c.draw(text, at: P(0.72 + ph * 0.16, 0.34 - ph * 0.26))
        }
    }

    private func drawThoughts(_ g: inout GraphicsContext, s: Double, _ P: (Double, Double) -> CGPoint) {
        let dots: [(Double, Double, Double)] = [(0.75, 0.30, 0.022), (0.81, 0.21, 0.03), (0.89, 0.11, 0.042)]
        for (i, d) in dots.enumerated() {
            let a = 0.3 + 0.7 * max(0, sin(t * 3.2 - Double(i) * 0.9))
            let c = P(d.0, d.1), r = d.2 * s
            g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(a)))
        }
    }

    private func drawProp(_ g: inout GraphicsContext, kind: AgentStep.Kind, s: Double, center c: CGPoint) {
        let r = 0.115 * s
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        g.fill(disc, with: .color(Color(white: 0.13)))
        g.stroke(disc, with: .color(kind.tint.opacity(0.9)), lineWidth: 0.014 * s)
        var icon = g.resolve(Image(systemName: kind.symbol))
        icon.shading = .color(kind.tint)
        let isz = r * 1.1
        g.draw(icon, in: CGRect(x: c.x - isz / 2, y: c.y - isz / 2, width: isz, height: isz))
    }

    private func drawAlertBubble(_ g: inout GraphicsContext, s: Double, center c: CGPoint) {
        let pulse = 1 + sin(t * 7) * 0.07
        let r = 0.11 * s * pulse
        var bubble = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        bubble.move(to: CGPoint(x: c.x - r * 0.55, y: c.y + r * 0.7))
        bubble.addLine(to: CGPoint(x: c.x - r * 0.95, y: c.y + r * 1.35))
        bubble.addLine(to: CGPoint(x: c.x - r * 0.05, y: c.y + r * 0.95))
        g.fill(bubble, with: .color(Theme.warning))
        let mark = Text("!").font(.system(size: r * 1.45, weight: .black, design: .rounded)).foregroundColor(.black)
        g.draw(mark, at: c)
    }

    private func drawConfetti(_ g: inout GraphicsContext, s: Double, _ P: (Double, Double) -> CGPoint) {
        let colors: [Color] = [Color(hex: 0xFFD166), Theme.claudeLight, Theme.success, Color(hex: 0x7AB8FF), Color(hex: 0xFF8FB1)]
        let spots: [(Double, Double)] = [(0.14, 0.26), (0.86, 0.24), (0.10, 0.60), (0.90, 0.58), (0.50, 0.08)]
        for (i, sp) in spots.enumerated() {
            let tw = 0.5 + 0.5 * sin(t * 5 + Double(i) * 1.3)
            let r = (0.035 + 0.03 * tw) * s
            var c = g
            let p = P(sp.0, sp.1 - tw * 0.03)
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(t * 2 + Double(i)))
            c.opacity = 0.4 + 0.6 * tw
            c.fill(SparkShape(pinch: 0.22).path(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(colors[i]))
        }
    }

    private func drawSweat(_ g: inout GraphicsContext, s: Double, at p: CGPoint) {
        let drop = (t * 0.9).truncatingRemainder(dividingBy: 1)
        let y = p.y + drop * 0.08 * s
        var d = Path()
        let w = 0.05 * s, h = 0.075 * s
        d.move(to: CGPoint(x: p.x, y: y))
        d.addQuadCurve(to: CGPoint(x: p.x, y: y + h), control: CGPoint(x: p.x + w, y: y + h * 0.75))
        d.addQuadCurve(to: CGPoint(x: p.x, y: y), control: CGPoint(x: p.x - w, y: y + h * 0.75))
        var c = g
        c.opacity = 1 - drop * 0.7
        c.fill(d, with: .color(Color(hex: 0x8CC8FF)))
    }
}

// MARK: - Roaming mascots
//
// One mascot per harness with live sessions. Each lives in a small click-through panel one level
// under the notch panel, so it can hide inside the notch and drop out of it. It hops between the
// top edges of the frontmost windows and the floor of each screen.

@MainActor @Observable
final class MascotState {
    var mood: PetMood = .idle
    var bubble: String?
    var walking = false
    var facingLeft = false
}

@MainActor
final class MascotRoamer {
    static let shared = MascotRoamer()
    private var walkers: [Harness: MascotWalker] = [:]
    private var timer: Timer?

    func start() {
        // ponytail: polls the store at 2 Hz instead of observing it; enough for a mascot, cheap for a few sessions.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { MascotRoamer.shared.tick() }
        }
    }

    private func tick() {
        let set = AgentsFeature.settings.value
        let sessions = Array(AgentStore.shared.sessions.values)
        let active = set.enabled && set.showPet && set.roams ? Set(sessions.map(\.harness)) : []
        for (h, w) in walkers where !active.contains(h) { w.leave(); walkers[h] = nil }
        let now = Date()
        for (slot, h) in Harness.allCases.enumerated() where active.contains(h) {
            let w = walkers[h] ?? MascotWalker(harness: h, slot: slot)
            walkers[h] = w
            w.tick(sessions.filter { $0.harness == h }, now: now)
        }
    }
}

@MainActor
final class MascotWalker {
    static let size: CGFloat = 46
    /// Mascot in the top-left corner; the bubble hangs to its right and grows down, clear of the notch.
    static let panelSize = CGSize(width: 300, height: 92)

    private struct Move {
        var to: CGPoint
        var duration: Double
        var arc: CGFloat = 0
        var walk = false
        var then: (() -> Void)?
        var from = CGPoint.zero
        var start: Date?
    }

    let harness: Harness
    private let slot: Int
    private let state = MascotState()
    private let panel: NotchPanel
    /// Feet of the mascot, in screen coordinates.
    private var pos: CGPoint
    private var moves: [Move] = []
    private var anim: Timer?
    private var atNotch = false
    private var nextWander = Date()

    init(harness: Harness, slot: Int) {
        self.harness = harness
        self.slot = slot
        panel = NotchPanel(frame: CGRect(origin: .zero, size: Self.panelSize))
        panel.level = .statusBar   // under the notch panel (.statusBar + 1): hidden by the notch until it drops out
        panel.sharingType = Settings.general.value.showNotchInScreenshots ? .readOnly : .none
        let host = NSHostingView(rootView: MascotPanelView(harness: harness, state: state))
        host.sizingOptions = []
        panel.contentView = host
        pos = .zero
        pos = notchHidden
        place()
        panel.orderFrontRegardless()
        // Enter by dropping out of the notch.
        go(notchOut, duration: 0.55)
    }

    // MARK: Places

    private var home: NSScreen {
        NotchManager.shared.controllers.first(where: \.model.hasPhysicalNotch)?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }
    private var notchX: CGFloat { home.frame.midX - 44 + CGFloat(slot) * 40 }
    /// Above the top edge, behind the notch.
    private var notchHidden: CGPoint { CGPoint(x: notchX, y: home.frame.maxY + 4) }
    /// Hanging just under the notch.
    private var notchOut: CGPoint {
        CGPoint(x: notchX, y: home.frame.maxY - max(home.safeAreaInsets.top, 24) - Self.size * 0.8)
    }

    /// Frontmost normal windows of other apps, front to back, in Cocoa screen coordinates.
    private func windowRects() -> [CGRect] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        var out: [CGRect] = []
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0
            && (w[kCGWindowOwnerPID as String] as? Int32) != getpid()
            && (w[kCGWindowAlpha as String] as? Double ?? 1) > 0 {
            guard let d = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d),
                  r.width >= 160, r.height >= 80 else { continue }
            out.append(CGRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height))
            if out.count == 8 { break }
        }
        return out
    }

    /// A free spot on the top edge of a visible window, or on a screen floor.
    private func randomSpot() -> CGPoint {
        let rects = windowRects()
        // The floor comes up about as often as any one window.
        if Int.random(in: 0...rects.count) > 0 {
            for _ in 0..<8 {
                let i = Int.random(in: rects.indices)
                let r = rects[i]
                let p = CGPoint(x: .random(in: r.minX + 30...max(r.minX + 30, r.maxX - 30)), y: r.maxY)
                if standable(p, on: i, rects) { return p }
            }
        }
        let f = (NSScreen.screens.randomElement() ?? home).visibleFrame
        return CGPoint(x: .random(in: f.minX + 40...f.maxX - 40), y: f.minY)
    }

    /// Not covered by a window in front, with head room below the menu bar.
    private func standable(_ p: CGPoint, on i: Int, _ rects: [CGRect]) -> Bool {
        let above = CGPoint(x: p.x, y: p.y + 4)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(above) }),
              p.y + Self.size < screen.visibleFrame.maxY else { return false }
        return !rects[..<i].contains { $0.contains(above) }
    }

    /// Still on a floor or on an uncovered window edge (windows move and close under it).
    private func supported(_ p: CGPoint) -> Bool {
        if NSScreen.screens.contains(where: { abs($0.visibleFrame.minY - p.y) < 3 && $0.frame.minX <= p.x && p.x <= $0.frame.maxX }) { return true }
        let rects = windowRects()
        return rects.indices.contains { abs(rects[$0].maxY - p.y) < 3 && rects[$0].minX <= p.x && p.x <= rects[$0].maxX && standable(p, on: $0, rects) }
    }

    // MARK: Behaviour

    /// What the bubble says: a request first, then a finish from the last few seconds.
    static func note(_ list: [AgentSession], now: Date) -> String? {
        if let s = list.first(where: \.phase.needsAttention) { return "\(s.project): \(s.attentionLine)" }
        if let s = list.filter({ $0.phase == .done && now.timeIntervalSince($0.updatedAt) < 5 }).max(by: { $0.updatedAt < $1.updatedAt }) {
            return "Done! \(s.title.isEmpty ? s.project : s.title)"
        }
        return nil
    }

    func tick(_ sessions: [AgentSession], now: Date) {
        let mood = AgentStore.mood(sessions, at: now)
        if mood != state.mood { state.mood = mood }
        let note = Self.note(sessions, now: now)
        if note != state.bubble { withAnimation(Motion.respecting(Motion.bouncy)) { state.bubble = note } }
        if note != nil {
            if !atNotch { pop() }
            return
        }
        if atNotch { atNotch = false; moves.removeAll(); go(randomSpot()); return }
        guard moves.isEmpty else { return }
        if !supported(pos) { go(randomSpot()); return }
        // Quiet agents rest; busy ones wander now and then.
        switch mood { case .sleeping, .idle, .alert: return; default: break }
        if now >= nextWander, !Motion.reduceMotion {
            nextWander = now.addingTimeInterval(.random(in: 6...14))
            go(randomSpot())
        }
    }

    /// Hide in the notch, then drop out of it.
    private func pop() {
        atNotch = true
        moves.removeAll()
        go(notchHidden, duration: 0)
        go(notchOut, duration: 0.55)
    }

    /// Climb back into the notch, then close.
    func leave() {
        state.bubble = nil
        moves.removeAll()
        if !atNotch { go(notchOut) }
        go(notchHidden, duration: 0.35) { [panel] in panel.orderOut(nil); panel.close() }
    }

    private func go(_ to: CGPoint, duration: Double? = nil, then: (() -> Void)? = nil) {
        let from = moves.last?.to ?? pos
        let d = hypot(to.x - from.x, to.y - from.y)
        let walk = abs(to.y - from.y) < 2 && duration == nil
        let auto = walk ? Double(d / 110) : 0.45 + Double(d) / 1400
        moves.append(Move(to: to, duration: Motion.reduceMotion ? 0 : min(duration ?? auto, 7),
                          arc: walk || duration != nil ? 0 : min(140, 30 + d * 0.15), walk: walk, then: then))
        guard anim == nil else { return }
        // The timer holds the walker until its moves finish, so a leaving mascot still reaches the notch.
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [self] _ in MainActor.assumeIsolated { step() } }
        RunLoop.main.add(t, forMode: .common)
        anim = t
    }

    private func step() {
        guard !moves.isEmpty else {
            anim?.invalidate(); anim = nil
            state.walking = false
            return
        }
        let now = Date()
        if moves[0].start == nil {
            moves[0].start = now
            moves[0].from = pos
            if abs(moves[0].to.x - pos.x) > 2 { state.facingLeft = moves[0].to.x < pos.x }
            state.walking = moves[0].walk || moves[0].arc > 0
        }
        let m = moves[0]
        let p = m.duration <= 0 ? 1 : min(1, now.timeIntervalSince(m.start ?? now) / m.duration)
        let e = m.walk ? p : (1 - cos(p * .pi)) / 2
        pos = CGPoint(x: m.from.x + (m.to.x - m.from.x) * e, y: m.from.y + (m.to.y - m.from.y) * e + m.arc * sin(p * .pi))
        place()
        if p >= 1 { moves.removeFirst().then?() }
    }

    private func place() {
        panel.setFrameOrigin(CGPoint(x: pos.x - Self.size / 2, y: pos.y - Self.size * 0.14 - (Self.panelSize.height - Self.size)))
    }
}

private struct MascotPanelView: View {
    let harness: Harness
    let state: MascotState

    var body: some View {
        ZStack(alignment: .topLeading) {
            PetView(mood: state.mood, harness: harness, size: MascotWalker.size, walking: state.walking, facingLeft: state.facingLeft)
            if let b = state.bubble {
                Text(b)
                    .font(Theme.caption.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(harness.tint.opacity(0.6), lineWidth: 1))
                    .frame(maxWidth: MascotWalker.panelSize.width - MascotWalker.size - 8, alignment: .leading)
                    .padding(.leading, MascotWalker.size + 2).padding(.top, MascotWalker.size * 0.5)
                    .transition(.scale(scale: 0.5, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .frame(width: MascotWalker.panelSize.width, height: MascotWalker.panelSize.height, alignment: .topLeading)
    }
}
