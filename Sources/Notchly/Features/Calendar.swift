import EventKit
import SwiftUI

// MARK: - Settings (same key names as NotchNook)

struct CalendarWidgetSettings: Codable, Equatable {
    var shouldShowAllDayEvents = true
    var numberOfDaysAheadToDisplay = 7
    var selectedCalendars: [String] = []            // calendar identifiers; empty = all
}

struct CalendarLiveActivitySettings: Codable, Equatable {
    var preEventWindow = 10                         // minutes
    var onlyEventsWithMeetings = false
}

// MARK: - Meetings

enum VideoConferenceService: String, CaseIterable {
    case googleMeet, zoom, microsoftTeams, webex

    var title: String {
        switch self {
        case .googleMeet: "Meet"
        case .zoom: "Zoom"
        case .microsoftTeams: "Teams"
        case .webex: "Webex"
        }
    }

    init?(host: String) {
        let h = host.lowercased()
        if h == "meet.google.com" { self = .googleMeet }
        else if h == "zoom.us" || h.hasSuffix(".zoom.us") { self = .zoom }
        else if h == "teams.microsoft.com" || h == "teams.live.com" { self = .microsoftTeams }
        else if h == "webex.com" || h.hasSuffix(".webex.com") { self = .webex }
        else { return nil }
    }

    /// First conference link found in the texts (event URL, location, notes).
    static func detect(in texts: [String?]) -> (VideoConferenceService, URL)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap({ $0 }) {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let url = match.url, let host = url.host, let service = VideoConferenceService(host: host) { return (service, url) }
            }
        }
        return nil
    }
}

struct Meeting: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?
    let service: VideoConferenceService?
    let joinURL: URL?

    init(_ e: EKEvent) {
        // Recurring occurrences share an identifier; add the start time.
        id = (e.eventIdentifier ?? UUID().uuidString) + "@\(e.startDate.timeIntervalSince1970)"
        title = e.title?.isEmpty == false ? e.title : "Untitled"
        start = e.startDate
        end = e.endDate
        isAllDay = e.isAllDay
        color = Color(nsColor: e.calendar?.color ?? .systemBlue)
        location = e.location.flatMap { $0.isEmpty || $0.contains("://") ? nil : $0 }
        let link = VideoConferenceService.detect(in: [e.url?.absoluteString, e.location, e.notes])
        service = link?.0
        joinURL = link?.1
    }
}

@MainActor @Observable
final class CalendarService {
    static let shared = CalendarService()
    let store = EKEventStore()
    private(set) var status = EKEventStore.authorizationStatus(for: .event)
    private(set) var events: [Meeting] = []
    var authorized: Bool { status == .fullAccess }

    func start() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarService.shared.reload() }
        }
        // The event window is "today + N days": move it forward at midnight.
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarService.shared.reload() }
        }
        if status == .notDetermined { Task { await requestAccess() } } else { reload() }
    }

    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        status = EKEventStore.authorizationStatus(for: .event)
        reload()
    }

    var calendars: [EKCalendar] { authorized ? store.calendars(for: .event).sorted { $0.title < $1.title } : [] }

    func reload() {
        guard authorized else { events = []; return }
        let s = CalendarFeature.settings.value
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now))!
        let to = cal.date(byAdding: .day, value: s.numberOfDaysAheadToDisplay + 2, to: from)!
        let chosen = s.selectedCalendars.isEmpty ? nil
            : store.calendars(for: .event).filter { s.selectedCalendars.contains($0.calendarIdentifier) }
        if chosen?.isEmpty == true { events = []; return }
        events = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: chosen))
            .filter { s.shouldShowAllDayEvents || !$0.isAllDay }
            .map(Meeting.init)
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    func events(on day: Date) -> [Meeting] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return events.filter { $0.start < end && $0.end > start }
    }

    func add(title: String, start: Date, minutes: Int) throws {
        let e = EKEvent(eventStore: store)
        e.title = title
        e.startDate = start
        e.endDate = start.addingTimeInterval(Double(minutes) * 60)
        e.calendar = store.defaultCalendarForNewEvents
        try store.save(e, span: .thisEvent)
    }
}

