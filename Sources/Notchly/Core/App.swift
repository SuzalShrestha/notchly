import AppKit
import Carbon.HIToolbox
import IOKit.ps
import SwiftUI

@main
struct NotchlyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // LSUIElement agent, like NotchNook. `--dock` runs as a regular app so UI-testing tools can see it.
        app.setActivationPolicy(CommandLine.arguments.contains("--dock") ? .regular : .accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var hotKeys: [EventHotKeyRef] = []
    private var hotKeyHandlerInstalled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        if CommandLine.arguments.contains("--selftest") { Features.selfTest(); exit(0) }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.run(to: CommandLine.arguments[i + 1]); exit(0)
        }
        // One notch owner: a second copy (e.g. `open -n`) would stack panels and steal the agent socket.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != NSRunningApplication.current }) {
            exit(0)
        }
        Features.start()
        PowerMonitor.shared.start()
        NotchManager.shared.start()
        setUpStatusItem()
        updateHotKeys()
        // First launch: an agent app has no Dock icon or window, so greet with the welcome tour.
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") || CommandLine.arguments.contains("--onboarding") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            showOnboarding()
        }
        // Escape in a notch text field ends editing; a second Escape closes the open notch.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            if let w = event.window as? NotchPanel, w.firstResponder is NSTextView {
                w.makeFirstResponder(nil); return nil
            }
            if !(event.window?.firstResponder is NSTextView),
               let c = NotchManager.shared.controllers.first(where: { $0.model.isOpen }) {
                c.model.close(); return nil
            }
            return event
        }
        if CommandLine.arguments.contains("--open") {
            NotchManager.shared.activeController?.model.open(CommandLine.arguments.last.flatMap(NotchMode.init(rawValue:)))
        }
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) while it runs shows Settings; there is no Dock icon to click.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notchly")
        let menu = NSMenu()
        for mode in NotchMode.allCases {
            let mi = NSMenuItem(title: "Open \(mode.title)", action: #selector(openMode(_:)), keyEquivalent: "\(mode.shortcutDigit)")
            mi.keyEquivalentModifierMask = [.command, .control]
            mi.representedObject = mode.rawValue
            mi.target = self
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Welcome Tour…", action: #selector(showOnboarding), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Notchly Website", action: #selector(openWebsite), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Report an Issue…", action: #selector(reportIssue), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notchly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = NotchMode(rawValue: raw) else { return }
        NotchManager.shared.open(mode)
    }

    @objc private func checkForUpdates() { Updates.check() }
    @objc private func openWebsite() { NSWorkspace.shared.open(AppInfo.website) }
    @objc private func reportIssue() { NSWorkspace.shared.open(AppInfo.newIssue) }

    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 820, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Notchly Settings"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsRootView())
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showOnboarding() {
        if onboardingWindow == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            w.title = "Welcome to Notchly"
            w.contentView = NSHostingView(rootView: OnboardingView { [weak self] openNotch in self?.finishOnboarding(openNotch: openNotch) })
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding(openNotch: Bool) {
        onboardingWindow?.close()
        // Drop the window after this action returns, so the tour starts fresh next time.
        DispatchQueue.main.async { self.onboardingWindow = nil }
        if openNotch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { NotchManager.shared.activeController?.model.open(.nook) }
        }
    }

    // MARK: Navigation shortcuts ⌘⌃1…7 (NotchNook: modifiers = 9 → command + control, inferred)

    /// Registers the global shortcuts when they are on and releases them when off, so other apps get ⌃⌘digit back.
    func updateHotKeys() {
        let enabled = Settings.general.value.navigationShortcutsEnabled
        if !enabled {
            hotKeys.forEach { UnregisterEventHotKey($0) }
            hotKeys = []
            return
        }
        guard hotKeys.isEmpty else { return }
        installHotKeyHandler()
        let keyCodes = [1: kVK_ANSI_1, 2: kVK_ANSI_2, 3: kVK_ANSI_3, 4: kVK_ANSI_4, 5: kVK_ANSI_5, 6: kVK_ANSI_6, 7: kVK_ANSI_7]
        for (digit, code) in keyCodes {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(code), UInt32(cmdKey | controlKey),
                                             EventHotKeyID(signature: OSType(0x4E4F5443), id: UInt32(digit)), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { hotKeys.append(ref) }
        }
    }

    private func installHotKeyHandler() {
        guard !hotKeyHandlerInstalled else { return }
        hotKeyHandlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let digit = Int(id.id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard Settings.general.value.navigationShortcutsEnabled,
                          let mode = NotchMode.allCases.first(where: { $0.shortcutDigit == digit }) else { return }
                    NotchManager.shared.open(mode)
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

// MARK: - Battery (PowerMonitor + batteryVisualizer live activity)

@MainActor @Observable
final class PowerMonitor {
    static let shared = PowerMonitor()
    private(set) var hasBattery = false
    private(set) var percent = 100
    private(set) var isCharging = false
    private(set) var isPluggedIn = false

    var symbol: String {
        if isCharging { return "battery.100percent.bolt" }
        switch percent { case ..<13: return "battery.0percent"; case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"; case ..<88: return "battery.75percent"; default: return "battery.100percent" }
    }

    func start() {
        read(initial: true)
        let source = IOPSNotificationCreateRunLoopSource({ _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { PowerMonitor.shared.read(initial: false) } }
        }, nil).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func read(initial: Bool) {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        guard let ps = list.first,
              let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else { hasBattery = false; return }
        let wasPlugged = isPluggedIn
        hasBattery = true
        let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0, max = d[kIOPSMaxCapacityKey] as? Int ?? 100
        percent = max > 0 ? cur * 100 / max : 0
        isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
        isPluggedIn = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        guard !initial, wasPlugged != isPluggedIn else { return }
        let color: Color = isPluggedIn ? Theme.green : (percent <= 20 ? .red : .white)
        LiveActivityCenter.shared.show(LiveActivity(
            kind: .batteryVisualizer, priority: 50, leadingWidth: 64, trailingWidth: 44,
            leading: AnyView(Text(isPluggedIn ? "Charging" : "On Battery").font(Theme.caption.weight(.semibold)).foregroundStyle(color).lineLimit(1)),
            trailing: AnyView(HStack(spacing: 3) {
                Text("\(percent)%").font(Theme.caption.weight(.semibold)).monospacedDigit()
                Image(systemName: isPluggedIn ? "bolt.fill" : symbol).font(.system(size: 10, weight: .bold))
            }.foregroundStyle(color))
        ), duration: 3)
    }
}
