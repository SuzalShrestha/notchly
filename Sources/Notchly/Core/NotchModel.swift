import SwiftUI

/// Open-notch destinations (NotchNookState.NotchMode minus closed/dragging/terminal).
enum NotchMode: String, CaseIterable, Codable, Identifiable {
    case nook, music, calendar, tray, prompter, clipboard, agents
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nook: "Nook"
        case .music: "Music"
        case .calendar: "Calendar"
        case .tray: "Tray"
        case .prompter: "Prompter"
        case .clipboard: "Clipboard"
        case .agents: "Agents"
        }
    }

    var symbol: String {
        switch self {
        case .nook: "square.grid.2x2.fill"
        case .music: "music.note"
        case .calendar: "calendar"
        case .tray: "tray.fill"
        case .prompter: "text.alignleft"
        case .clipboard: "doc.on.clipboard.fill"
        case .agents: "sparkles"
        }
    }

    /// Navigation shortcut digit, same order as NotchNook's navigationShortcutsSettings.
    var shortcutDigit: Int {
        switch self {
        case .nook: 1; case .music: 2; case .calendar: 3; case .tray: 4
        case .prompter: 5; case .clipboard: 6; case .agents: 7
        }
    }

    /// Content area size below the top bar (inferred from widget mock proportions).
    var contentSize: CGSize {
        switch self {
        case .nook: CGSize(width: 680, height: 156)
        case .music: CGSize(width: 560, height: 156)
        case .calendar: CGSize(width: 640, height: 200)
        case .tray: CGSize(width: 620, height: 150)
        case .prompter: CGSize(width: 600, height: 190)
        case .clipboard: CGSize(width: 760, height: 190)
        case .agents: CGSize(width: 680, height: 220)
        }
    }
}

/// Per-screen notch state (NotchViewModel + NotchNookState in the original).
@MainActor @Observable
final class NotchModel {
    let screenID: CGDirectDisplayID
    var notchSize: CGSize
    var hasPhysicalNotch: Bool
    var isOpen = false
    var mode: NotchMode = .nook
    var hovering = false
    var isDraggingFiles = false
    /// A text field inside the notch has focus; keep it open on unhover.
    var keyboardPinned = false
    /// Last mode the user picked; reopening returns there.
    @ObservationIgnored var lastMode: NotchMode = .nook
    /// Set by the window controller: gives keyboard focus back when the notch closes.
    @ObservationIgnored var onClose: (() -> Void)?

    init(screenID: CGDirectDisplayID, notchSize: CGSize, hasPhysicalNotch: Bool) {
        self.screenID = screenID
        self.notchSize = notchSize
        self.hasPhysicalNotch = hasPhysicalNotch
    }

    var topBarHeight: CGFloat { max(notchSize.height, 28) }

    /// Size of the black shape for the current state.
    var shapeSize: CGSize {
        if isOpen {
            let pad = Settings.general.value.contentPadding
            // One width for every tab so the navigation dock never moves under the pointer.
            let width = NotchMode.allCases.map(\.contentSize.width).max()! + pad * 2
            return CGSize(width: max(width, notchSize.width + 260), height: topBarHeight + mode.contentSize.height + pad * 2)
        }
        if let a = LiveActivityCenter.shared.current {
            return CGSize(width: notchSize.width + a.leadingWidth + a.trailingWidth + 24, height: notchSize.height)
        }
        if hasPhysicalNotch || hovering { return notchSize }
        // Notchless screens rest as a thin handle (generalSettings.handleSize = [184, 8]).
        let g = Settings.general.value
        return CGSize(width: g.handleWidth, height: g.handleHeight)
    }

    func open(_ mode: NotchMode? = nil) {
        let target = mode ?? lastMode
        guard !isOpen || self.mode != target else { return }
        if !isOpen, !Settings.general.value.disableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        withAnimation(Motion.open(speed: Settings.general.value.notchOpenSpeed.multiplier)) {
            self.mode = target
            isOpen = true
        }
    }

    func select(_ mode: NotchMode) {
        lastMode = mode
        keyboardPinned = false
        withAnimation(Motion.snappy) { self.mode = mode }
    }

    func close() {
        guard isOpen else { return }
        keyboardPinned = false
        onClose?()
        withAnimation(Motion.close(speed: Settings.general.value.notchOpenSpeed.multiplier)) {
            isOpen = false
            isDraggingFiles = false
        }
    }

    func toggle(_ mode: NotchMode) {
        if isOpen && self.mode == mode { close() } else { open(mode); lastMode = mode }
    }
}