// MARK: - Feature entry

@MainActor
enum CalendarFeature {
    static let settings = Setting("calendarWidgetSettings", default: CalendarWidgetSettings())
    static let liveSettings = Setting("calendarLiveActivitySettings", default: CalendarLiveActivitySettings())

    static func start() {
        CalendarService.shared.start()
        WeatherStore.shared.start()
        TimerStore.shared.start()
        Task {
            while !Task.isCancelled {
                updateLiveActivity()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    static func countdown(to start: Date, now: Date = .now) -> String {
        let m = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return m <= 0 ? "now" : "in \(m)m"
    }

    /// Closed-notch wings when a timed event starts within `preEventWindow` minutes.
    static func updateLiveActivity() {
        let ls = liveSettings.value, now = Date()
        guard let next = CalendarService.shared.events.first(where: {
            !$0.isAllDay && $0.start > now && $0.start.timeIntervalSince(now) <= Double(ls.preEventWindow * 60)
                && (!ls.onlyEventsWithMeetings || $0.joinURL != nil)
        }) else { LiveActivityCenter.shared.remove(.calendar); return }
        let leading = HStack(spacing: 5) {
            Circle().fill(next.color).frame(width: 8, height: 8)
            Text(countdown(to: next.start, now: now)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        }
        let trailing = Group {
            if let url = next.joinURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "video.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 18).background(Theme.blue, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            } else {
                Text(next.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
        }
        LiveActivityCenter.shared.show(LiveActivity(kind: .calendar, priority: 30, leadingWidth: 58, trailingWidth: next.joinURL == nil ? 80 : 32,
                                                    leading: AnyView(leading), trailing: AnyView(trailing)))
    }

    static func selfTest() {
        let zoom = VideoConferenceService.detect(in: [nil, "Room 4", "Join: https://us02web.zoom.us/j/123?pwd=x thanks"])
        precondition(zoom?.0 == .zoom && zoom?.1.host == "us02web.zoom.us")
        precondition(VideoConferenceService.detect(in: ["https://meet.google.com/abc-defg-hij"])?.0 == .googleMeet)
        precondition(VideoConferenceService.detect(in: ["<https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0>"])?.0 == .microsoftTeams)
        precondition(VideoConferenceService.detect(in: ["https://acme.webex.com/meet/bob"])?.0 == .webex)
        precondition(VideoConferenceService.detect(in: ["https://example.com/zoom.us", "no link"]) == nil)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        precondition(countdown(to: t0.addingTimeInterval(250), now: t0) == "in 5m")
        precondition(countdown(to: t0.addingTimeInterval(20), now: t0) == "in 1m")
        precondition(countdown(to: t0, now: t0) == "now")
        WeatherStore.selfTest()
        TimerStore.selfTest()
        TodoStore.selfTest()
    }
}

// MARK: - Calendar tab (640 × 200)

struct CalendarTabView: View {
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var composing = false

    var body: some View {
        let svc = CalendarService.shared
        if !svc.authorized {
            CalendarAccessView()
        } else {
            let events = svc.events(on: day)
            HStack(spacing: 10) {
                WidgetCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(day.formatted(.dateTime.month(.wide).year())).font(Theme.title(15))
                            Spacer()
                            RoundButton(symbol: composing ? "xmark" : "plus", size: 26) { withAnimation(Motion.snappy) { composing.toggle() } }
                        }
                        DayStrip(selection: $day)
                        Spacer(minLength: 0)
                        Text(summary(events.count)).font(Theme.caption).foregroundStyle(Theme.tertiaryText)
                    }
                }
                .frame(width: 270)
                WidgetCard {
                    if composing {
                        EventComposer(day: day) { withAnimation(Motion.snappy) { composing = false } }
                    } else if events.isEmpty {
                        EmptyState(symbol: "calendar", title: "No events", subtitle: "Nothing scheduled for this day.")
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 8) { ForEach(events) { AgendaRow(meeting: $0) } }
                        }
                    }
                }
            }
        }
    }

