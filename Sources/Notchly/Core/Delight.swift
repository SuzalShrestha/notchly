import SwiftUI

// Light and motion that make the notch feel alive. Each effect is off under Reduce Motion, and still in snapshots.

extension Motion {
    /// Decorative motion is allowed: not Reduce Motion, and not a snapshot render (which captures the first frame).
    static var lively: Bool { !reduceMotion && !Snapshot.isRunning }
}

// MARK: - Transitions

private struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.blur(radius: radius).opacity(opacity) }
}

extension AnyTransition {
    /// Fade through a blur, so content dissolves instead of popping.
    static var blurFade: AnyTransition { .modifier(active: BlurFade(radius: 8, opacity: 0), identity: BlurFade(radius: 0, opacity: 1)) }

    /// A tab's content comes in from the side its icon is on in the dock; the old content dissolves in place.
    static func tab(forward: Bool) -> AnyTransition {
        if Motion.reduceMotion { return .opacity }
        return .asymmetric(insertion: .offset(x: forward ? 26 : -26).combined(with: .blurFade),
                           removal: .scale(scale: 0.97).combined(with: .blurFade))
    }
}

// MARK: - Aura

/// Colored light under the notch. It says what happens without a word: orange and breathing while an agent
/// waits for you (open or closed), the album color while music plays (open only, so the closed notch stays calm).
struct NotchAura<S: Shape>: View {
    let shape: S
    let isOpen: Bool

    var body: some View {
        let alert = AgentStore.shared.needsAttention && AgentsFeature.settings.value.notifyAttention
        let music = isOpen && MediaService.shared.track?.isPlaying == true
        ZStack {
            if alert || music {
                shape.stroke(alert ? Theme.warning : MediaService.shared.tint, lineWidth: isOpen ? 7 : 2)
                    .blur(radius: isOpen ? 14 : 7)
                    .modifier(Breathing(active: alert))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: [alert, music])
        .allowsHitTesting(false)
    }
}

private struct Breathing: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active && Motion.lively {
            content.phaseAnimator([0.4, 1.0]) { view, level in view.opacity(level) } animation: { _ in .easeInOut(duration: 1.3) }
        } else {
            content.opacity(0.75)
        }
    }
}

// MARK: - Spotlight

private struct Spotlight: ViewModifier {
    let radius: CGFloat
    @State private var point: CGPoint?
    func body(content: Content) -> some View {
        let edge = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .overlay {
                ZStack {
                    if let point {
                        Circle().fill(RadialGradient(colors: [.white.opacity(0.09), .clear], center: .center, startRadius: 0, endRadius: 110))
                            .frame(width: 220, height: 220).position(point)
                    }
                    edge.strokeBorder(Theme.hairlineStrong, lineWidth: 0.5).opacity(point == nil ? 0 : 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(edge)
                .animation(.easeOut(duration: 0.25), value: point == nil)
                .allowsHitTesting(false)
            }
            .onContinuousHover { phase in
                if case .active(let p) = phase { point = p } else { point = nil }
            }
    }
}

extension View {
    /// A soft light that follows the pointer across a card, and a brighter edge while the pointer is on it.
    func spotlight(radius: CGFloat = Theme.widgetRadius) -> some View { modifier(Spotlight(radius: radius)) }

    /// Rises into place after a short delay that grows with `index`, so a row of cards arrives as a cascade.
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }

    /// A slow float for the icon of an empty state.
    func floating() -> some View { modifier(Floating()) }
}

private struct Entrance: ViewModifier {
    let index: Int
    @State private var shown = !Motion.lively
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 10).scaleEffect(shown ? 1 : 0.96)
            .onAppear { withAnimation(Motion.gentle.delay(0.05 + 0.045 * Double(min(index, 6)))) { shown = true } }
    }
}

private struct Floating: ViewModifier {
    func body(content: Content) -> some View {
        if Motion.lively {
            content.phaseAnimator([false, true]) { view, up in view.offset(y: up ? -2.5 : 1.5) } animation: { _ in .easeInOut(duration: 1.8) }
        } else {
            content
        }
    }
}

// MARK: - Confetti

/// A burst of confetti out of the notch for a finished timer or a cleared to-do list.
@MainActor @Observable
final class Celebration {
    static let shared = Celebration()
    private(set) var startedAt: Date?

    func fire() {
        guard !Motion.reduceMotion else { return }
        let t = Date()
        startedAt = t
        Task {
            try? await Task.sleep(for: .seconds(Confetti.duration))
            if startedAt == t { startedAt = nil }
        }
    }
}

/// One frame of the burst, `time` seconds after it started. A pure function of time, so a snapshot can check it.
struct Confetti: View {
    static let duration = 2.2
    static let colors: [Color] = [Theme.accent, Theme.blue, Theme.green, Theme.claude, Theme.lightYellow, Theme.weekendPink]
    let time: Double
    /// Distance from the top of the view to the point the pieces fly out of (the bottom edge of the notch).
    let originY: CGFloat

    var body: some View {
        Canvas { ctx, size in
            for i in 0..<48 {
                // Fixed pseudo-random numbers per piece: the same burst on every frame, no stored state.
                func rnd(_ k: Double) -> Double { let v = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453; return v - v.rounded(.down) }
                let angle = (rnd(1) - 0.5) * .pi * 1.1            // a fan that opens downward
                let speed = 140 + rnd(2) * 220
                let x = size.width / 2 + sin(angle) * speed * time * (1 - 0.18 * time)
                let y = originY + cos(angle) * speed * 0.55 * time + 150 * time * time
                var piece = ctx
                piece.opacity = min(1, max(0, 1 - time / Self.duration) * 1.6)
                piece.translateBy(x: x, y: y)
                piece.rotate(by: .radians(rnd(3) * 6 + time * (rnd(4) - 0.5) * 14))
                let w = 4 + rnd(5) * 4
                let path = i % 3 == 0 ? Path(ellipseIn: CGRect(x: -w / 2.5, y: -w / 2.5, width: w / 1.25, height: w / 1.25))
                                      : Path(roundedRect: CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2 + rnd(6) * 2), cornerRadius: 1)
                piece.fill(path, with: .color(Self.colors[i % Self.colors.count]))
            }
        }
        .allowsHitTesting(false)
    }
}
