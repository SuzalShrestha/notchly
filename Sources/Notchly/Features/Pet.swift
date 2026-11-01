import SwiftUI

// MARK: - Claude pet
//
// A small vector companion that mirrors what Claude Code is doing. It is drawn in one Canvas
// (a single layer, no view tree per limb), and its TimelineView pauses whenever the pet is
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

    var accessibilityLabel: String { "Claude pet: \(title)" }

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

    fileprivate var isWorking: Bool { if case .working = self { return true } else { return false } }
}

struct PetView: View {
    var mood: PetMood
    var size: CGFloat = 64
    var animated = true

    var body: some View {
        let still = !animated || Motion.reduceMotion
        // Tiny pets in the closed notch tick slower; nobody can see 30 fps at 22 pt.
        let rate: Double = size < 34 ? 1.0 / 20 : 1.0 / 30
        TimelineView(.animation(minimumInterval: rate, paused: still)) { ctx in
            let t = still ? 0.6 : ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, sz in PetPainter(mood: mood, t: t, detail: size >= 34).draw(&g, sz) }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(mood.accessibilityLabel)
    }
}

/// Pet whose mood comes from the live agent sessions. Mood changes that depend on time
/// (celebrating fades to idle, idle dozes off) are resolved per frame from the timeline date.
struct AgentPet: View {
    var size: CGFloat = 64
    var body: some View {
        let store = AgentStore.shared
        if Motion.reduceMotion {
            PetView(mood: store.petMood(at: Date()), size: size, animated: false)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                PetView(mood: store.petMood(at: ctx.date), size: size)
            }
        }
    }
}

// MARK: - Painter

private struct PetPainter {
    let mood: PetMood
    let t: Double
    let detail: Bool

    // Palette (Display P3 friendly sRGB values).
    private let body = Color(hex: 0xDE7C5A)
    private let bodyTop = Color(hex: 0xEC977A)
    private let bodyShade = Color(hex: 0xBF5E3E)
    private let belly = Color(hex: 0xF6C3A9)
    private let ink = Color(hex: 0x2A1712)
    private let cheek = Color(hex: 0xF59A8C)

    func draw(_ g: inout GraphicsContext, _ size: CGSize) {
        let s = min(size.width, size.height)
        let ox = (size.width - s) / 2, oy = (size.height - s) / 2
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        func R(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s) }

        // Motion: hop (vertical lift), squash (breathing), sway (horizontal).
        var hop = 0.0, squash = 1.0, sway = 0.0
        switch mood {
        case .sleeping: squash = 1 + sin(t * 1.3) * 0.035
        case .idle: hop = (sin(t * 2) + 1) * 0.008; squash = 1 + sin(t * 2) * 0.015
        case .thinking: hop = (sin(t * 2.4) + 1) * 0.01; sway = sin(t * 1.2) * 0.008
        case .working: hop = abs(sin(t * 6)) * 0.022; squash = 1 - abs(sin(t * 6)) * 0.02
        case .alert: hop = max(0, sin(t * 7)) * 0.06; squash = 1 + max(0, -sin(t * 7)) * 0.03
        case .celebrating: hop = abs(sin(t * 6.5)) * 0.085
        case .oops: sway = sin(t * 18) * 0.006 * (1 + sin(t * 1.5)); squash = 0.97
        }

        let bw = 0.60 * (2 - squash), bh = 0.50 * squash
        let bottom = 0.86 - hop
        let bx = 0.5 - bw / 2 + sway, by = bottom - bh
        let cx = 0.5 + sway

        // Ground light: a soft glow that shrinks while the pet is in the air.
        let glowW = 0.52 * (1 - hop * 3.5)
        g.fill(Path(ellipseIn: R(0.5 - glowW / 2, 0.875, glowW, 0.06)), with: .color(mood.tint.opacity(0.28)))

        // Arms sit behind the body; only the ends that stick out are visible.
        let (la, ra) = armAngles()
        let armL = P(bx + 0.06, by + bh * 0.58), armR = P(bx + bw - 0.06, by + bh * 0.58)
        for (pivot, a) in [(armL, la), (armR, ra)] {
            var arm = Path()
            arm.move(to: pivot)
            arm.addLine(to: CGPoint(x: pivot.x + cos(a) * 0.17 * s, y: pivot.y + sin(a) * 0.17 * s))
            g.stroke(arm, with: .color(bodyShade), style: StrokeStyle(lineWidth: 0.085 * s, lineCap: .round))
        }

        // Feet.
        for fx in [cx - 0.13, cx + 0.07] {
            g.fill(Path(roundedRect: R(fx, bottom - 0.035, 0.11, 0.07), cornerRadius: 0.035 * s), with: .color(bodyShade))
        }