    private func summary(_ n: Int) -> String {
        let name = Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide))
        return "\(name) · \(n == 0 ? "no" : "\(n)") event\(n == 1 ? "" : "s")"
    }
}

private struct DayStrip: View {
    @Binding var selection: Date
    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = (-1...CalendarFeature.settings.value.numberOfDaysAheadToDisplay).map { cal.date(byAdding: .day, value: $0, to: today)! }
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { d in
                        DayCell(day: d, selected: d == selection, count: CalendarService.shared.events(on: d).count)
                            .id(d)
                            .onTapGesture { withAnimation(Motion.snappy) { selection = d } }
                    }
                }
                .padding(.horizontal, 20)
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                         .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, d in withAnimation(Motion.snappy) { proxy.scrollTo(d, anchor: .center) } }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let selected: Bool
    let count: Int
    var body: some View {
        let cal = Calendar.current
        let weekend = cal.isDateInWeekend(day)
        let today = cal.isDateInToday(day)
        VStack(spacing: 3) {
            Text(day.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(weekend ? Theme.weekendPink : Theme.tertiaryText)
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: selected ? 26 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? Theme.blue : today ? Theme.blue.opacity(0.6) : weekend ? Theme.weekendPink : .white)
                .frame(height: 30)
            HStack(spacing: 3) {
                ForEach(0..<min(count, 3), id: \.self) { _ in Circle().fill(Theme.blue).frame(width: 5, height: 5) }
            }
            .frame(height: 5)
        }
        .frame(width: 36)
        .contentShape(Rectangle())
    }
}

private struct AgendaRow: View {
    let meeting: Meeting
    var body: some View {
        let m = meeting
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(m.isAllDay ? "all-day" : m.start.formatted(date: .omitted, time: .shortened)).font(Theme.caption.weight(.semibold))
                if !m.isAllDay {
                    Text(m.end.formatted(date: .omitted, time: .shortened)).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.tertiaryText)
                }
            }
            .frame(width: 62, alignment: .trailing)
            RoundedRectangle(cornerRadius: 1.5).fill(m.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title).font(Theme.body.weight(.semibold)).lineLimit(1)
                if let loc = m.location { Text(loc).font(Theme.caption).foregroundStyle(Theme.tertiaryText).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if let url = m.joinURL, let service = m.service { JoinButton(url: url, service: service) }
        }
        .frame(height: 32)
        .opacity(m.end < .now ? 0.45 : 1)
    }
}

private struct JoinButton: View {
    let url: URL
    let service: VideoConferenceService
    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: { Chip(title: "Join", symbol: "video.fill", fill: Theme.blue) }
            .buttonStyle(PressableStyle())
            .help("Join \(service.title) meeting")
    }
}

private struct EventComposer: View {
    let day: Date
    let done: () -> Void
    @Environment(NotchModel.self) private var notch
    @State private var title = ""
    @State private var start: Date
    @State private var minutes = 30
    @State private var error: String?
    @FocusState private var focused: Bool

    init(day: Date, done: @escaping () -> Void) {
        self.day = day
        self.done = done
        let cal = Calendar.current
        if cal.isDateInToday(day) {   // next half hour
            _start = State(initialValue: Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 1800).rounded(.up) * 1800))
        } else {
            _start = State(initialValue: cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New event · \(day.formatted(.dateTime.weekday(.abbreviated).day().month()))")
                .font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            TextField("Title", text: $title)
                .textFieldStyle(.plain).font(Theme.title(17))
                .focused($focused)
                .onSubmit(save)
            HStack(spacing: 10) {
                DatePicker("", selection: $start, displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.stepperField)
                Picker("", selection: $minutes) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text($0 < 60 ? "\($0) min" : String(format: "%g h", Double($0) / 60)).tag($0) }
                }
                .labelsHidden().frame(width: 90)
            }
            Spacer(minLength: 0)
            HStack {
                if let error { Text(error).font(Theme.caption).foregroundStyle(.red).lineLimit(1) }
                Spacer()
                Button(action: done) { Chip(title: "Cancel") }.buttonStyle(PressableStyle())
                Button(action: save) { Chip(title: "Add", symbol: "plus", fill: Theme.blue) }.buttonStyle(PressableStyle())
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { focused = true }
        .onChange(of: focused) { _, f in notch.keyboardPinned = f }
        .onDisappear { notch.keyboardPinned = false }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        do { try CalendarService.shared.add(title: t, start: start, minutes: minutes); done() }
        catch { self.error = error.localizedDescription }
    }
}

