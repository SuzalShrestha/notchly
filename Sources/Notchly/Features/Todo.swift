import SwiftUI

// MARK: - Model (research/SPEC.md data model)

struct TodoItem: Codable, Identifiable, Equatable {
    var taskUUID = UUID()
    var title: String
    var notes = ""
    var isCompleted = false
    var isPriority = false
    var storedFocusDurationMinutes: Int? = 25
    var scheduledDate: Date?
    var sortOrder = 0
    var createdAt = Date()
    var id: UUID { taskUUID }
}

struct TodoCompletionEvent: Codable, Equatable {
    var taskUUID: UUID
    var completedAt: Date
}

enum TodoActivityBlockSize: String, Codable, CaseIterable { case small, medium, large }

enum TodoActivityCompletionColor: String, Codable, CaseIterable {
    case green, blue, purple, orange, pink
    var color: Color {
        switch self {
        case .green: Theme.green
        case .blue: Theme.blue
        case .purple: Color(nsColor: .systemPurple)
        case .orange: Theme.accent
        case .pink: Color(nsColor: .systemPink)
        }
    }
}

struct TodoListWidgetSettings: Codable, Equatable {
    var showCompleted = true
    var activityBlockSize: TodoActivityBlockSize = .medium
    var activityCompletionColor: TodoActivityCompletionColor = .green
}

// MARK: - Store (todos.json)

@MainActor @Observable
final class TodoStore {
    static let shared = TodoStore()
    static let settings = Setting("todoListWidgetSettings", default: TodoListWidgetSettings())

    private struct File: Codable { var items: [TodoItem]; var completions: [TodoCompletionEvent] }
    private(set) var items: [TodoItem]
    private(set) var completions: [TodoCompletionEvent]

    init() {
        let f = DataFile.load("todos.json", as: File.self)
        items = f?.items ?? []
        completions = f?.completions ?? []
    }

    var visible: [TodoItem] {
        let show = Self.settings.value.showCompleted
        return items.filter { show || !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func add(_ title: String) {
        items.append(TodoItem(title: title, sortOrder: (items.map(\.sortOrder).max() ?? 0) + 1))
        save()
    }

    func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isCompleted.toggle()
        if items[i].isCompleted {
            completions.append(TodoCompletionEvent(taskUUID: id, completedAt: .now))
        } else if let j = completions.lastIndex(where: { $0.taskUUID == id }) {
            completions.remove(at: j)
        }
        save()
    }

    func setFocus(_ id: UUID, minutes: Int?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].storedFocusDurationMinutes = minutes
        save()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    private func save() { DataFile.save(File(items: items, completions: completions), to: "todos.json") }

    /// Completions per day as `weeks` columns × 7 weekday rows, last column = this week; days after `today` are -1.
    static func activityGrid(_ events: [TodoCompletionEvent], today: Date, weeks: Int, calendar: Calendar = .current) -> [[Int]] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        let first = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!
        let dayIndex = { (d: Date) in calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: d)).day! }
        let todayIndex = dayIndex(today)
        var grid = (0..<weeks).map { w in (0..<7).map { w * 7 + $0 > todayIndex ? -1 : 0 } }
        for e in events {
            let i = dayIndex(e.completedAt)
            if i >= 0 && i <= todayIndex && i < weeks * 7 { grid[i / 7][i % 7] += 1 }
        }
        return grid
    }

    static func selfTest() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1
        let today = ISO8601DateFormatter().date(from: "2026-10-28T12:00:00Z")!        // Wednesday
        let day: (Int) -> Date = { today.addingTimeInterval(Double($0) * 86_400) }
        let id = UUID()
        let events = [0, 0, -1, -15, -100, 2].map { TodoCompletionEvent(taskUUID: id, completedAt: day($0)) }
        let g = TodoStore.activityGrid(events, today: today, weeks: 10, calendar: cal)
        precondition(g.count == 10 && g.allSatisfy { $0.count == 7 })
        precondition(g[9][3] == 2 && g[9][2] == 1 && g[9][4] == -1 && g[9][6] == -1)
        precondition(g[7][2] == 1)                                                   // 15 days back: week 7, Tuesday
        precondition(g.flatMap { $0 }.filter { $0 > 0 }.reduce(0, +) == 4)          // -100 and future ignored
        precondition(TodoItem(title: "x").storedFocusDurationMinutes == 25)
    }
}

