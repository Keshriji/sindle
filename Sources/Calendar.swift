import SwiftUI
import AppKit
import EventKit

struct CalEvent: Identifiable {
    let id = UUID()
    let title: String
    let start: Date
    let colour: Color
}

/// Reads the next week of events from Calendar. Access is requested once, when the page is first opened.
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()
    @Published var events: [CalEvent] = []
    @Published var status = "Calendar access is off"
    private let store = EKEventStore()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        request()
    }

    private func request() {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                self.status = granted ? "" : "Allow Calendar access in System Settings"
                if granted { self.load() }
            }
        }
    }

    func load() {
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let found = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
        events = found.map { e in
            CalEvent(title: e.title ?? "Event", start: e.startDate, colour: Self.colour(e.calendar))
        }
        status = events.isEmpty ? "No events this week" : ""
    }

    private static func colour(_ c: EKCalendar?) -> Color {
        guard let cg = c?.cgColor, let ns = NSColor(cgColor: cg) else { return .white }
        return Color(nsColor: ns)
    }
}

struct CalendarPage: View {
    @ObservedObject var calendar = CalendarStore.shared
    private let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f }()
    private let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Label("Calendar", systemImage: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { calendar.load() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }.buttonStyle(.plain)
            }
            .foregroundStyle(.white.opacity(0.7))

            if calendar.events.isEmpty {
                Text(calendar.status)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(calendar.events) { e in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(e.colour).frame(width: 3, height: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text("\(day.string(from: e.start)) · \(time.string(from: e.start))")
                                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()
                            }
                            .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { calendar.start() }
    }
}
