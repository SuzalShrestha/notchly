import SwiftUI

// Flat 2D illustrations for onboarding, drawn as vectors in a Canvas (no image assets).
// Each loops on a TimelineView that stops under Reduce Motion, where a representative
// still frame is shown instead.

private func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

private func backOut(_ x: Double) -> Double {
    let t = min(max(x, 0), 1), c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
}

private struct Looping<Content: View>: View {
    var stillTime: Double
    @ViewBuilder var content: (Double) -> Content
    var body: some View {
        let still = Motion.reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { ctx in
            content(still ? stillTime : ctx.date.timeIntervalSinceReferenceDate)
        }
    }
}

private enum Palette {
    static let sunsetTop = Color(hex: 0xF7B087)
    static let sunsetMid = Color(hex: 0xD9719F)
    static let sunsetLow = Color(hex: 0x5B3FA6)
    static let hillFar = Color(hex: 0x7A4A9E)
    static let hillNear = Color(hex: 0x3E2B70)
    static let sun = Color(hex: 0xFFE0B0)
    static let lid = Color(hex: 0x1B1B21)
    static let deckTop = Color(hex: 0xD9DBE1)
    static let deckLow = Color(hex: 0x8E9199)
    static let leafA = Color(hex: 0x5FA877)
    static let leafB = Color(hex: 0x4C8F63)
    static let leafC = Color(hex: 0x86C795)
    static let pot = Color(hex: 0xC8714F)
    static let potRim = Color(hex: 0xDE8A66)
    static let mug = Color(hex: 0xEFE9DF)
}

/// Draws the wallpaper (sunset, sun, hills) clipped to `rect`.
private func drawWallpaper(_ g: inout GraphicsContext, _ rect: CGRect, radius: CGFloat) {
    let clip = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    var c = g
    c.clip(to: clip)
    c.fill(clip, with: .linearGradient(Gradient(colors: [Palette.sunsetTop, Palette.sunsetMid, Palette.sunsetLow]),
                                        startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
    let sr = rect.height * 0.17
    let sun = CGPoint(x: rect.midX + rect.width * 0.2, y: rect.maxY - rect.height * 0.36)
    c.fill(Path(ellipseIn: CGRect(x: sun.x - sr * 2, y: sun.y - sr * 2, width: sr * 4, height: sr * 4)),
           with: .radialGradient(Gradient(colors: [Palette.sun.opacity(0.5), .clear]), center: sun, startRadius: 0, endRadius: sr * 2))
    c.fill(Path(ellipseIn: CGRect(x: sun.x - sr, y: sun.y - sr, width: sr * 2, height: sr * 2)), with: .color(Palette.sun))
    var far = Path()
    far.move(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.24))
    far.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.16),
                     control: CGPoint(x: rect.midX - rect.width * 0.12, y: rect.maxY - rect.height * 0.58))
    far.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); far.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); far.closeSubpath()
    c.fill(far, with: .color(Palette.hillFar))
    var near = Path()
    near.move(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.08))
    near.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.30),
                      control: CGPoint(x: rect.midX + rect.width * 0.22, y: rect.maxY + rect.height * 0.02))
    near.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); near.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); near.closeSubpath()
    c.fill(near, with: .color(Palette.hillNear))
}

