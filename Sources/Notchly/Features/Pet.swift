import SwiftUI

// MARK: - Agent mascots
//
// A small pixel companion per coding agent that acts out what the agent is doing. One Canvas draws
// it (a single layer, no view tree per limb). The motion follows the classic animation rules: a hop
// has anticipation, a stretch in the air and a squash on landing; the body breathes; the eyes blink
// at uneven times and jump between targets as real eyes do; and each new mood opens with a short
// reaction (a startle, a flinch, a stretch on waking). Randomness comes from a hash of the time,
// so every frame of a moment agrees and snapshots repeat. The TimelineView pauses whenever the pet
// is static: under Reduce Motion, or when `animated` is false (snapshots, settings previews).

/// What a working mascot acts out: one per kind of step, and one per intent for shell commands.
enum PetAct: String, CaseIterable {
    case read, edit, write, terminal, test, build, git, ship, install, delete, download
    case search, web, helper, question, plan, connector, tool

    init(_ step: AgentStep) {
        switch step.kind {
        case .read: self = .read
        case .edit: self = .edit
        case .write: self = .write
        case .command: self = AgentStep.act(command: step.subject)
        case .search: self = .search
        case .web: self = .web
        case .task: self = .helper
        case .question: self = .question
        case .other:
            // MCP tools: `mcp__server__tool` (Claude) or `server__tool` (Grok).
            if step.tool.contains("__") { self = .connector }
            else if step.tool.hasSuffix("PlanMode") { self = .plan }
            else { self = .tool }
        }
    }

    var title: String {
        switch self {
        case .read: "Reading"; case .edit: "Editing code"; case .write: "Writing a file"; case .terminal: "Running a command"
        case .test: "Running tests"; case .build: "Building"; case .git: "Checking history"; case .ship: "Shipping changes"
        case .install: "Installing packages"; case .delete: "Cleaning up"; case .download: "Downloading"
        case .search: "Searching"; case .web: "Researching"; case .helper: "Asking a helper"; case .question: "Has a question"
        case .plan: "Making a plan"; case .connector: "Using an app"; case .tool: "Using a tool"
        }
    }

    var symbol: String {
        switch self {
        case .read: "book.fill"; case .edit: "pencil"; case .write: "doc.fill"; case .terminal: "terminal.fill"
        case .test: "flask.fill"; case .build: "hammer.fill"; case .git: "arrow.triangle.branch"; case .ship: "paperplane.fill"
        case .install: "shippingbox.fill"; case .delete: "trash.fill"; case .download: "arrow.down.circle.fill"
        case .search: "magnifyingglass"; case .web: "globe.americas.fill"; case .helper: "person.2.fill"; case .question: "questionmark"
        case .plan: "list.bullet.clipboard.fill"; case .connector: "puzzlepiece.extension.fill"; case .tool: "wrench.adjustable.fill"
        }
    }

    /// One hue per act, tuned to read on the black panel.
    var tint: Color {
        switch self {
        case .read: Color(hex: 0x7AB8FF); case .edit: Color(hex: 0xFFB45E); case .write: Color(hex: 0xFFD166)
        case .terminal: Color(hex: 0x6EE7A8); case .test: Color(hex: 0x9BE15D); case .build: Color(hex: 0xFF9F43)
        case .git: Color(hex: 0xF78166); case .ship: Color(hex: 0x58A6FF); case .install: Color(hex: 0xD9A86C)
        case .delete: Color(hex: 0xFF6B6B); case .download: Color(hex: 0x4FD1C5); case .search: Color(hex: 0xB79CFF)
        case .web: Color(hex: 0x5ED6E6); case .helper: Color(hex: 0xFF8FB1); case .question: Color(nsColor: .systemOrange)
        case .plan: Color(hex: 0xA0E7E5); case .connector: Color(hex: 0xC792EA); case .tool: Color(white: 0.75)
        }
    }
}

enum PetMood: Equatable {
    case sleeping           // no sessions, or nothing has happened for a while
    case idle               // sessions exist, all quiet
    case thinking           // prompt submitted, no tool yet
    case working(PetAct)    // running a tool; the act shows what kind
    case alert              // waiting for permission or input
    case celebrating        // a turn just finished
    case oops               // the last tool failed a moment ago
    case stopped            // you interrupted the agent a moment ago

    var title: String {
        switch self {
        case .sleeping: "Napping"
        case .idle: "All caught up"
        case .thinking: "Thinking it through"
        case .working(let a): a.title
        case .alert: "Needs you"
        case .celebrating: "All done!"
        case .oops: "Hit a snag"
        case .stopped: "Stopped"
        }
    }