        // Antenna with a spark on top.
        let top = P(cx, by + 0.01)
        let tip = P(cx + 0.06 + sin(t * 2.2) * (mood == .sleeping ? 0 : 0.012), by - 0.12)
        var stalk = Path()
        stalk.move(to: top)
        stalk.addQuadCurve(to: tip, control: P(cx - 0.02, by - 0.06))
        g.stroke(stalk, with: .color(bodyShade), style: StrokeStyle(lineWidth: 0.03 * s, lineCap: .round))
        drawSpark(&g, at: tip, s: s)

        // Body.
        let bodyRect = R(bx, by, bw, bh)
        let bodyPath = Path(roundedRect: bodyRect, cornerRadius: 0.24 * s, style: .continuous)
        g.fill(bodyPath, with: .linearGradient(Gradient(colors: [bodyTop, body, bodyShade]),
                                               startPoint: CGPoint(x: bodyRect.midX, y: bodyRect.minY),
                                               endPoint: CGPoint(x: bodyRect.midX, y: bodyRect.maxY)))
        // Belly highlight and a rim light along the top edge.
        g.fill(Path(ellipseIn: R(cx - 0.17, by + bh * 0.55, 0.34, bh * 0.38)), with: .color(belly.opacity(0.38)))
        var rim = Path()
        rim.addArc(center: P(cx, by + 0.24), radius: 0.215 * s, startAngle: .degrees(205), endAngle: .degrees(255), clockwise: false)
        g.stroke(rim, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 0.018 * s, lineCap: .round))

        // Face.
        let eyeY = by + bh * 0.40
        drawEyes(&g, s: s, left: P(cx - 0.10, eyeY), right: P(cx + 0.10, eyeY))
        let cheekA = mood == .celebrating || mood == .alert ? 0.85 : 0.55
        for x in [cx - 0.175, cx + 0.105] {
            g.fill(Path(ellipseIn: R(x, eyeY + 0.045, 0.07, 0.04)), with: .color(cheek.opacity(cheekA)))
        }
        drawMouth(&g, s: s, at: P(cx, eyeY + 0.085))

        // Props and effects.
        guard detail || mood == .alert else { return }
        switch mood {
        case .sleeping: drawZs(&g, s: s, P)
        case .thinking: drawThoughts(&g, s: s, P)
        case .working(let k): drawProp(&g, kind: k, s: s, center: P(0.82, 0.76 - hop * 0.5))
        case .alert: drawAlertBubble(&g, s: s, center: P(0.80, 0.20))
        case .celebrating: drawConfetti(&g, s: s, P)
        case .oops: drawSweat(&g, s: s, at: P(cx + 0.22, by + 0.06))
        case .idle: break
        }
    }

    // MARK: Parts

    /// Arm angles in radians (0 = right, π/2 = down in view space).
    private func armAngles() -> (Double, Double) {
        switch mood {
        case .alert: return (.pi * 0.72, -.pi * 0.38 + sin(t * 11) * 0.38)          // waving right arm
        case .celebrating: return (-.pi * 0.72 + sin(t * 9) * 0.15, -.pi * 0.28 - sin(t * 9) * 0.15)
        case .thinking: return (.pi * 0.70, -.pi * 0.78)                                // hand to chin
        case .working(let k):
            switch k {
            case .command, .edit, .write: // typing
                return (.pi * 0.62 + sin(t * 17) * 0.22, .pi * 0.38 - sin(t * 17 + 1.4) * 0.22)
            default: return (.pi * 0.66 + sin(t * 3) * 0.06, .pi * 0.30 + sin(t * 3) * 0.08)
            }
        case .oops: return (.pi * 0.80, .pi * 0.20)
        case .sleeping: return (.pi * 0.68, .pi * 0.32)
        case .idle: return (.pi * 0.66, .pi * 0.34 + sin(t * 1.4) * 0.05)
        }
    }

    private func drawSpark(_ g: inout GraphicsContext, at p: CGPoint, s: Double) {
        let pulse: Double
        switch mood {
        case .alert: pulse = 1 + sin(t * 8) * 0.18
        case .working, .thinking: pulse = 1 + sin(t * 4) * 0.1
        case .celebrating: pulse = 1.15
        default: pulse = 1
        }
        let r = 0.06 * s * pulse
        let color: Color = mood == .sleeping ? Color(hex: 0xC9A88E) : (mood == .alert ? Theme.warning : Color(hex: 0xFFD7A6))
        if mood != .sleeping {
            g.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.6, y: p.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                   with: .radialGradient(Gradient(colors: [color.opacity(0.45), .clear]), center: p, startRadius: 0, endRadius: r * 1.6))
        }
        var c = g
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(mood.isWorking || mood == .thinking ? t * 1.6 : 0))
        c.fill(SparkShape().path(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(color))
    }

    private func drawEyes(_ g: inout GraphicsContext, s: Double, left: CGPoint, right: CGPoint) {
        let lw = 0.024 * s
        func arc(_ c: CGPoint, up: Bool) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: c.x - 0.04 * s, y: c.y))
            p.addQuadCurve(to: CGPoint(x: c.x + 0.04 * s, y: c.y), control: CGPoint(x: c.x, y: c.y + (up ? -0.045 : 0.035) * s))
            return p
        }
        switch mood {
        case .sleeping:
            for c in [left, right] { g.stroke(arc(c, up: false), with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round)) }
            return
        case .celebrating:
            for c in [left, right] { g.stroke(arc(c, up: true), with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round)) }
            return
        case .oops:
            // > <
            for (c, dir) in [(left, 1.0), (right, -1.0)] {
                var p = Path()
                p.move(to: CGPoint(x: c.x - dir * 0.035 * s, y: c.y - 0.03 * s))
                p.addLine(to: CGPoint(x: c.x + dir * 0.025 * s, y: c.y))
                p.addLine(to: CGPoint(x: c.x - dir * 0.035 * s, y: c.y + 0.03 * s))
                g.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            }
            return
        default: break
        }

        // Open eyes, with blink and gaze.
        let big = mood == .alert
        let w = (big ? 0.10 : 0.085) * s
        var h = (big ? 0.13 : 0.11) * s
        let cycle = t.truncatingRemainder(dividingBy: 3.8)
        if cycle < 0.13 { h *= 0.12 }
        var look = CGPoint.zero
        switch mood {
        case .thinking: look = CGPoint(x: (0.012 + sin(t * 0.9) * 0.008) * s, y: -0.02 * s)
        case .working(let k):
            switch k {
            case .read, .search, .web: look = CGPoint(x: sin(t * 2.4) * 0.016 * s, y: 0.006 * s)
            default: look = CGPoint(x: 0, y: 0.014 * s)
            }
        case .idle: look = CGPoint(x: sin(t * 0.55) * 0.012 * s, y: 0)
        default: break
        }
        for c in [left, right] {
            let e = CGRect(x: c.x - w / 2 + look.x, y: c.y - h / 2 + look.y, width: w, height: h)
            g.fill(Path(ellipseIn: e), with: .color(ink))
            if h > w * 0.5 {
                let gr = 0.022 * s
                g.fill(Path(ellipseIn: CGRect(x: e.minX + w * 0.22, y: e.minY + h * 0.16, width: gr, height: gr)), with: .color(.white.opacity(0.95)))
            }
        }
        if big {
            for (c, dir) in [(left, -1.0), (right, 1.0)] {
                var brow = Path()
                brow.move(to: CGPoint(x: c.x - 0.035 * s, y: c.y - 0.095 * s + dir * 0.008 * s))
                brow.addLine(to: CGPoint(x: c.x + 0.035 * s, y: c.y - 0.095 * s - dir * 0.008 * s))
                g.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: 0.018 * s, lineCap: .round))
            }
        }
    }

    private func drawMouth(_ g: inout GraphicsContext, s: Double, at m: CGPoint) {
        let lw = 0.02 * s
        var p = Path()
        switch mood {
        case .celebrating:
            p.move(to: CGPoint(x: m.x - 0.05 * s, y: m.y - 0.01 * s))
            p.addQuadCurve(to: CGPoint(x: m.x + 0.05 * s, y: m.y - 0.01 * s), control: CGPoint(x: m.x, y: m.y + 0.08 * s))
            p.closeSubpath()
            g.fill(p, with: .color(ink))
            g.fill(Path(ellipseIn: CGRect(x: m.x - 0.02 * s, y: m.y + 0.012 * s, width: 0.04 * s, height: 0.022 * s)), with: .color(cheek))
        case .alert, .sleeping:
            let r = (mood == .alert ? 0.034 : 0.022) * s
            g.fill(Path(ellipseIn: CGRect(x: m.x - r / 2, y: m.y - r / 2, width: r, height: r * 1.15)), with: .color(ink))
        case .working:
            p.move(to: CGPoint(x: m.x - 0.022 * s, y: m.y))
            p.addLine(to: CGPoint(x: m.x + 0.022 * s, y: m.y))
            g.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        case .thinking:
            p.move(to: CGPoint(x: m.x - 0.012 * s, y: m.y + 0.004 * s))
            p.addQuadCurve(to: CGPoint(x: m.x + 0.03 * s, y: m.y - 0.006 * s), control: CGPoint(x: m.x + 0.01 * s, y: m.y + 0.012 * s))
            g.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        case .oops:
            p.move(to: CGPoint(x: m.x - 0.04 * s, y: m.y + 0.008 * s))
            p.addCurve(to: CGPoint(x: m.x + 0.04 * s, y: m.y + 0.008 * s),
                       control1: CGPoint(x: m.x - 0.015 * s, y: m.y - 0.022 * s), control2: CGPoint(x: m.x + 0.015 * s, y: m.y + 0.036 * s))
            g.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        case .idle:
            p.move(to: CGPoint(x: m.x - 0.035 * s, y: m.y - 0.006 * s))
            p.addQuadCurve(to: CGPoint(x: m.x + 0.035 * s, y: m.y - 0.006 * s), control: CGPoint(x: m.x, y: m.y + 0.03 * s))
            g.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }
    }

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
