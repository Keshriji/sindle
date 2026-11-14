import SwiftUI
import AppKit

/// Everything the island's tool pages need: file tray, notes, tasks, alarm and counter.
final class Tools {
    let tray = TrayStore(), notes = NotesStore(), tasks = TaskStore(), clock = ClockStore()
    let typing = TypingStore(), diary = DiaryStore(), mini = MiniStore()
    func start() { tray.start(); clock.start(); typing.start(); mini.start() }
}

// MARK: Tray (drop files in, or copy files in Finder; drag them out again)
final class TrayStore: ObservableObject {
    @Published var items: [URL] = []
    private var last = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.check() }
    }
    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != last else { return }
        last = pb.changeCount
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL] { add(urls) }
    }
    func add(_ urls: [URL]) {
        for u in urls where !items.contains(u) { items.insert(u, at: 0) }
        items = Array(items.prefix(12))
    }
    func remove(_ u: URL) { items.removeAll { $0 == u } }
}

struct TrayPage: View {
    @ObservedObject var tray: TrayStore
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            if tray.items.isEmpty {
                Text("Drop files here, or copy files in Finder")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(tray.items, id: \.self) { u in
                            VStack(spacing: 3) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 38, height: 38)
                                Text(u.lastPathComponent).font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.7)).lineLimit(1).frame(width: 56)
                            }
                            .onDrag { NSItemProvider(object: u as NSURL) }      // drag back out
                            .contextMenu {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                                Button("Remove") { tray.remove(u) }
                            }
                        }
                    }.padding(10)
                }
            }
        }
    }
}

// MARK: Notes
final class NotesStore: ObservableObject {
    @Published var text: String { didSet { UserDefaults.standard.set(text, forKey: "spindle.notes") } }
    init() { text = UserDefaults.standard.string(forKey: "spindle.notes") ?? "" }
}

struct NotesPage: View {
    @ObservedObject var notes: NotesStore
    var body: some View {
        TextEditor(text: $notes.text)
            .scrollContentBackground(.hidden).font(.system(size: 12)).foregroundStyle(.white)
            .padding(6).background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))
    }
}

// MARK: Tasks
struct TaskItem: Codable, Identifiable { var id = UUID(); var title: String; var done = false }

final class TaskStore: ObservableObject {
    @Published var items: [TaskItem] { didSet {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: "spindle.tasks") } }
    init() {
        let d = UserDefaults.standard.data(forKey: "spindle.tasks")
        items = d.flatMap { try? JSONDecoder().decode([TaskItem].self, from: $0) } ?? []
    }
}

struct TasksPage: View {
    @ObservedObject var tasks: TaskStore
    @State private var draft = ""
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                TextField("New task", text: $draft).textFieldStyle(.plain).font(.system(size: 12))
                    .foregroundStyle(.white).onSubmit(add)
                Button(action: add) { Image(systemName: "plus.circle.fill").foregroundStyle(.white) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.12)))
            ScrollView {
                VStack(spacing: 5) {
                    ForEach($tasks.items) { $t in
                        HStack(spacing: 8) {
                            Button { withAnimation(.spring(response: 0.3)) { t.done.toggle() } } label: {
                                Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                            }.buttonStyle(.plain)
                            Text(t.title).strikethrough(t.done).opacity(t.done ? 0.4 : 1).lineLimit(1)
                            Spacer()
                            Button { tasks.items.removeAll { $0.id == t.id } } label: {
                                Image(systemName: "xmark").font(.system(size: 9))
                            }.buttonStyle(.plain).opacity(0.5)
                        }.font(.system(size: 12)).foregroundStyle(.white)
                    }
                }
            }
        }
    }
    private func add() {
        let s = draft.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        withAnimation(.spring(response: 0.3)) { tasks.items.insert(TaskItem(title: s), at: 0) }
        draft = ""
    }
}

// MARK: Alarm + counter
final class ClockStore: ObservableObject {
    @Published var alarmOn = false
    @Published var alarmTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @Published var count = 0
    var onRing: (() -> Void)?
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }
    private func tick() {
        guard alarmOn else { return }
        let c = Calendar.current
        let n = c.dateComponents([.hour, .minute], from: Date()), a = c.dateComponents([.hour, .minute], from: alarmTime)
        if n.hour == a.hour && n.minute == a.minute {
            alarmOn = false                                   // one-shot
            for i in 0..<4 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8) { NSSound(named: "Glass")?.play() } }
            onRing?()
        }
    }
}

struct ClockPage: View {
    @ObservedObject var clock: ClockStore
    @ObservedObject var s = SettingsStore.shared
    private var design: Font.Design { [Font.Design.rounded, .serif, .monospaced][min(max(s.clockFont, 0), 2)] }
    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 6) {
                Label("Alarm", systemImage: "alarm.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                DatePicker("", selection: $clock.alarmTime, displayedComponents: .hourAndMinute)
                    .labelsHidden().colorScheme(.dark)
                Toggle("", isOn: $clock.alarmOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Rectangle().fill(.white.opacity(0.15)).frame(width: 1)
            VStack(spacing: 4) {
                Text("Counter").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                Text("\(clock.count)").font(.system(size: 30, weight: .semibold, design: design))
                    .foregroundStyle(.white).contentTransition(.numericText())
                HStack(spacing: 14) {
                    step("minus") { clock.count -= 1 }
                    step("plus") { clock.count += 1 }
                    step("arrow.counterclockwise") { clock.count = 0 }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func step(_ icon: String, _ f: @escaping () -> Void) -> some View {
        Button { withAnimation(.spring(response: 0.3)) { f() } } label: {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Circle().fill(.white.opacity(0.15)))
        }.buttonStyle(.plain)
    }
}
