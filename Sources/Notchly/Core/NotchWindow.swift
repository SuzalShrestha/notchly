import AppKit
import SwiftUI

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Camera housing size; nil on screens without a notch.
    var physicalNotchSize: CGSize? {
        guard safeAreaInsets.top > 0, let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - l.width - r.width, height: safeAreaInsets.top)
    }
}

/// Borderless, non-activating panel that floats over the menu bar on every Space.
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = true   // buttons do not steal focus; text fields still can
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// One notch per screen (WindowsManager.DisplayKit in the original).
@MainActor
final class NotchController {
    static let windowSize = CGSize(width: 960, height: 420)

    let screen: NSScreen
    let model: NotchModel
    let panel: NotchPanel
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?

    init(screen: NSScreen) {
        self.screen = screen
        let g = Settings.general.value
        let physical = screen.physicalNotchSize
        var size = physical ?? CGSize(width: g.handleWidth, height: max(NSStatusBar.system.thickness, 24))
        size.width += g.notchWidthFineTune
        size.height += g.notchHeightFineTune
        model = NotchModel(screenID: screen.displayID, notchSize: size, hasPhysicalNotch: physical != nil)

        let f = screen.frame
        let frame = CGRect(x: f.midX - Self.windowSize.width / 2, y: f.maxY - Self.windowSize.height,
                           width: Self.windowSize.width, height: Self.windowSize.height)
        panel = NotchPanel(frame: frame)
        panel.sharingType = g.showNotchInScreenshots ? .readOnly : .none
        let host = NSHostingView(rootView: NotchRootView(model: model).frame(width: frame.width, height: frame.height, alignment: .top))
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
        model.onClose = { [weak panel] in
            panel?.makeFirstResponder(nil)
            panel?.resignKey()
        }
    }

    func tearDown() { panel.orderOut(nil); panel.close() }

    /// Shape rect in screen coordinates.
    var shapeRect: CGRect {
        let s = model.shapeSize, f = screen.frame
        return CGRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height)
    }

    /// Called for every pointer move (global and local monitors).
    func pointerMoved(to p: CGPoint, draggingFiles: Bool) {
        let rect = shapeRect
        let zone = model.isOpen ? rect.insetBy(dx: -6, dy: -8)
                                : rect.insetBy(dx: -8, dy: model.hasPhysicalNotch ? -2 : -6)
        let inside = zone.contains(p)
        panel.ignoresMouseEvents = !inside

        if draggingFiles {
            let dropZone = rect.insetBy(dx: -120, dy: -60)
            if dropZone.contains(p) {
                panel.ignoresMouseEvents = false
                if !model.isDraggingFiles {
                    model.isDraggingFiles = true
                    model.open(.tray)
                }
            }
            return
        }

        if inside != model.hovering {
            withAnimation(Motion.snappy) { model.hovering = inside }
        }
        if inside {
            closeWork?.cancel(); closeWork = nil
            guard !model.isOpen, Settings.general.value.alwaysOpenNotchOnHover, openWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.openWork = nil
                guard let self, self.model.hovering else { return }
                self.model.open()
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Settings.general.value.hoverOpenDelay, execute: work)
        } else {
            openWork?.cancel(); openWork = nil
            guard model.isOpen, closeWork == nil else { return }
            if model.keyboardPinned && Settings.general.value.preventUnhoverCloseWhenTyping { return }
            let work = DispatchWorkItem { [weak self] in
                self?.closeWork = nil
                guard let self, !self.model.hovering else { return }
                self.model.close()
                self.panel.ignoresMouseEvents = true
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }

    func dragEnded(at p: CGPoint) {
        guard model.isDraggingFiles else { return }
        model.isDraggingFiles = false
        if !shapeRect.insetBy(dx: -6, dy: -8).contains(p) {
            model.close()
            panel.ignoresMouseEvents = true
        }
    }
}

/// Owns all notch controllers and the pointer monitors.
@MainActor
final class NotchManager {
    static let shared = NotchManager()
    private(set) var controllers: [NotchController] = []
    private var monitors: [Any] = []
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var dragHasFiles = false
    private var dragStartedInApp = false

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchManager.shared.rebuild() }
        }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] _ in self?.handleMove() } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] e in self?.handleMove(); return e } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.mouseDown(inApp: false) } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in self?.mouseDown(inApp: true); return e } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.mouseUp() } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] e in self?.mouseUp(); return e } as Any)
    }

    func rebuild() {
        controllers.forEach { $0.tearDown() }
        let g = Settings.general.value
        controllers = NSScreen.screens.compactMap { screen in
            let notched = screen.physicalNotchSize != nil
            switch g.displaySelection {
            case .notchedOnly where !notched: return nil
            case .mainOnly where screen != NSScreen.main: return nil
            default: break
            }
            if !notched && !g.enableOnNonNotchScreens { return nil }
            return NotchController(screen: screen)
        }
    }

    /// Controller under the pointer, else the one on the main screen.
    var activeController: NotchController? {
        let p = NSEvent.mouseLocation
        return controllers.first { $0.screen.frame.contains(p) } ?? controllers.first
    }

    private func mouseDown(inApp: Bool) {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        dragHasFiles = false
        dragStartedInApp = inApp
        guard !inApp else { return }
        // A click in another app closes an open notch, even one pinned by a text field.
        let p = NSEvent.mouseLocation
        for c in controllers where c.model.isOpen && !c.shapeRect.contains(p) {
            c.model.close()
            c.panel.ignoresMouseEvents = true
        }
    }

    private func handleMove() {
        let p = NSEvent.mouseLocation
        if NSEvent.pressedMouseButtons & 1 == 1 {
            // Only drags that start outside the notch can bring files in (a scrubber drag must not open the tray).
            let pb = NSPasteboard(name: .drag)
            if !dragStartedInApp, pb.changeCount != dragChangeCount { dragHasFiles = pb.types?.contains(.fileURL) ?? false }
        } else if dragHasFiles || controllers.contains(where: { $0.model.isDraggingFiles }) {
            // The mouse-up was eaten by a drag session (e.g. dragging a tray file out): end the drag here.
            mouseUp()
        }
        for c in controllers { c.pointerMoved(to: p, draggingFiles: dragHasFiles) }
    }

    private func mouseUp() {
        let p = NSEvent.mouseLocation
        dragHasFiles = false
        for c in controllers { c.dragEnded(at: p) }
    }

    func open(_ mode: NotchMode) { activeController?.model.toggle(mode) }
}