    /// Accent used for glows, badges and the hero card tint.
    var tint: Color {
        switch self {
        case .sleeping, .idle: Theme.claude
        case .thinking: Theme.claudeLight
        case .working(let a): a.tint
        case .alert: Theme.warning
        case .celebrating: Theme.success
        case .oops: Theme.danger
        case .stopped: Color(hex: 0xA7A9B4)
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
    /// The mood before this one and when it changed: each mood opens with a short reaction.
    @State private var change: (from: PetMood?, at: Double) = (nil, -100)

    var body: some View {
        let still = !animated || Motion.reduceMotion
        // Tiny pets in the closed notch tick slower (nobody can see 30 fps at 24 pt), and a sleeping pet barely moves.
        let rate: Double = mood == .sleeping && !walking ? 1.0 / 15 : (size < 34 ? 1.0 / 20 : 1.0 / 30)
        TimelineView(.animation(minimumInterval: rate, paused: still)) { ctx in
            let t = still ? 0.6 : ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, sz in
                PetPainter(mood: mood, sprite: .of(harness), t: t, from: change.from, age: still ? 99 : t - change.at,
                           detail: size >= 34, walking: walking, facingLeft: facingLeft).draw(&g, sz)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: mood) { old, _ in change = (old, Date().timeIntervalSinceReferenceDate) }
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
// Pixel characters, one per harness, each with its own build and way of moving:
// Claude is a bouncy blocky critter in the spirit of the Claude Code terminal mascot; Codex is a
// terminal robot that moves in steps; Gemini is a floating four-point star; Grok is a dark orb with
// a light slash and a sly side-eye; Antigravity is a hover pod on a thruster; Droid is a heavy
// one-eyed worker bot. Eyes, arms and legs are drawn on top so each mood can move them.

struct PetSprite {
    enum Build { case hopper, mech, floater }
    /// `#` body, `d` shade, `s` screen, `w` accent, `a` antenna light (mood tint), `.` empty.
    let rows: [String]
    /// Left and right eye: top cell of a 1×2 eye.
    let eyes: [(Int, Int)]
    /// Two-cell arm stubs beside the body at this row (nil = no arms).
    let armRow: Int?
    let legs: [Int]
    let colors: (top: Color, bottom: Color, shade: Color, screen: Color, eye: Color, accent: Color)
    var build = Build.hopper
    /// Hop height scale: heavy bots jump less.
    var bounce = 1.0
    /// Slow sway, in radians, for floaters.
    var wobble = 0.0
    /// One wide eye (two cells per column).
    var bigEye = false
    var thruster = false
    /// Now and then gives you a side-eye when idle.
    var smug = false

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count + (legs.isEmpty ? 0 : 2) }

    static func of(_ h: Harness) -> PetSprite {
        switch h {
        case .claude: claude
        case .codex: codex
        case .gemini: gemini
        case .grok: grok
        case .antigravity: antigravity
        case .droid: droid
        }
    }

    static let claude = PetSprite(rows: [
        "..############..",
        "..############..",
        "..############..",
        "..############..",
        "..dddddddddddd..",
    ], eyes: [(4, 1), (11, 1)], armRow: 2, legs: [3, 5, 10, 12],
       colors: (Color(hex: 0xE5866A), Color(hex: 0xD97757), Color(hex: 0xB65A3B), .clear, Color(hex: 0x2A1712), .clear))

    static let codex = PetSprite(rows: [
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
       colors: (Color(hex: 0xF4F4F4), Color(hex: 0xD9D9D9), Color(hex: 0xA8A8A8), Color(hex: 0x1C1C1E), Color(hex: 0x7CF0B0), .clear),
       build: .mech)

    static let gemini = PetSprite(rows: [
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
       colors: (Color(hex: 0x5B8CFF), Color(hex: 0xA77BFF), Color(hex: 0x8A6BE8), .clear, Color(hex: 0x14193A), .clear),
       build: .floater, wobble: 0.07)

    static let grok = PetSprite(rows: [
        ".....######.....",
        "...##########...",
        "..##########w#..",
        ".##########w###.",
        ".#########w####.",
        ".########w#####.",
        "..######w#####..",
        "...####w#####...",
        ".....dddddd.....",
    ], eyes: [(4, 3), (8, 3)], armRow: 4, legs: [6, 9],
       colors: (Color(hex: 0x8A8A96), Color(hex: 0x4A4A55), Color(hex: 0x2F2F38), .clear, Color(hex: 0xFFFFFF), Color(hex: 0xF4F4F6)),
       smug: true)

    static let antigravity = PetSprite(rows: [
        ".....######.....",
        "....#ssssss#....",
        "...#ssssssss#...",
        "...#ssssssss#...",
        "..############..",
        "..############..",
        "..############..",
        "....dddddddd....",
    ], eyes: [(6, 2), (9, 2)], armRow: 5, legs: [],
       colors: (Color(hex: 0x5B9DFF), Color(hex: 0x2BC4B4), Color(hex: 0x1F7FA8), Color(hex: 0x0E2233), Color(hex: 0xBFF6FF), .clear),
       build: .floater, wobble: 0.03, thruster: true)

    static let droid = PetSprite(rows: [
        "........a.......",
        "........#.......",
        "...##########...",
        "..############..",
        "..##ssssssss##..",
        "..##ssssssss##..",
        "..##ssssssss##..",
        "..############..",
        "...dddddddddd...",
    ], eyes: [(7, 4)], armRow: 5, legs: [4, 6, 9, 11],
       colors: (Color(hex: 0xEDE8E0), Color(hex: 0xC9C1B5), Color(hex: 0x8C8275), Color(hex: 0x1A1A1A), Color(hex: 0xFF7A1A), .clear),
       bounce: 0.6, bigEye: true)
}

// MARK: - Painter

struct PetPainter {
    let mood: PetMood
    let sprite: PetSprite
    let t: Double
    /// Mood before this one, and seconds since it changed (large = no reaction).
    var from: PetMood?
    var age = 99.0
    var detail = true
    var walking = false
    var facingLeft = false

    enum Eyes { case open, blink, half, closed, happy, wide, dizzy }
    enum Legs { case stand, walk, tap, tuck }
    enum Mouth { case smile, o }

    /// Where the body is and what each part does in this frame. `squash` > 0 flattens, < 0 stretches.
    struct Pose {
        var lift = 0.0, squash = 0.0, tilt = 0.0, dx = 0.0
        var arms = (0, 0)
        var eyes = Eyes.open
        var look = (0, 0)
        var legs = Legs.stand
        var mouth: Mouth?
        var blush = false
    }

    // MARK: Timing helpers

    /// Stable pseudo-random value in 0..<1 (same input, same output, so the frames of one moment agree).
    static func noise(_ n: Int, _ salt: Int = 0) -> Double {
        var x = UInt64(bitPattern: Int64(n &* 73_856_093 ^ salt &* 19_349_663))
        x ^= x >> 33; x &*= 0xff51_afd7_ed55_8ccd; x ^= x >> 33; x &*= 0xc4ce_b9fe_1a85_ec53; x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }

    /// One hop, p in 0...1: crouch (anticipation), stretch on the way up and down, squash on landing.
    static func hop(_ p: Double, height h: Double) -> (lift: Double, squash: Double) {
        let p = min(max(p, 0), 1)
        if p < 0.2 { return (0, 0.13 * sin(p / 0.2 * .pi)) }
        if p < 0.78 {
            let q = (p - 0.2) / 0.58
            return (h * 4 * q * (1 - q), -0.09 * abs(1 - 2 * q) * min(1, q * 8, (1 - q) * 8))
        }
        let r = (p - 0.78) / 0.22
        return (0, 0.15 * sin(r * .pi) * (1 - 0.4 * r))
    }

    /// 0 → 1 with a springy overshoot; x in seconds.
    static func spring(_ x: Double) -> Double { x <= 0 ? 0 : 1 - exp(-6 * x) * cos(16 * x) }
    static func easeInOut(_ x: Double) -> Double { let x = min(max(x, 0), 1); return x * x * (3 - 2 * x) }
    /// A drop that bounces twice before it rests.
    static func bounce(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        if x < 0.55 { return pow(x / 0.55, 2) }
        if x < 0.82 { let k = (x - 0.685) / 0.135; return 1 - 0.18 * (1 - k * k) }
        let k = (x - 0.91) / 0.09; return 1 - 0.05 * max(0, 1 - k * k)
    }
    private func cycle(_ period: Double, _ offset: Double = 0) -> Double { ((t + offset) / period).truncatingRemainder(dividingBy: 1) }

    // MARK: Pose

    func pose() -> Pose {
        var p = Pose()
        // Robots move in steps; everyone else moves smoothly.
        let t = sprite.build == .mech ? (self.t * 12).rounded(.down) / 12 : self.t
        func breathe(_ period: Double, _ depth: Double) -> Double { -sin(t * 2 * .pi / period) * depth }

        switch mood {
        case .sleeping:
            p.squash = breathe(4.6, 0.035)
            p.eyes = .closed
            p.tilt = 0.05
            // A twitch in a dream, now and then.
            let b = Int(t / 7)
            if Self.noise(b, 1) > 0.55, t - Double(b) * 7 < 0.25 { p.dx = sin(t * 80) * 0.006; p.eyes = .half }
        case .idle:
            idle(&p, t)
        case .thinking:
            p.squash = breathe(2.6, 0.02)
            p.tilt = sin(t * 0.9) * 0.05
            p.arms = (0, 1)   // hand to chin
            p.look = (Self.noise(Int(t / 1.3), 2) > 0.35 ? 1 : 0, -1)
        case .working(let act):
            work(&p, act, t)
        case .alert:
            // A "hey!" hop every 1.6 s while one hand waves.
            (p.lift, p.squash) = Self.hop(min(1, cycle(1.6) * 1.5), height: 0.07)
            p.arms = (0, Int(t * 6) % 2 + 1)
            p.eyes = .wide
        case .celebrating:
            (p.lift, p.squash) = Self.hop(cycle(0.72), height: 0.07)
            p.arms = (Int(t * 8) % 2 + 1, Int(t * 8 + 1) % 2 + 1)
            p.eyes = .happy; p.blush = true; p.mouth = .smile
        case .oops:
            p.squash = breathe(1.2, 0.02)
            p.tilt = -0.05
            p.arms = (0, Int(t * 4) % 2 + 1)   // scratches its head
            p.look = (0, 1)
        case .stopped:
            p.squash = breathe(3.2, 0.02)
            p.tilt = 0.04
            p.eyes = .half
            p.look = (-1, 1)   // a sheepish look down
        }
        react(&p)

        if walking {
            if sprite.build == .floater { p.lift = 0.03 + sin(t * 4) * 0.012; p.tilt = 0.09 }   // glides, leaning in
            else { p.lift = abs(sin(t * 16)) * 0.015; p.legs = .walk; p.tilt = 0.03 }
        } else if sprite.build == .floater {
            p.lift += (mood == .sleeping ? 0.015 : 0.035) + sin(t * 1.7) * 0.012
            p.tilt += sin(t * 0.8) * sprite.wobble
        }
        p.lift *= sprite.bounce
        if sprite.build == .mech { p.squash *= 0.35 }   // metal hardly squashes
        if p.lift > 0.025, p.legs == .stand, sprite.build != .floater { p.legs = .tuck }
        blink(&p)
        return p
    }

    private func idle(_ p: inout Pose, _ t: Double) {
        p.squash = -sin(t * 2 * .pi / 3.4) * 0.02
        // Every 6 s it picks a small thing to do, as a person waiting does.
        let b = Int(t / 6), local = t - Double(b) * 6
        switch Int(Self.noise(b, 3) * 6) {
        case 0: p.look = (Int(Self.noise(Int(t / 0.7), 4) * 3) - 1, 0)   // looks around
        case 1 where local < 0.8: (p.lift, p.squash) = Self.hop(local / 0.8, height: 0.045)
        case 2 where local < 1.5:   // a stretch and a yawn
            let k = local / 1.5
            p.squash = -0.1 * sin(k * .pi); p.arms = (2, 2)
            if k > 0.25, k < 0.75 { p.eyes = .closed; p.mouth = .o }
        case 3 where local < 2: p.legs = .tap
        case 5 where sprite.smug: p.eyes = .half; p.look = (1, 0)
        default: break
        }
    }

    private func work(_ p: inout Pose, _ act: PetAct, _ t: Double) {
        p.squash = -sin(t * 2 * .pi / 1.8) * 0.02
        p.lift = abs(sin(t * 5)) * 0.01
        let typing = (Int(t * 9) % 2, Int(t * 9 + 1) % 2)
        switch act {
        case .terminal, .edit, .write, .test: p.arms = typing; p.look = (0, 1)
        case .build:
            let k = cycle(0.55)
            p.arms = (0, k < 0.7 ? 2 : 0); p.look = (1, 0)
            if k > 0.7, k < 0.8 { p.squash += 0.05 }   // the jolt of each blow
        case .read:
            // Reads a line left to right, then jumps back to the next one.
            let line = cycle(1.1)
            p.arms = (1, 1)
            p.look = (line < 0.85 ? min(1, Int(line / 0.85 * 3) - 1) : -1, 1)
        case .search:
            let s = sin(t * 2.2)
            p.arms = (0, 1); p.look = (s > 0.35 ? 1 : (s < -0.35 ? -1 : 0), 0)
        case .web: p.arms = (0, 1); p.look = (Int(Self.noise(Int(t / 0.9), 7) * 3) - 1, -1)
        case .helper: p.look = (1, 0); p.arms = (0, cycle(2.4) < 0.25 ? Int(t * 6) % 2 + 1 : 0)
        case .question: p.tilt = 0.12 * sin(t * 1.4); p.arms = (0, 1)
        case .plan: p.arms = (1, 0); p.look = (0, 1)
        case .ship: p.arms = (0, cycle(1.6) < 0.2 ? 2 : 0); p.look = (1, -1)
        case .install, .download: p.arms = (1, 1); p.look = (1, -1)
        case .delete: p.arms = (0, cycle(1.3) < 0.3 ? 2 : 0); p.look = (1, 0)
        case .git: p.arms = (0, 1); p.look = (1, 0)
        case .connector: p.arms = (1, 1)
        case .tool: p.arms = (0, Int(t * 3) % 2 + 1)
        }
    }

    /// The first moment of a new mood.
    private func react(_ p: inout Pose) {
        guard age < 1.2 else { return }
        if from == .sleeping, mood != .sleeping, age < 1.1 {   // waking up: a long stretch and a yawn
            let k = age / 1.1
            p.lift = 0; p.squash = -0.14 * sin(k * .pi); p.arms = (2, 2); p.look = (0, 0)
            p.eyes = k < 0.55 ? .closed : .half
            p.mouth = k < 0.75 ? .o : nil
            return
        }
        switch mood {
        case .alert where age < 0.55:   // startled
            let k = age / 0.55
            (p.lift, p.squash) = Self.hop(k, height: 0.13)
            p.dx = sin(age * 70) * 0.012 * (1 - k)
            p.mouth = .o
        case .celebrating where age < 0.9:   // one big first jump; floaters flip
            (p.lift, p.squash) = Self.hop(age / 0.9, height: 0.17)
            if sprite.build == .floater { p.tilt = 2 * .pi * Self.easeInOut((age - 0.15) / 0.6) }
            p.arms = (2, 2)
        case .oops where age < 0.6:   // flinch
            let k = age / 0.6
            p.lift = 0; p.squash = 0.16 * (1 - k); p.dx = sin(age * 75) * 0.014 * (1 - k); p.eyes = .dizzy
        case .oops: p.eyes = .dizzy
        case .stopped where age < 0.9:   // skids to a halt, a hand up
            p.tilt = -0.14 * sin(age / 0.9 * .pi); p.eyes = .wide; p.arms = (0, 2); p.look = (0, 0); p.mouth = .o
        case .working where age < 0.4 && from == .thinking:   // "got it!"
            (p.lift, p.squash) = Self.hop(age / 0.4, height: 0.05); p.eyes = .wide
        case .thinking where age < 0.35: p.eyes = .wide
        default: break
        }
    }

    /// Uneven gaps between blinks (2–6 s), and now and then a double blink.
    private func blink(_ p: inout Pose) {
        guard p.eyes == .open || p.eyes == .wide else { return }
        let b = Int(t / 4), d = t - (Double(b) * 4 + Self.noise(b, 5) * 3.2)
        if (0..<0.12).contains(d) || (Self.noise(b, 6) > 0.7 && (0.22..<0.32).contains(d)) { p.eyes = .blink }
    }

    // MARK: Draw

    func draw(_ g: inout GraphicsContext, _ size: CGSize) {
        let s = min(size.width, size.height)
        let ox = (size.width - s) / 2, oy = (size.height - s) / 2
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        let p = pose()
        let cell = 0.78 * s / 16
        let w = Double(sprite.width) * cell, h = Double(sprite.height) * cell
        let feet = CGPoint(x: ox + (0.5 + p.dx) * s, y: oy + (0.86 - p.lift) * s)
        let x0 = feet.x - w / 2, y0 = feet.y - h

        // Ground: a shadow that tightens as the pet rises, and a soft light in the mood colour.
        let k = max(0.35, 1 - p.lift * 5)
        let gw = 0.52 * s * k
        let ground = CGRect(x: ox + (0.5 + p.dx) * s - gw / 2, y: oy + 0.865 * s, width: gw, height: 0.06 * s)
        g.fill(Path(ellipseIn: ground.insetBy(dx: gw * 0.12, dy: 0)), with: .color(.black.opacity(0.3 * k)))
        g.fill(Path(ellipseIn: ground), with: .color(mood.tint.opacity(0.26 * k)))

        if sprite.thruster { drawThruster(&g, at: feet, cell: cell) }

        // Body: squash about the feet, tilt about the feet (floaters about their middle), mirror when walking left.
        var c = g
        let pivot = CGPoint(x: feet.x, y: sprite.build == .floater ? feet.y - h / 2 : feet.y)
        c.translateBy(x: feet.x, y: feet.y)
        c.scaleBy(x: (1 + p.squash * 0.85) * (facingLeft ? -1 : 1), y: 1 - p.squash)
        c.translateBy(x: -feet.x, y: -feet.y)
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: .radians(p.tilt))
        c.translateBy(x: -pivot.x, y: -pivot.y)
        drawBody(&c, x0: x0, y0: y0, cell: cell, pose: p, face: detail)
        if case .working(.helper) = mood, detail { drawBuddy(&g, shoulder: CGPoint(x: feet.x, y: y0 + h * 0.3), cell: cell, s: s) }

        // Props and effects, unmirrored so text and symbols read the right way round.
        guard detail || mood == .alert else { return }
        let side: Double = facingLeft ? -1 : 1
        let hand = CGPoint(x: feet.x + side * (w / 2 - cell * 0.5), y: y0 + Double((sprite.armRow ?? sprite.rows.count / 2) + 1) * cell)
        let head = CGPoint(x: feet.x, y: y0)
        switch mood {
        case .sleeping: drawZs(&g, s: s, P)
        case .thinking: drawThoughts(&g, s: s, P)
        case .working(let a): drawAct(&g, a, s: s, hand: hand, head: head, feet: feet, side: side)
        case .alert: drawAlertBubble(&g, s: s, center: P(0.80, 0.20))
        case .celebrating: drawConfetti(&g, s: s, from: CGPoint(x: head.x, y: head.y + cell))
        case .oops:
            drawSweat(&g, s: s, at: CGPoint(x: feet.x + side * (w / 2 - cell), y: y0 + cell))
            if age < 1.1 { drawDizzy(&g, s: s, around: head) }
        case .stopped:
            if age < 1.3 {
                let pop = Self.spring(age)
                symbol(&g, "hand.raised.fill", at: CGPoint(x: hand.x, y: y0 - 0.06 * s), size: 0.15 * s * pop, tint: mood.tint)
            } else {
                drawDots(&g, s: s, center: P(0.8, 0.24))
            }
        case .idle: break
        }
    }

    /// Cells, arms, legs and face of a sprite at `x0, y0` (top-left) with cells `cell` wide.
    private func drawBody(_ c: inout GraphicsContext, x0: Double, y0: Double, cell: Double, pose p: Pose, face: Bool) {
        func px(_ x: Int, _ y: Int, _ color: Color) {
            // A hair of overlap hides seams between cells.
            c.fill(Path(CGRect(x: x0 + Double(x) * cell, y: y0 + Double(y) * cell, width: cell + 0.4, height: cell + 0.4)), with: .color(color))
        }
        let col = sprite.colors

        // Body: a vertical gradient from top to bottom colour, row by row.
        let n = max(sprite.rows.count - 1, 1)
        for (y, row) in sprite.rows.enumerated() {
            let fill = mix(col.top, col.bottom, Double(y) / Double(n))
            for (x, ch) in row.enumerated() {
                switch ch {
                case "#": px(x, y, fill)
                case "d": px(x, y, col.shade)
                case "s": px(x, y, col.screen)
                case "w": px(x, y, col.accent)
                case "a": px(x, y, mood == .sleeping ? col.shade : mood.tint)
                default: break
                }
            }
        }

        // Arms: two cells each side; raised one row per step.
        if let ay = sprite.armRow {
            let w = sprite.width
            for (x, lift) in [(0, p.arms.0), (1, p.arms.0), (w - 2, p.arms.1), (w - 1, p.arms.1)] { px(x, ay - lift, col.bottom) }
        }

        // Legs: two cells tall; walking lifts alternate legs, tapping lifts one, jumping tucks them all.
        if !sprite.legs.isEmpty {
            let ly = sprite.rows.count
            let ph = Int(t * 8) % 2
            for (i, x) in sprite.legs.enumerated() {
                let down: Bool
                switch p.legs {
                case .stand: down = true
                case .walk: down = i % 2 != ph
                case .tap: down = i != sprite.legs.count - 1 || Int(t * 5) % 2 == 1
                case .tuck: down = false
                }
                px(x, ly, col.shade)
                if down { px(x, ly + 1, col.shade) }
            }
        }

        // Eyes: a few cell patterns per expression; the right eye mirrors the left.
        let cells: [(Int, Int)]
        switch p.eyes {
        case .open: cells = [(0, 0), (0, 1)]
        case .blink: cells = [(0, 1)]
        case .half: cells = [(0, 1), (1, 1)]
        case .closed: cells = [(-1, 1), (0, 1), (1, 1)]
        case .happy: cells = [(-1, 1), (0, 0), (1, 1)]
        case .wide: cells = [(0, 0), (0, 1), (1, 0), (1, 1)]
        case .dizzy: cells = [(-1, 0), (0, 1), (-1, 2)]
        }
        for (i, e) in sprite.eyes.enumerated() {
            let m = i == 1 ? -1 : 1
            for (dx, dy) in cells {
                let x = e.0 + dx * m + p.look.0, y = e.1 + dy + p.look.1
                px(x, y, col.eye)
                if sprite.bigEye { px(x + 1, y, col.eye) }
            }
            guard face else { continue }
            // A glint makes the eyes look alive.
            if p.eyes == .open || p.eyes == .wide {
                let gx = x0 + Double(e.0 + p.look.0 + (sprite.bigEye ? 1 : 0)) * cell + cell * 0.55
                let gy = y0 + Double(e.1 + p.look.1) * cell + cell * 0.12
                c.fill(Path(CGRect(x: gx, y: gy, width: cell * 0.34, height: cell * 0.34)), with: .color(.white.opacity(0.85)))
            }
            if p.blush { px(e.0 - m * (sprite.bigEye ? 2 : 1), e.1 + 2, Color(hex: 0xFF8FA3).opacity(0.6)) }
        }

        // Mouth, only for big expressions.
        if face, let mouth = p.mouth, let first = sprite.eyes.first {
            let last = sprite.eyes.last ?? first
            let mx = (first.0 + last.0 + (sprite.bigEye ? 1 : 0)) / 2, my = max(first.1, last.1) + 2
            let dark = col.screen == .clear ? col.eye : col.eye.opacity(0.9)
            switch mouth {
            case .smile: for (x, y) in [(mx - 1, my), (mx, my + 1), (mx + 1, my + 1), (mx + 2, my)] { px(x, y, dark) }
            case .o: for (x, y) in [(mx, my), (mx + 1, my), (mx, my + 1), (mx + 1, my + 1)] { px(x, y, dark) }
            }
        }
    }

    private func mix(_ a: Color, _ b: Color, _ f: Double) -> Color {
        let x = NSColor(a).usingColorSpace(.sRGB) ?? .white, y = NSColor(b).usingColorSpace(.sRGB) ?? .white
        return Color(red: x.redComponent + (y.redComponent - x.redComponent) * f,
                     green: x.greenComponent + (y.greenComponent - x.greenComponent) * f,
                     blue: x.blueComponent + (y.blueComponent - x.blueComponent) * f)
    }

    // MARK: Parts

    /// An SF Symbol on a dark disc (so it reads over the body), scaled to fit `size`.
    private func symbol(_ g: inout GraphicsContext, _ name: String, at p: CGPoint, size: Double, tint: Color,
                        angle: Double = 0, opacity: Double = 1, backing: Bool = true) {
        guard size > 0.5 else { return }
        var c = g
        c.opacity = opacity
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(angle))
        if backing {
            let r = size * 0.66
            c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(Color(white: 0.09).opacity(0.82)))
        }
        var img = c.resolve(Image(systemName: name))
        img.shading = .color(tint)
        let k = size / max(img.size.width, img.size.height, 1)
        c.draw(img, in: CGRect(x: -img.size.width * k / 2, y: -img.size.height * k / 2, width: img.size.width * k, height: img.size.height * k))
    }

    private func circle(_ c: CGPoint, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }

    /// Acting for each kind of work: a prop in hand, moving the way the job moves.
    private func drawAct(_ g: inout GraphicsContext, _ a: PetAct, s: Double, hand: CGPoint, head: CGPoint, feet: CGPoint, side: Double) {
        let r = 0.17 * s
        func at(_ dx: Double, _ dy: Double, from o: CGPoint = hand) -> CGPoint { CGPoint(x: o.x + side * dx * s, y: o.y + dy * s) }
        switch a {
        case .read:
            symbol(&g, a.symbol, at: at(0, 0.02 + sin(t * 2) * 0.006), size: r, tint: a.tint, angle: -0.08 * side)
            let flip = cycle(2.6)
            if flip > 0.82 {   // a page turns
                let k = (flip - 0.82) / 0.18, pw = r * 0.34 * abs(cos(k * .pi))
                let o = at(0.03 * (k < 0.5 ? 1 : -1), 0.02)
                g.fill(Path(roundedRect: CGRect(x: o.x - pw / 2, y: o.y - r * 0.32, width: max(pw, 0.6), height: r * 0.6), cornerRadius: 1),
                       with: .color(.white.opacity(0.9)))
            }
        case .edit:
            symbol(&g, a.symbol, at: at(cos(t * 13) * 0.012, sin(t * 26) * 0.008), size: r * 0.9, tint: a.tint, angle: -0.5 * side)
            drawCodeLines(&g, s: s, from: at(-0.06, -0.12), tint: a.tint, side: side)
        case .write:
            let page = CGRect(x: hand.x - r * 0.45, y: hand.y - r * 0.55, width: r * 0.9, height: r * 1.1)
            g.fill(Path(roundedRect: page, cornerRadius: r * 0.1), with: .color(Color(white: 0.96)))
            let k = cycle(2.4)
            for i in 0..<3 {
                let len = min(1, max(0, k * 3.4 - Double(i))) * page.width * 0.7
                g.fill(Path(roundedRect: CGRect(x: page.minX + page.width * 0.15, y: page.minY + page.height * (0.25 + Double(i) * 0.22), width: len, height: page.height * 0.07), cornerRadius: 1),
                       with: .color(Color(white: 0.35)))
            }
            let line = min(2, Int(k * 3.4)), done = min(1, max(0, k * 3.4 - Double(line)))
            let tip = CGPoint(x: page.minX + page.width * (0.15 + 0.7 * done), y: page.minY + page.height * (0.2 + Double(line) * 0.22))
            symbol(&g, "pencil", at: CGPoint(x: tip.x + r * 0.15, y: tip.y - r * 0.15), size: r * 0.55, tint: a.tint, backing: false)
        case .terminal:
            drawTerminal(&g, s: s, center: at(-0.02, 0.05), tint: a.tint)
        case .test:
            symbol(&g, a.symbol, at: hand, size: r, tint: a.tint, angle: sin(t * 3) * 0.12)
            for i in 0..<3 {   // bubbles
                let ph = cycle(0.9, Double(i) * 0.3)
                let b = CGPoint(x: hand.x + sin(ph * 6 + Double(i)) * 0.02 * s, y: hand.y - (0.09 + ph * 0.16) * s)
                var c = g; c.opacity = 1 - ph
                c.stroke(circle(b, (0.012 + 0.01 * ph) * s), with: .color(a.tint), lineWidth: 0.008 * s)
            }
            let k = cycle(2)
            if k < 0.55 { symbol(&g, "checkmark.circle.fill", at: at(-0.12, -0.3), size: 0.12 * s * Self.spring(k * 2), tint: Theme.success, backing: false) }
        case .build:
            let k = cycle(0.55)
            let swing = k < 0.7 ? -1.1 * Self.easeInOut(k / 0.7) : -1.1 + 1.45 * min(1, (k - 0.7) / 0.08)
            symbol(&g, a.symbol, at: at(0, -0.02), size: r, tint: a.tint, angle: swing * side)
            if k > 0.76, k < 0.9 {   // sparks where it lands
                let hit = at(0.05, 0.08)
                for i in 0..<4 {
                    let ang = -.pi / 2 + (Double(i) - 1.5) * 0.6
                    var path = Path()
                    path.move(to: CGPoint(x: hit.x + cos(ang) * 0.03 * s, y: hit.y + sin(ang) * 0.03 * s))
                    path.addLine(to: CGPoint(x: hit.x + cos(ang) * 0.07 * s, y: hit.y + sin(ang) * 0.07 * s))
                    g.stroke(path, with: .color(Color(hex: 0xFFE08A)), style: StrokeStyle(lineWidth: 0.012 * s, lineCap: .round))
                }
            }
        case .git:
            let k = cycle(1.2)
            var c = g; c.opacity = 1 - k
            c.stroke(circle(hand, r * (0.6 + 0.5 * k)), with: .color(a.tint), lineWidth: 0.01 * s)
            symbol(&g, a.symbol, at: hand, size: r * 0.85, tint: a.tint, angle: sin(t * 2) * 0.08)
        case .ship:
            let k = cycle(1.6)
            let p = at(k * 0.3, -k * 0.42 + sin(k * .pi) * -0.05)
            for i in 1...3 {   // a short trail
                let q = max(0, k - Double(i) * 0.04)
                var c = g; c.opacity = (1 - k) * 0.5 / Double(i)
                c.fill(circle(at(q * 0.3, -q * 0.42 + sin(q * .pi) * -0.05), 0.01 * s), with: .color(a.tint))
            }
            symbol(&g, a.symbol, at: p, size: r * 0.8, tint: a.tint, angle: -0.35 * side, opacity: 1 - k * k, backing: k < 0.1)
        case .install:
            let k = cycle(1.4)
            let y = hand.y - 0.32 * s * (1 - Self.bounce(k / 0.8))
            symbol(&g, a.symbol, at: CGPoint(x: hand.x, y: y), size: r * 0.9, tint: a.tint, opacity: min(1, (1 - k) * 5))
        case .delete:
            symbol(&g, a.symbol, at: at(0, 0.03), size: r, tint: a.tint, angle: cycle(1.3) > 0.88 ? 0.15 * side : 0)
            let k = cycle(1.3)
            if k < 0.88 {   // a crumpled page tossed in
                let q = k / 0.88
                let ball = CGPoint(x: head.x + (hand.x - head.x) * q, y: head.y + (hand.y - head.y) * q - sin(q * .pi) * 0.18 * s)
                g.fill(circle(ball, 0.022 * s), with: .color(Color(white: 0.92)))
            }
        case .download:
            symbol(&g, a.symbol, at: at(0, sin(t * 3) * 0.008), size: r, tint: a.tint)
            for i in 0..<2 {
                let ph = cycle(0.85, Double(i) * 0.42)
                symbol(&g, "arrow.down", at: at(0, -0.3 + ph * 0.18), size: 0.06 * s, tint: a.tint, opacity: sin(ph * .pi), backing: false)
            }
        case .search:
            let sw = sin(t * 2.2)
            let lens = CGPoint(x: feet.x + side * (0.2 + sw * 0.1) * s, y: hand.y + 0.03 * s)
            symbol(&g, a.symbol, at: lens, size: r, tint: a.tint, angle: -0.2 * side)
            if abs(cos(t * 2.2)) < 0.2 { drawSparkle(&g, at: CGPoint(x: lens.x - 0.03 * s, y: lens.y - 0.05 * s), r: 0.025 * s, color: .white) }
        case .web:
            let globes = ["globe.americas.fill", "globe.europe.africa.fill", "globe.asia.australia.fill"]
            symbol(&g, globes[Int(t / 0.7) % 3], at: hand, size: r, tint: a.tint)
            for i in 0..<2 {   // signal rings
                let ph = cycle(1.2, Double(i) * 0.6)
                var arc = Path()
                arc.addArc(center: hand, radius: r * (0.75 + ph * 0.6), startAngle: .degrees(-140), endAngle: .degrees(-40), clockwise: false)
                var c = g; c.opacity = (1 - ph) * 0.9
                c.stroke(arc, with: .color(a.tint), style: StrokeStyle(lineWidth: 0.01 * s, lineCap: .round))
            }
        case .helper:
            drawDots(&g, s: s, center: at(0.02, -0.2, from: head))
        case .question:
            let q = Text("?").font(.system(size: 0.2 * s, weight: .black, design: .rounded)).foregroundColor(a.tint)
            var c = g
            let p = at(0.16, -0.08 + sin(t * 3) * 0.012, from: head)
            c.fill(circle(p, 0.1 * s), with: .color(Color(white: 0.09).opacity(0.82)))
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(sin(t * 2) * 0.2))
            c.draw(q, at: .zero)
        case .plan:
            symbol(&g, a.symbol, at: hand, size: r, tint: a.tint)
            let k = cycle(2.4)
            for i in 0..<3 where k > Double(i) * 0.25 {
                symbol(&g, "checkmark", at: at(-0.1 - Double(i) * 0.07, -0.22), size: 0.05 * s * Self.spring(k * 2.4 - Double(i) * 0.6),
                       tint: Theme.success, backing: false)
            }
        case .connector:
            let push = abs(sin(t * 3))
            symbol(&g, a.symbol, at: at(push * 0.03, 0), size: r, tint: a.tint)
            if push < 0.15 { drawSparkle(&g, at: at(-0.08, 0), r: 0.03 * s, color: a.tint) }
        case .tool:
            symbol(&g, a.symbol, at: hand, size: r, tint: a.tint, angle: sin(t * 6) * 0.5)
        }
    }

    private func drawTerminal(_ g: inout GraphicsContext, s: Double, center c: CGPoint, tint: Color) {
        let rect = CGRect(x: c.x - 0.13 * s, y: c.y - 0.085 * s, width: 0.26 * s, height: 0.17 * s)
        let shape = Path(roundedRect: rect, cornerRadius: 0.025 * s)
        g.fill(shape, with: .color(Color(hex: 0x0D1117).opacity(0.95)))
        g.stroke(shape, with: .color(tint.opacity(0.8)), lineWidth: 0.008 * s)
        let u = 0.022 * s
        var chev = Path()
        chev.move(to: CGPoint(x: rect.minX + u, y: rect.midY - u * 0.8))
        chev.addLine(to: CGPoint(x: rect.minX + u * 1.8, y: rect.midY))
        chev.addLine(to: CGPoint(x: rect.minX + u, y: rect.midY + u * 0.8))
        g.stroke(chev, with: .color(tint), style: StrokeStyle(lineWidth: 0.011 * s, lineCap: .round, lineJoin: .round))
        // Keys typed one by one, then the line runs and clears.
        let typed = min(5, Int(cycle(1.8) * 6))
        for i in 0..<typed {
            g.fill(Path(CGRect(x: rect.minX + u * (2.5 + Double(i) * 1.2), y: rect.midY - u * 0.45, width: u * 0.9, height: u * 0.9)),
                   with: .color(tint.opacity(0.6)))
        }
        if Int(t * 3) % 2 == 0 {
            g.fill(Path(CGRect(x: rect.minX + u * (2.5 + Double(typed) * 1.2), y: rect.midY - u * 0.55, width: u * 0.55, height: u * 1.1)), with: .color(tint))
        }
        for i in 0..<3 {   // bits floating up off the screen
            let ph = cycle(1.25, Double(i) * 0.42)
            var cc = g; cc.opacity = sin(ph * .pi) * 0.8
            cc.draw(Text(i == 1 ? "0" : "1").font(.system(size: 0.055 * s, weight: .bold, design: .monospaced)).foregroundColor(tint),
                    at: CGPoint(x: rect.minX + rect.width * (0.25 + 0.25 * Double(i)), y: rect.minY - ph * 0.12 * s))
        }
    }

    private func drawCodeLines(_ g: inout GraphicsContext, s: Double, from o: CGPoint, tint: Color, side: Double) {
        for i in 0..<3 {
            let ph = cycle(1.4, Double(i) * 0.47)
            let len = (0.04 + 0.04 * Self.noise(i, 9)) * s
            let x = o.x - side * Double(i % 2) * 0.03 * s
            var c = g; c.opacity = sin(ph * .pi) * 0.85
            c.fill(Path(roundedRect: CGRect(x: side > 0 ? x - len : x, y: o.y - ph * 0.13 * s, width: len, height: 0.014 * s), cornerRadius: 0.007 * s),
                   with: .color(tint))
        }
    }

    /// A smaller copy of the pet hopping on its shoulder: the helper agent at work.
    private func drawBuddy(_ g: inout GraphicsContext, shoulder: CGPoint, cell: Double, s: Double) {
        let c2 = cell * 0.38
        let (lift, _) = Self.hop(cycle(0.9, 0.3), height: 0.04)
        let bf = CGPoint(x: shoulder.x + (facingLeft ? -1 : 1) * 0.35 * s, y: shoulder.y - lift * s)
        var buddy = Pose(); buddy.arms = (Int(t * 9) % 2, Int(t * 9 + 1) % 2); buddy.legs = lift > 0.01 ? .tuck : .stand
        var c = g
        drawBody(&c, x0: bf.x - Double(sprite.width) * c2 / 2, y0: bf.y - Double(sprite.height) * c2, cell: c2, pose: buddy, face: false)
    }

    private func drawThruster(_ g: inout GraphicsContext, at feet: CGPoint, cell: Double) {
        let flicker = 0.75 + 0.25 * sin(t * 31) * sin(t * 17)
        let len = cell * (mood == .sleeping ? 1.3 : 2.6) * flicker * (walking ? 1.4 : 1)
        var f = Path()
        f.move(to: CGPoint(x: feet.x - cell * 1.6, y: feet.y))
        f.addQuadCurve(to: CGPoint(x: feet.x, y: feet.y + len), control: CGPoint(x: feet.x - cell, y: feet.y + len * 0.6))
        f.addQuadCurve(to: CGPoint(x: feet.x + cell * 1.6, y: feet.y), control: CGPoint(x: feet.x + cell, y: feet.y + len * 0.6))
        f.closeSubpath()
        g.fill(f, with: .linearGradient(Gradient(colors: [.white, Color(hex: 0x7FE7FF), Color(hex: 0x4F8CFF).opacity(0)]),
                                        startPoint: feet, endPoint: CGPoint(x: feet.x, y: feet.y + len)))
    }

    private func drawZs(_ g: inout GraphicsContext, s: Double, _ P: (Double, Double) -> CGPoint) {
        for i in 0..<3 {
            let ph = (t * 0.32 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            var c = g
            c.opacity = sin(ph * .pi) * 0.85
            let text = Text("z").font(.system(size: (0.10 + ph * 0.07) * s, weight: .heavy, design: .rounded)).foregroundColor(Color(hex: 0xBFD4FF))
            // Each z drifts up and sways a little, like smoke.
            c.draw(text, at: P(0.72 + ph * 0.16 + sin(ph * 6 + Double(i)) * 0.02, 0.34 - ph * 0.26))
        }
    }

    /// A thought cloud with three dots that rise in turn, as in a chat app.
    private func drawThoughts(_ g: inout GraphicsContext, s: Double, _ P: (Double, Double) -> CGPoint) {
        let white = Color.white.opacity(0.92)
        g.fill(circle(P(0.73, 0.34), 0.016 * s), with: .color(white))
        g.fill(circle(P(0.78, 0.26), 0.024 * s), with: .color(white))
        let c = P(0.84, 0.13)
        var cloud = Path()
        for (dx, dy, r) in [(-0.06, 0.01, 0.05), (0.0, -0.015, 0.06), (0.06, 0.01, 0.05), (0.0, 0.03, 0.045)] {
            cloud.addPath(circle(CGPoint(x: c.x + dx * s, y: c.y + dy * s), r * s))
        }
        g.fill(cloud, with: .color(white))
        for i in 0..<3 {
            let bob = max(0, sin(t * 6 - Double(i) * 0.8)) * 0.014 * s
            g.fill(circle(CGPoint(x: c.x + Double(i - 1) * 0.04 * s, y: c.y + 0.005 * s - bob), 0.012 * s), with: .color(Color(white: 0.25)))
        }
    }

    private func drawDots(_ g: inout GraphicsContext, s: Double, center c: CGPoint) {
        let rect = CGRect(x: c.x - 0.09 * s, y: c.y - 0.045 * s, width: 0.18 * s, height: 0.09 * s)
        g.fill(Path(roundedRect: rect, cornerRadius: 0.045 * s), with: .color(Color(white: 0.92).opacity(0.9)))
        for i in 0..<3 {
            var cc = g; cc.opacity = 0.35 + 0.65 * max(0, sin(t * 5 - Double(i) * 0.9))
            cc.fill(circle(CGPoint(x: c.x + Double(i - 1) * 0.045 * s, y: c.y), 0.012 * s), with: .color(Color(white: 0.2)))
        }
    }

    private func drawAlertBubble(_ g: inout GraphicsContext, s: Double, center c: CGPoint) {
        // Pops in with a spring, then pulses.
        let pulse = age < 0.7 ? Self.spring(age) : 1 + sin(t * 7) * 0.07
        let r = 0.11 * s * pulse
        guard r > 0.5 else { return }
        var bubble = circle(c, r)
        bubble.move(to: CGPoint(x: c.x - r * 0.55, y: c.y + r * 0.7))
        bubble.addLine(to: CGPoint(x: c.x - r * 0.95, y: c.y + r * 1.35))
        bubble.addLine(to: CGPoint(x: c.x - r * 0.05, y: c.y + r * 0.95))
        g.fill(bubble, with: .color(Theme.warning))
        let mark = Text("!").font(.system(size: r * 1.45, weight: .black, design: .rounded)).foregroundColor(.black)
        g.draw(mark, at: c)
    }

    /// Bursts of confetti thrown up from the head that fall back under gravity.
    private func drawConfetti(_ g: inout GraphicsContext, s: Double, from o: CGPoint) {
        let colors: [Color] = [Color(hex: 0xFFD166), Theme.claudeLight, Theme.success, Color(hex: 0x7AB8FF), Color(hex: 0xFF8FB1)]
        let period = 1.8
        let tau = age < period ? age : t.truncatingRemainder(dividingBy: period)
        let burst = age < period ? -1 : Int(t / period)
        guard tau < 1.5 else { return }
        for i in 0..<14 {
            let a = -Double.pi / 2 + (Self.noise(i, burst &* 31 &+ 7) - 0.5) * 2.4
            let v = (0.55 + Self.noise(i, burst &* 31 &+ 8) * 0.5) * s
            let p = CGPoint(x: o.x + cos(a) * v * tau, y: o.y + sin(a) * v * tau + 0.9 * s * tau * tau)
            let r = (0.016 + Self.noise(i, 11) * 0.012) * s
            var c = g
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(tau * 9 + Double(i)))
            c.opacity = max(0, 1 - tau / 1.5)
            let rect = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
            let shape = i % 3 == 0 ? SparkShape(pinch: 0.22).path(in: rect) : (i % 3 == 1 ? Path(CGRect(x: -r, y: -r * 0.45, width: r * 2, height: r * 0.9)) : Path(ellipseIn: rect.insetBy(dx: r * 0.3, dy: r * 0.3)))
            c.fill(shape, with: .color(colors[i % colors.count]))
        }
    }

    private func drawDizzy(_ g: inout GraphicsContext, s: Double, around head: CGPoint) {
        for i in 0..<3 {
            let a = t * 6 + Double(i) * 2 * .pi / 3
            let p = CGPoint(x: head.x + cos(a) * 0.16 * s, y: head.y - 0.03 * s + sin(a) * 0.04 * s)
            drawSparkle(&g, at: p, r: 0.028 * s, color: Color(hex: 0xFFD166))
        }
    }

    private func drawSparkle(_ g: inout GraphicsContext, at p: CGPoint, r: Double, color: Color) {
        g.fill(SparkShape(pinch: 0.22).path(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
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
        let host = NSHostingView(rootView: MascotPanelView(harness: harness, state: state))
        host.sizingOptions = []
        panel.contentView = host
        pos = .zero
        pos = notchHidden
        place()
        panel.sharingType = Settings.general.value.showNotchInScreenshots ? .readOnly : .none
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
        // Bubbles show project names and agent messages: follow the screenshot setting live, as the notch panels do.
        let sharing: NSWindow.SharingType = Settings.general.value.showNotchInScreenshots ? .readOnly : .none
        if panel.sharingType != sharing { panel.sharingType = sharing }
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
