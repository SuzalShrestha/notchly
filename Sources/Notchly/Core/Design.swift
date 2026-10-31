import SwiftUI

// Design tokens measured from NotchNook (README › "Design values measured from NotchNook").
enum Theme {
    static let panel = Color.black
    static let card = Color(white: 0.11)            // widget card on black (#1C1C1E)
    static let chip = Color.white.opacity(0.10)     // capsule chips and round buttons
    static let chipHover = Color.white.opacity(0.16)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.32)
    static let accent = Color(nsColor: .systemOrange) // timer / to-dos
    static let blue = Color(nsColor: .systemBlue)     // calendar / notes
    static let green = Color(nsColor: .systemGreen)   // AI usage ring, battery
    // Named colors from Assets.car (Display P3).
    static let noteBG = Color(.displayP3, red: 0.098, green: 0.098, blue: 0.106)
    static let selected = Color(.displayP3, red: 0.125, green: 0.125, blue: 0.133)
    static let weekendPink = Color(.displayP3, red: 0.925, green: 0.643, blue: 0.612)
    static let lightYellow = Color(.displayP3, red: 0.996, green: 1, blue: 0.761)

    static let widgetRadius: CGFloat = 22
    static let contentPadding: CGFloat = 12          // generalSettings.contentPadding default

    static func title(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .semibold) }
    static let body = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11, weight: .medium)
}

// Springs measured from NotchNook's NotchView.openAnimation / closeAnimation.
enum Motion {
    static func open(speed: Double = 1) -> Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return .easeInOut(duration: 0.2) }
        return .spring(response: 0.48, dampingFraction: 0.88).speed(speed)
    }
    static func close(speed: Double = 1) -> Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return .easeInOut(duration: 0.2) }
        return .spring(response: 0.4, dampingFraction: 0.95).speed(speed)
    }
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.85)
}

/// Notch body with rounded bottom corners and concave top "ears" that sit outside the body.
/// Path and radii match NotchShape.path(in:) in the app binary and the website's notch module
/// (docs/index.html draws the same path): cubic corners with a 0.62 control factor.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var earRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(bottomRadius, earRadius) }
        set { bottomRadius = newValue.first; earRadius = newValue.second }
    }

    /// `rect` includes the ears: body width = rect.width − 2 × earRadius.
    func path(in rect: CGRect) -> Path {
        let n = earRadius, k: CGFloat = 0.62
        let x0 = rect.minX + n, w = rect.width - 2 * n, h = rect.height, y0 = rect.minY
        let a = min(bottomRadius, h / 2, w / 2)
        var p = Path()
        p.move(to: CGPoint(x: x0 - n, y: y0))
        p.addLine(to: CGPoint(x: x0 + w + n, y: y0))
        p.addCurve(to: CGPoint(x: x0 + w, y: y0 + n),
                   control1: CGPoint(x: x0 + w + n - k * n, y: y0), control2: CGPoint(x: x0 + w, y: y0 + n - k * n))
        p.addLine(to: CGPoint(x: x0 + w, y: y0 + h - a))
        p.addCurve(to: CGPoint(x: x0 + w - a, y: y0 + h),
                   control1: CGPoint(x: x0 + w, y: y0 + h - a + k * a), control2: CGPoint(x: x0 + w - a + k * a, y: y0 + h))
        p.addLine(to: CGPoint(x: x0 + a, y: y0 + h))
        p.addCurve(to: CGPoint(x: x0, y: y0 + h - a),
                   control1: CGPoint(x: x0 + a - k * a, y: y0 + h), control2: CGPoint(x: x0, y: y0 + h - a + k * a))
        p.addLine(to: CGPoint(x: x0, y: y0 + n))
        p.addCurve(to: CGPoint(x: x0 - n, y: y0),
                   control1: CGPoint(x: x0, y: y0 + n - k * n), control2: CGPoint(x: x0 - n + k * n, y: y0))
        p.closeSubpath()
        return p
    }

    private static func lerp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
        c + (d - c) * min(max((v - a) / (b - a), 0), 1)
    }

    /// radius(forHeight:notchSize:): 11 pt closed (0.65 × h for notches under 14 pt) → 40 pt at +100 pt of height.
    static func bottomRadius(height: CGFloat, notch: CGSize) -> CGFloat {
        let r0 = notch.height < 14 ? notch.height * 0.65 : 11
        return lerp(height, notch.height, notch.height + 100, r0, 40)
    }

    /// decorationRadius(forSize:notchSize:): min(5, h − r) closed → 24 pt at +300 pt of width, plus up to +6 pt with height.
    static func earRadius(size: CGSize, notch: CGSize) -> CGFloat {
        let e0 = max(0, min(5, size.height - bottomRadius(height: size.height, notch: notch)))
        let e = lerp(max(notch.width, size.width), notch.width, notch.width + 300, e0, 24)
        return e + e / 24 * lerp(size.height, notch.height + 40, notch.height + 120, 0, 6)
    }
}

// MARK: - Shared components

/// Black widget tile used across the Nook grid.
struct WidgetCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.widgetRadius, style: .continuous))
    }
}

/// Round icon button (generalSettings.preferRoundButtons = true).
struct RoundButton: View {
    let symbol: String
    var size: CGFloat = 32
    var tint: Color = .white
    var fill: Color = Theme.chip
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(hovering ? Theme.chipHover : fill, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
    }
}

/// Capsule chip with optional icon.
struct Chip: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = .white
    var fill: Color = Theme.chip
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(Theme.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(fill, in: Capsule())
    }
}

/// Scale-down press feedback (ShrinkOnClick in the original).
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// Empty-state placeholder inside the notch.
struct EmptyState: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
            Text(title).font(Theme.title(13)).foregroundStyle(Theme.secondaryText)
            if let subtitle { Text(subtitle).font(Theme.caption).foregroundStyle(Theme.tertiaryText).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Settings window components (NotchNookSettingsCard / Row)

struct SettingsCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4) }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.vertical, 7)
    }
}

/// Pane wrapper: header + scrolling cards.
struct SettingsPane<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title).font(.system(size: 22, weight: .bold))
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