/// A notch opened by `open` (0…1) inside `display`, with miniature widgets once it is mostly open.
private func drawNotch(_ g: inout GraphicsContext, display: CGRect, closed: CGSize, opened: CGSize, open: Double) {
    let w = closed.width + (opened.width - closed.width) * open
    let h = closed.height + (opened.height - closed.height) * open
    let ear = 3 + 7 * open
    let r = CGRect(x: display.midX - w / 2 - ear, y: display.minY, width: w + ear * 2, height: h)
    g.fill(NotchShape(bottomRadius: 4 + 16 * open, earRadius: ear).path(in: r), with: .color(.black))

    let a = smooth(0.55, 1, open)
    guard a > 0 else { return }
    var c = g
    c.opacity = a
    let inner = CGRect(x: r.minX + ear + 12, y: r.minY + h * 0.26, width: w - 24, height: h * 0.62)
    // Tab dots along the top.
    for i in 0..<5 {
        let d = CGRect(x: inner.minX + CGFloat(i) * 11, y: r.minY + h * 0.08, width: 6, height: 6)
        c.fill(Path(ellipseIn: d), with: .color(.white.opacity(i == 0 ? 0.9 : 0.3)))
    }
    // Music card.
    let cardW = inner.width * 0.56
    let card = CGRect(x: inner.minX, y: inner.minY, width: cardW, height: inner.height)
    c.fill(Path(roundedRect: card, cornerRadius: 9, style: .continuous), with: .color(Color(white: 0.12)))
    let art = CGRect(x: card.minX + 7, y: card.minY + 7, width: card.height - 14, height: card.height - 14)
    c.fill(Path(roundedRect: art, cornerRadius: 6, style: .continuous),
           with: .linearGradient(Gradient(colors: [Color(hex: 0xFF8FB1), Color(hex: 0xFFB45E)]), startPoint: art.origin, endPoint: CGPoint(x: art.maxX, y: art.maxY)))
    let tx = art.maxX + 7, tw = card.maxX - tx - 8
    c.fill(Path(roundedRect: CGRect(x: tx, y: card.minY + card.height * 0.24, width: tw * 0.8, height: 5), cornerRadius: 2.5), with: .color(.white.opacity(0.85)))
    c.fill(Path(roundedRect: CGRect(x: tx, y: card.minY + card.height * 0.44, width: tw * 0.5, height: 4), cornerRadius: 2), with: .color(.white.opacity(0.4)))
    c.fill(Path(roundedRect: CGRect(x: tx, y: card.minY + card.height * 0.70, width: tw, height: 3), cornerRadius: 1.5), with: .color(.white.opacity(0.18)))
    c.fill(Path(roundedRect: CGRect(x: tx, y: card.minY + card.height * 0.70, width: tw * 0.62, height: 3), cornerRadius: 1.5), with: .color(.white.opacity(0.8)))
    // Ring card.
    let ring = CGRect(x: card.maxX + 6, y: inner.minY, width: inner.maxX - card.maxX - 6, height: inner.height)
    c.fill(Path(roundedRect: ring, cornerRadius: 9, style: .continuous), with: .color(Color(white: 0.12)))
    let rc = CGPoint(x: ring.midX, y: ring.midY), rr = min(ring.width, ring.height) * 0.3
    var track = Path(); track.addArc(center: rc, radius: rr, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
    c.stroke(track, with: .color(.white.opacity(0.14)), lineWidth: 3.5)
    var prog = Path(); prog.addArc(center: rc, radius: rr, startAngle: .degrees(-90), endAngle: .degrees(-90 + 260 * open), clockwise: false)
    c.stroke(prog, with: .color(Theme.success), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
}

// MARK: - Desk scene (welcome)

struct DeskIllustration: View {
    var body: some View {
        Looping(stillTime: 2.2) { t in
            Canvas { g, size in draw(&g, size, t) }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let cx = size.width / 2
        let screen = CGRect(x: cx - 170, y: 14, width: 340, height: 206)
        let ground = screen.maxY + 13
        let loop = t.truncatingRemainder(dividingBy: 5.2)
        let open = Motion.reduceMotion ? 1 : backOut(smooth(0.6, 1.25, loop)) * (1 - smooth(3.9, 4.5, loop))

        // Desk shadow.
        g.fill(Path(ellipseIn: CGRect(x: cx - 270, y: ground - 8, width: 540, height: 24)), with: .color(.black.opacity(0.4)))

        // Plant.
        let px = cx - 250
        for i in 0..<5 {
            let angle = -90.0 + Double(i - 2) * 26 + sin(t * 1.1 + Double(i)) * 3
            var c = g
            c.translateBy(x: px, y: ground - 42)
            c.rotate(by: .degrees(angle))
            let len = i == 2 ? 58.0 : 46.0
            c.fill(Path(ellipseIn: CGRect(x: 0, y: -8, width: len, height: 16)), with: .color([Palette.leafA, Palette.leafB, Palette.leafC][i % 3]))
            var vein = Path(); vein.move(to: CGPoint(x: 4, y: 0)); vein.addLine(to: CGPoint(x: len - 8, y: 0))
            c.stroke(vein, with: .color(.white.opacity(0.18)), lineWidth: 1)
        }
        var pot = Path()
        pot.move(to: CGPoint(x: px - 21, y: ground - 38)); pot.addLine(to: CGPoint(x: px + 21, y: ground - 38))
        pot.addLine(to: CGPoint(x: px + 15, y: ground)); pot.addLine(to: CGPoint(x: px - 15, y: ground)); pot.closeSubpath()
        g.fill(pot, with: .color(Palette.pot))
        g.fill(Path(roundedRect: CGRect(x: px - 25, y: ground - 46, width: 50, height: 9), cornerRadius: 3), with: .color(Palette.potRim))

        // Mug with steam.
        let mx = cx + 252
        for i in 0..<2 {
            let ph = (t * 0.45 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
            let x0: CGFloat = mx - 6 + CGFloat(i) * 11, y0: CGFloat = ground - 44 - CGFloat(ph) * 22
            var steam = Path()
            steam.move(to: CGPoint(x: x0, y: y0))
            steam.addCurve(to: CGPoint(x: x0, y: y0 - 22), control1: CGPoint(x: x0 + 7, y: y0 - 7), control2: CGPoint(x: x0 - 7, y: y0 - 15))
            var c = g
            c.opacity = sin(ph * .pi) * 0.55
            c.stroke(steam, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        var handle = Path(); handle.addArc(center: CGPoint(x: mx + 18, y: ground - 20), radius: 9, startAngle: .degrees(-80), endAngle: .degrees(80), clockwise: false)
        g.stroke(handle, with: .color(Palette.mug), lineWidth: 5)
        g.fill(Path(roundedRect: CGRect(x: mx - 18, y: ground - 38, width: 36, height: 38), cornerRadius: 8, style: .continuous), with: .color(Palette.mug))
        g.fill(Path(roundedRect: CGRect(x: mx - 18, y: ground - 26, width: 36, height: 7), cornerRadius: 0), with: .color(Theme.claude.opacity(0.8)))

        // Laptop lid, display, notch.
        let lid = Path(roundedRect: screen, cornerRadius: 16, style: .continuous)
        g.fill(lid, with: .color(Palette.lid))
        g.stroke(lid, with: .color(.white.opacity(0.1)), lineWidth: 1)
        let display = screen.insetBy(dx: 9, dy: 9)
        drawWallpaper(&g, display, radius: 9)
        drawNotch(&g, display: display, closed: CGSize(width: 62, height: 11), opened: CGSize(width: 236, height: 80), open: open)

        // Deck and lip.
        let deck = CGRect(x: cx - 222, y: screen.maxY, width: 444, height: 13)
        g.fill(Path(roundedRect: deck, cornerRadius: 6.5, style: .continuous),
               with: .linearGradient(Gradient(colors: [Palette.deckTop, Palette.deckLow]),
                                     startPoint: CGPoint(x: cx, y: deck.minY), endPoint: CGPoint(x: cx, y: deck.maxY)))
        g.fill(Path(roundedRect: CGRect(x: cx - 34, y: deck.minY, width: 68, height: 5), cornerRadius: 2.5), with: .color(Color(hex: 0x7D8088)))
    }
}

// MARK: - Point to open (hover)

struct HoverIllustration: View {
    var body: some View {
        Looping(stillTime: 2.4) { t in
            Canvas { g, size in draw(&g, size, t) }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let frame = CGRect(x: size.width / 2 - 240, y: 6, width: 480, height: size.height - 12)
        let loop = t.truncatingRemainder(dividingBy: 4.8)
        let move = CGFloat(smooth(0.2, 1.3, loop))
        let leave = CGFloat(smooth(3.5, 4.1, loop))
        let open = Motion.reduceMotion ? 1 : backOut(smooth(1.3, 1.75, loop)) * (1 - smooth(3.55, 3.95, loop))

        // Screen corner with a menu bar strip.
        g.fill(Path(roundedRect: frame.insetBy(dx: -8, dy: -8), cornerRadius: 22, style: .continuous), with: .color(Palette.lid))
        drawWallpaper(&g, frame, radius: 14)
        let bar = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 20)
        var c = g
        c.clip(to: Path(roundedRect: frame, cornerRadius: 14, style: .continuous))
        c.fill(Path(bar), with: .color(.white.opacity(0.16)))
        for i in 0..<4 {
            c.fill(Path(roundedRect: CGRect(x: frame.minX + 14 + CGFloat(i) * 30, y: bar.midY - 3, width: i == 0 ? 12 : 22, height: 6), cornerRadius: 3),
                   with: .color(.white.opacity(i == 0 ? 0.85 : 0.5)))
        }
        for i in 0..<3 {
            c.fill(Path(ellipseIn: CGRect(x: frame.maxX - 22 - CGFloat(i) * 18, y: bar.midY - 4, width: 8, height: 8)), with: .color(.white.opacity(0.6)))
        }
        drawNotch(&g, display: frame, closed: CGSize(width: 92, height: 20), opened: CGSize(width: 320, height: 128), open: open)

        // Pointer: travels to the notch, rests inside it, then leaves.
        let start = CGPoint(x: frame.minX + frame.width * 0.22, y: frame.maxY - 30)
        let target = CGPoint(x: frame.midX + 30, y: frame.minY + 12)
        let away = CGPoint(x: frame.maxX - 70, y: frame.maxY - 40)
        let inside = CGPoint(x: target.x, y: target.y + 70 * CGFloat(open))
        var p = CGPoint(x: start.x + (target.x - start.x) * move, y: start.y + (target.y - start.y) * move)
        if loop > 1.3 { p = inside }
        if leave > 0 { p = CGPoint(x: inside.x + (away.x - inside.x) * leave, y: inside.y + (away.y - inside.y) * leave) }
        if loop > 4.1 {
            let back = CGFloat(smooth(4.1, 4.8, loop))
            p = CGPoint(x: away.x + (start.x - away.x) * back, y: away.y + (start.y - away.y) * back)
        }
        drawPointer(&g, at: p, pressed: loop > 1.15 && loop < 1.4)
    }

    private func drawPointer(_ g: inout GraphicsContext, at p: CGPoint, pressed: Bool) {
        let k = pressed ? 0.9 : 1.15
        let pts: [(Double, Double)] = [(0, 0), (0, 17), (4.2, 13.2), (7.2, 20), (10, 18.8), (7.1, 12.2), (12.4, 12.2)]
        var arrow = Path()
        arrow.move(to: CGPoint(x: p.x + pts[0].0 * k, y: p.y + pts[0].1 * k))
        for q in pts.dropFirst() { arrow.addLine(to: CGPoint(x: p.x + q.0 * k, y: p.y + q.1 * k)) }
        arrow.closeSubpath()
        var shadow = g
        shadow.translateBy(x: 1, y: 2)
        shadow.fill(arrow, with: .color(.black.opacity(0.3)))
        g.fill(arrow, with: .color(.white))
        g.stroke(arrow, with: .color(.black), style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
    }
}

// MARK: - Confetti burst (finish page)

struct ConfettiIllustration: View {
    var body: some View {
        Looping(stillTime: 0.8) { t in
            Canvas { g, size in
                let colors: [Color] = [Color(hex: 0xFFD166), Theme.claudeLight, Theme.success, Color(hex: 0x7AB8FF), Color(hex: 0xFF8FB1), Color(hex: 0xB79CFF)]
                let c = CGPoint(x: size.width / 2, y: size.height * 0.52)
                for i in 0..<26 {
                    let seed = Double(i) * 2.399963
                    let ph = (t * 0.28 + Double(i) / 26).truncatingRemainder(dividingBy: 1)
                    let spread: Double = 0.6 + 0.4 * sin(seed * 3)
                    let dist = CGFloat(70 + ph * Double(size.width) * 0.36 * spread)
                    let dx = CGFloat(cos(seed)) * dist
                    let dy = CGFloat(sin(seed)) * dist * 0.55 + CGFloat(ph * ph * 40)
                    let p = CGPoint(x: c.x + dx, y: c.y + dy)
                    var ctx = g
                    ctx.opacity = sin(ph * .pi) * 0.9
                    ctx.translateBy(x: p.x, y: p.y)
                    ctx.rotate(by: .radians(t * 2 + seed))
                    if i % 3 == 0 {
                        ctx.fill(SparkShape(pinch: 0.22).path(in: CGRect(x: -6, y: -6, width: 12, height: 12)), with: .color(colors[i % colors.count]))
                    } else {
                        ctx.fill(Path(roundedRect: CGRect(x: -4, y: -2, width: 8, height: 4), cornerRadius: 1.5), with: .color(colors[i % colors.count]))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