// MARK: - Nook widget (4 units, todoListWidgetMock.png)

struct TodoWidget: View {
    @Environment(NotchModel.self) private var notch
    @State private var adding = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let items = TodoStore.shared.visible
        WidgetCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("To-dos").font(Theme.title(13)).foregroundStyle(Theme.secondaryText)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items) { TodoRow(item: $0) }
                        if items.isEmpty { Text("All done").font(Theme.caption).foregroundStyle(Theme.tertiaryText) }
                    }
                }
                addField
            }
        }
    }

    private var addField: some View {
        Group {
            if adding {
                TextField("Add a task", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit {
                        let t = draft.trimmingCharacters(in: .whitespaces)
                        if t.isEmpty { adding = false } else { TodoStore.shared.add(t); draft = ""; focused = true }
                    }
                    .onExitCommand { draft = ""; adding = false }
            } else {
                Button { adding = true } label: { Label("Add a task", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(.plain)
            }
        }
        .font(Theme.body.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 10).frame(height: 26)
        .background(Theme.accent.opacity(0.18), in: Capsule())
        .fixedSize(horizontal: !adding, vertical: false)
        .onChange(of: focused) { _, f in
            notch.keyboardPinned = f
            if !f && draft.isEmpty { adding = false }
        }
    }
}

private struct TodoRow: View {
    let item: TodoItem
    var body: some View {
        let store = TodoStore.shared
        let timing = TimerStore.shared.entries.contains { $0.todoTaskID == item.id }
        HStack(spacing: 7) {
            Button { withAnimation(Motion.snappy) { store.toggle(item.id) } } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(item.isCompleted ? Color.black : Theme.accent, Theme.accent)
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(PressableStyle())
            Text(item.title)
                .font(Theme.body.weight(.semibold))
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? Theme.tertiaryText : .white)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let m = item.storedFocusDurationMinutes {
                Button { TimerStore.shared.start(label: item.title, seconds: m * 60, todoTaskID: item.id) } label: {
                    Chip(title: "\(m)m", symbol: timing ? "timer" : nil, tint: timing ? Theme.accent : Theme.secondaryText)
                }
                .buttonStyle(PressableStyle())
                .disabled(item.isCompleted)
                .opacity(item.isCompleted ? 0.4 : 1)
                .help("Start a \(m)-minute focus timer")
            }
        }
        .contextMenu {
            Menu("Focus duration") {
                ForEach([5, 15, 25, 45, 60], id: \.self) { m in Button("\(m) min") { store.setFocus(item.id, minutes: m) } }
                Button("None") { store.setFocus(item.id, minutes: nil) }
            }
            Button("Delete", role: .destructive) { store.delete(item.id) }
        }
    }
}

// MARK: - Activity widget (3 units): completions per day, last 10 weeks

struct TodoActivityWidget: View {
    var body: some View {
        let weeks = 10
        let color = TodoStore.settings.value.activityCompletionColor.color
        let grid = TodoStore.activityGrid(TodoStore.shared.completions, today: .now, weeks: weeks)
        let thisWeek = grid[weeks - 1].filter { $0 > 0 }.reduce(0, +)
        WidgetCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Activity").font(Theme.title(13)).foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
                HStack(spacing: 2.5) {
                    ForEach(0..<weeks, id: \.self) { w in
                        VStack(spacing: 2.5) {
                            ForEach(0..<7, id: \.self) { d in
                                let n = grid[w][d]
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(n < 0 ? .clear : n == 0 ? Color.white.opacity(0.08) : color.opacity(min(1, 0.35 + 0.22 * Double(n - 1))))
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Text("\(thisWeek) done this week").font(Theme.caption).foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}