private struct CalendarAccessView: View {
    var body: some View {
        let svc = CalendarService.shared
        WidgetCard {
            VStack(spacing: 10) {
                EmptyState(symbol: "calendar.badge.exclamationmark", title: "Calendar access needed",
                           subtitle: "Notchly shows your events and adds the ones you create.")
                Button {
                    if svc.status == .notDetermined { Task { await svc.requestAccess() } }
                    else { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }
                } label: { Chip(title: svc.status == .notDetermined ? "Allow Access" : "Open System Settings", fill: Theme.blue) }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

// MARK: - Nook widget (4 units)

struct CalendarWidget: View {
    var body: some View {
        let svc = CalendarService.shared
        let cal = Calendar.current
        let now = Date()
        let tomorrowEnd = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
        let upcoming = svc.events.filter { $0.end > now && $0.start < tomorrowEnd }.sorted { $0.start < $1.start }
        WidgetCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(cal.component(.day, from: now))").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.blue)
                    Text(now.formatted(.dateTime.weekday(.wide))).font(Theme.title(13)).foregroundStyle(Theme.secondaryText)
                }
                if !svc.authorized {
                    Text("No calendar access").font(Theme.caption).foregroundStyle(Theme.tertiaryText)
                } else if upcoming.isEmpty {
                    Text("No more events today or tomorrow").font(Theme.caption).foregroundStyle(Theme.tertiaryText)
                } else {
                    ForEach(upcoming.prefix(3)) { m in
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 1.5).fill(m.color).frame(width: 3, height: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(m.title).font(Theme.caption.weight(.semibold)).lineLimit(1)
                                Text(when(m)).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if let url = m.joinURL {
                                Button { NSWorkspace.shared.open(url) } label: {
                                    Image(systemName: "video.fill").font(.system(size: 9, weight: .bold))
                                        .frame(width: 24, height: 18).background(Theme.blue, in: Capsule())
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
            }
        }
    }

    private func when(_ m: Meeting) -> String {
        let day = Calendar.current.isDateInToday(m.start) || m.start < .now ? "" : "Tomorrow "
        return m.isAllDay ? "\(day)all-day".capitalizedFirst : day + m.start.formatted(date: .omitted, time: .shortened)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Settings pane

struct CalendarPane: View {
    var body: some View {
        let svc = CalendarService.shared
        let s = CalendarFeature.settings
        let live = CalendarFeature.liveSettings
        let weather = WeatherStore.settings
        let pomodoro = TimerStore.pomodoro
        let timer = TimerStore.settings
        let todo = TodoStore.settings
        SettingsPane(title: "Calendar & Timers") {
            SettingsCard(title: "Calendars") {
                if !svc.authorized {
                    SettingsRow(title: "Calendar access", subtitle: "Needed to show and add events.") {
                        Button(svc.status == .notDetermined ? "Allow…" : "Open System Settings") {
                            if svc.status == .notDetermined { Task { await svc.requestAccess() } }
                            else { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }
                        }
                    }
                }
                let all = svc.calendars.map(\.calendarIdentifier)
                ForEach(svc.calendars, id: \.calendarIdentifier) { c in
                    SettingsRow(title: c.title, subtitle: c.source?.title) {
                        Toggle("", isOn: Binding(
                            get: { s.value.selectedCalendars.isEmpty || s.value.selectedCalendars.contains(c.calendarIdentifier) },
                            set: { on in
                                var ids = s.value.selectedCalendars.isEmpty ? all : s.value.selectedCalendars
                                ids.removeAll { $0 == c.calendarIdentifier }
                                if on { ids.append(c.calendarIdentifier) }
                                guard !ids.isEmpty else { return }       // keep at least one calendar
                                s.value.selectedCalendars = Set(ids) == Set(all) ? [] : ids
                            })).labelsHidden()
                    }
                    .overlay(alignment: .leading) { Circle().fill(Color(nsColor: c.color)).frame(width: 8, height: 8).offset(x: -11) }
                }
                SettingsRow(title: "Days ahead") {
                    Stepper("\(s.value.numberOfDaysAheadToDisplay)", value: s.binding(\.numberOfDaysAheadToDisplay), in: 1...30)
                }
                SettingsRow(title: "Show all-day events") { Toggle("", isOn: s.binding(\.shouldShowAllDayEvents)).labelsHidden() }
            }
            SettingsCard(title: "Upcoming event live activity") {
                SettingsRow(title: "Show before start", subtitle: "Minutes before the event starts") {
                    Stepper("\(live.value.preEventWindow) min", value: live.binding(\.preEventWindow), in: 1...60)
                }
                SettingsRow(title: "Only events with a meeting link") { Toggle("", isOn: live.binding(\.onlyEventsWithMeetings)).labelsHidden() }
            }
            SettingsCard(title: "Weather") {
                SettingsRow(title: "Location") {
                    Picker("", selection: weather.binding(\.locationMode)) {
                        Text("Current location").tag(WeatherLocationMode.auto)
                        Text("Custom place").tag(WeatherLocationMode.custom)
                    }.labelsHidden().frame(width: 170)
                }
                SettingsRow(title: "Place", subtitle: "Used when location is off or not allowed. Default Cupertino.") {
                    TextField("Cupertino", text: weather.binding(\.customPlace))
                        .frame(width: 170)
                        .onSubmit { WeatherStore.shared.refresh() }
                }
                SettingsRow(title: "Unit") {
                    Picker("", selection: weather.binding(\.unit)) {
                        Text("Automatic").tag(WeatherTemperatureUnit.automatic)
                        Text("Celsius").tag(WeatherTemperatureUnit.celsius)
                        Text("Fahrenheit").tag(WeatherTemperatureUnit.fahrenheit)
                    }.labelsHidden().frame(width: 170)
                }
            }
            SettingsCard(title: "Timer & Pomodoro") {
                SettingsRow(title: "Focus") { Stepper("\(pomodoro.value.focusMinutes) min", value: pomodoro.binding(\.focusMinutes), in: 1...120) }
                SettingsRow(title: "Break") { Stepper("\(pomodoro.value.breakMinutes) min", value: pomodoro.binding(\.breakMinutes), in: 1...120) }
                SettingsRow(title: "Show running timer in the notch") { Toggle("", isOn: pomodoro.binding(\.showInNotch)).labelsHidden() }
                SettingsRow(title: "Play sound when done") { Toggle("", isOn: timer.binding(\.playSound)).labelsHidden() }
                SettingsRow(title: "Sound") {
                    Picker("", selection: timer.binding(\.expirySound)) {
                        ForEach(TimerStore.sounds, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 140)
                    .onChange(of: timer.value.expirySound) { _, name in NSSound(named: name)?.play() }
                }
            }
            SettingsCard(title: "To-dos") {
                SettingsRow(title: "Show completed tasks") { Toggle("", isOn: todo.binding(\.showCompleted)).labelsHidden() }
                SettingsRow(title: "Activity color") {
                    Picker("", selection: todo.binding(\.activityCompletionColor)) {
                        ForEach(TodoActivityCompletionColor.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }.labelsHidden().frame(width: 140)
                }
            }
        }
        .onChange(of: s.value) { CalendarService.shared.reload() }
        .onChange(of: weather.value.locationMode) { WeatherStore.shared.refresh() }
        .onChange(of: pomodoro.value.showInNotch) { TimerStore.shared.updateActivity() }
    }
}
