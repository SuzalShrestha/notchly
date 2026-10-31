import ServiceManagement
import SwiftUI

/// Settings sections (subset of NotchNookSettingsSection, same order).
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, nook, music, calendar, tray, clipboard, prompter, agents, liveActivities, shortcuts, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .nook: "Nook"
        case .music: "Music"
        case .calendar: "Calendar & Timers"
        case .tray: "Tray"
        case .clipboard: "Clipboard"
        case .prompter: "Prompter"
        case .agents: "Agents & AI Usage"
        case .liveActivities: "Live Activities"
        case .shortcuts: "Keyboard Shortcuts"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .nook: "square.grid.2x2.fill"
        case .music: "music.note"
        case .calendar: "calendar"
        case .tray: "tray.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .prompter: "text.alignleft"
        case .agents: "sparkles"
        case .liveActivities: "capsule.fill"
        case .shortcuts: "command"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .nook: .indigo
        case .music: .pink
        case .calendar: .red
        case .tray: .blue
        case .clipboard: .teal
        case .prompter: .orange
        case .agents: .purple
        case .liveActivities: .green
        case .shortcuts: .gray
        case .about: .blue
        }
    }
}

struct SettingsRootView: View {
    @State private var section: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { s in
                Label {
                    Text(s.title)
                } icon: {
                    Image(systemName: s.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(s.color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .tag(s)
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            pane.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder private var pane: some View {
        switch section {
        case .general: GeneralPane()
        case .nook: NookPane()
        case .music: MusicPane()
        case .calendar: CalendarPane()
        case .tray: TrayPane()
        case .clipboard: ClipboardPane()
        case .prompter: PrompterPane()
        case .agents: AgentsPane()
        case .liveActivities: LiveActivitiesPane()
        case .shortcuts: ShortcutsPane()
        case .about: AboutPane()
        }
    }
}

private struct GeneralPane: View {
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        let s = Settings.general
        SettingsPane(title: "General") {
            SettingsCard(title: "Behavior") {
                SettingsRow(title: "Launch at login", subtitle: loginSubtitle) {
                    HStack {
                        if loginStatus == .requiresApproval {
                            Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        }
                        Toggle("", isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                                                 set: { setLaunchAtLogin($0) }))
                            .labelsHidden().toggleStyle(.switch)
                    }
                }
                Divider()
                SettingsRow(title: "Open notch on hover", subtitle: "Off: click the notch to open it.") {
                    Toggle("", isOn: s.binding(\.alwaysOpenNotchOnHover)).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsRow(title: "Keep open while typing") {
                    Toggle("", isOn: s.binding(\.preventUnhoverCloseWhenTyping)).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsRow(title: "Haptic feedback") {
                    Toggle("", isOn: Binding(get: { !s.value.disableHaptics }, set: { s.value.disableHaptics = !$0 })).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsRow(title: "Opening speed") {
                    Picker("", selection: s.binding(\.notchOpenSpeed)) {
                        ForEach(NotchOpenSpeed.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }.labelsHidden().fixedSize()
                }
            }
            SettingsCard(title: "Appearance") {
                SettingsRow(title: "Navigation style") {
                    Picker("", selection: s.binding(\.navigationDockStyle)) {
                        ForEach(NavigationDockStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Divider()
                SettingsRow(title: "Content padding") {
                    Slider(value: s.binding(\.contentPadding), in: 6...20, step: 1).frame(width: 180)
                }
                Divider()
                SettingsRow(title: "Notch width fine-tune", subtitle: "Match the camera housing exactly.") {
                    Slider(value: s.binding(\.notchWidthFineTune), in: -20...20, step: 1).frame(width: 180)
                }
                Divider()
                SettingsRow(title: "Notch height fine-tune") {
                    Slider(value: s.binding(\.notchHeightFineTune), in: -6...6, step: 1).frame(width: 180)
                }
                Divider()
                SettingsRow(title: "Show notch in screenshots") {
                    Toggle("", isOn: s.binding(\.showNotchInScreenshots)).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsCard(title: "Tabs") {
                ForEach(NotchMode.allCases) { mode in
                    SettingsRow(title: mode.title) {
                        Toggle("", isOn: Binding(
                            get: { !s.value.hiddenModes.contains(mode) },
                            set: { on in s.value.hiddenModes.removeAll { $0 == mode }; if !on { s.value.hiddenModes.append(mode) } }
                        )).labelsHidden().toggleStyle(.switch).disabled(mode == .nook)
                    }
                    if mode != NotchMode.allCases.last { Divider() }
                }
            }
            SettingsCard(title: "Displays") {
                SettingsRow(title: "Show on") {
                    Picker("", selection: s.binding(\.displaySelection)) {
                        Text("All displays").tag(DisplaySelection.all)
                        Text("Notched displays").tag(DisplaySelection.notchedOnly)
                        Text("Main display").tag(DisplaySelection.mainOnly)
                    }.labelsHidden().fixedSize()
                }
                Divider()
                SettingsRow(title: "Use on displays without a notch", subtitle: "Shows a small handle at the top.") {
                    Toggle("", isOn: s.binding(\.enableOnNonNotchScreens)).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        // Display options are read when the notch windows are built: rebuild them on change.
        .onChange(of: Self.displayKey(s.value)) { NotchManager.shared.rebuild() }
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    private var loginSubtitle: String? {
        if let loginError { return loginError }
        return loginStatus == .requiresApproval ? "Waiting for approval in System Settings › General › Login Items." : nil
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
    }

    private static func displayKey(_ g: GeneralSettings) -> String {
        "\(g.displaySelection.rawValue)|\(g.enableOnNonNotchScreens)|\(g.notchWidthFineTune)|\(g.notchHeightFineTune)|\(g.showNotchInScreenshots)"
    }
}

private struct LiveActivitiesPane: View {
    var body: some View {
        let s = LiveActivityCenter.settings
        SettingsPane(title: "Live Activities") {
            SettingsCard {
                SettingsRow(title: "Show live activities", subtitle: "Small status around the closed notch.") {
                    Toggle("", isOn: s.binding(\.enabled)).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsRow(title: "Replace volume & brightness HUD") {
                    Toggle("", isOn: s.binding(\.showHUDReplacement)).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsCard(title: "Activities") {
                ForEach(LiveActivity.Kind.allCases.filter { $0 != .hud }, id: \.self) { kind in
                    SettingsRow(title: kind.title) {
                        Toggle("", isOn: Binding(
                            get: { !s.value.disabledKinds.contains(kind) },
                            set: { on in s.value.disabledKinds.removeAll { $0 == kind }; if !on { s.value.disabledKinds.append(kind) } }
                        )).labelsHidden().toggleStyle(.switch)
                    }
                    Divider()
                }
            }
        }
    }
}

private struct ShortcutsPane: View {
    var body: some View {
        SettingsPane(title: "Keyboard Shortcuts") {
            SettingsCard {
                SettingsRow(title: "Navigation shortcuts", subtitle: "Open a tab from anywhere.") {
                    Toggle("", isOn: Settings.general.binding(\.navigationShortcutsEnabled)).labelsHidden().toggleStyle(.switch)
                        .onChange(of: Settings.general.value.navigationShortcutsEnabled) { AppDelegate.shared?.updateHotKeys() }
                }
                ForEach(NotchMode.allCases) { mode in
                    Divider()
                    SettingsRow(title: mode.title) {
                        Text("⌃⌘\(mode.shortcutDigit)").font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                Divider()
                SettingsRow(title: "Close the notch") { Text("esc").font(.system(.body, design: .monospaced)) }
            }
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        SettingsPane(title: "About") {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(LinearGradient(colors: [Color(hex: 0x6F27C4), Color(hex: 0x12061F)], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notchly").font(.system(size: 28, weight: .bold))
                    Text("Version \(AppInfo.version)").foregroundStyle(.secondary).textSelection(.enabled)
                    Text("Free and open source under the MIT license. An independent project, not affiliated with NotchNook or lo.cafe.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
            }
            SettingsCard(title: "Project") {
                SettingsRow(title: "Updates", subtitle: "Checks GitHub only when you click.") {
                    Button("Check for Updates…") { Updates.check() }
                }
                Divider()
                SettingsRow(title: "Website") { Link("suzalshrestha.github.io/notchly", destination: AppInfo.website) }
                Divider()
                SettingsRow(title: "Source code") { Link("github.com/\(AppInfo.repository)", destination: AppInfo.sourceCode) }
                Divider()
                SettingsRow(title: "Found a bug or have an idea?") { Link("Open an issue", destination: AppInfo.newIssue) }
            }
            SettingsCard(title: "Your data") {
                SettingsRow(title: "Data folder", subtitle: DataFile.folder.path) {
                    Button("Show in Finder") { NSWorkspace.shared.open(DataFile.folder) }
                }
                Divider()
                Text("Clipboard history, tray, notes, to-dos, timers and scripts are stored here. Settings live in the app's preferences. Nothing is uploaded.")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
            }
        }
    }
}
