import SwiftUI

struct NotchRootView: View {
    let model: NotchModel

    var body: some View {
        let size = model.shapeSize
        let shape = NotchShape(bottomRadius: NotchShape.bottomRadius(height: size.height, notch: model.notchSize),
                               earRadius: NotchShape.earRadius(size: size, notch: model.notchSize))
        ZStack(alignment: .top) {
            shape
                .fill(Theme.panel)
                .shadow(color: .black.opacity(model.isOpen ? 0.55 : 0), radius: 14, y: 6)
            if model.isOpen {
                OpenNotchContent(model: model, ear: shape.earRadius)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.86, anchor: .top)).animation(Motion.open().delay(0.04)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            } else {
                ClosedNotchContent(model: model, ear: shape.earRadius)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width + shape.earRadius * 2, height: size.height)
        .contentShape(shape)
        .onTapGesture { if !model.isOpen { model.open() } }
        .environment(model)
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Live activity wings beside the camera housing.
private struct ClosedNotchContent: View {
    let model: NotchModel
    let ear: CGFloat
    var body: some View {
        if let a = LiveActivityCenter.shared.current {
            HStack(spacing: 0) {
                a.leading.frame(width: a.leadingWidth, alignment: .leading)
                Spacer(minLength: model.notchSize.width)
                a.trailing.frame(width: a.trailingWidth, alignment: .trailing)
            }
            .padding(.horizontal, 12 + ear)
            .frame(height: model.notchSize.height)
            .id(a.kind)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }
}

private struct OpenNotchContent: View {
    let model: NotchModel
    let ear: CGFloat

    var body: some View {
        let pad = Settings.general.value.contentPadding
        VStack(spacing: 0) {
            TopBar(model: model)
                .frame(height: model.topBarHeight)
            ModeContent(mode: model.mode)
                .frame(width: model.shapeSize.width - pad * 2, height: model.mode.contentSize.height)
                .padding(pad)
                .id(model.mode)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        .padding(.horizontal, ear)
        .foregroundStyle(.white)
    }
}

private struct TopBar: View {
    let model: NotchModel
    var body: some View {
        HStack(spacing: 8) {
            NavigationDock(model: model)
            Spacer(minLength: model.hasPhysicalNotch ? model.notchSize.width + 16 : 16)
            TopBarStatus()
            RoundButton(symbol: "gearshape.fill", size: 24) { AppDelegate.shared?.showSettings() }
        }
        .padding(.horizontal, 14)
        .padding(.top, model.hasPhysicalNotch ? 0 : 4)
    }
}

/// Tab switcher (NavigationDockSurface, styles compact / icons / dots).
private struct NavigationDock: View {
    let model: NotchModel
    var body: some View {
        let style = Settings.general.value.navigationDockStyle
        let modes = NotchMode.allCases.filter { !Settings.general.value.hiddenModes.contains($0) }
        HStack(spacing: style == .dots ? 6 : 2) {
            ForEach(modes) { mode in
                let selected = model.mode == mode
                Button { model.select(mode) } label: {
                    if style == .dots {
                        Circle().fill(.white.opacity(selected ? 0.95 : 0.3)).frame(width: 6, height: 6)
                            .frame(width: 12, height: 20)
                    } else {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(selected ? 1 : 0.45))
                            .frame(width: 28, height: 22)
                            .background(selected && style == .compact ? Theme.chipHover : .clear, in: Capsule())
                    }
                }
                .buttonStyle(PressableStyle())
                .help("\(mode.title)  ⌘⌃\(mode.shortcutDigit)")
            }
        }
        .padding(2)
        .background(style == .compact ? Theme.chip.opacity(0.6) : .clear, in: Capsule())
    }
}

/// Battery readout on the right of the top bar.
private struct TopBarStatus: View {
    var body: some View {
        let b = PowerMonitor.shared
        if b.hasBattery {
            HStack(spacing: 4) {
                Text("\(b.percent)%").font(Theme.caption.weight(.semibold)).monospacedDigit()
                Image(systemName: b.symbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(b.isCharging ? Theme.green : (b.percent <= 20 ? .red : .white), .white.opacity(0.4))
            }
            .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// Routes the open notch to each feature's tab view.
struct ModeContent: View {
    let mode: NotchMode
    var body: some View {
        switch mode {
        case .nook: NookView()
        case .music: MusicView()
        case .calendar: CalendarTabView()
        case .tray: TrayView()
        case .prompter: PrompterView()
        case .clipboard: ClipboardView()
        case .agents: AgentsView()
        }
    }
}
