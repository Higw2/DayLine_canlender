import Foundation

public enum TimelineLayout {
    public static let dayMinutes = 1440
    public static let pixelsPerMinute: CGFloat = 1
    public static let minimumCardHeight: CGFloat = 32
    public static let selectionStep = 15

    public struct Clipped: Sendable { public let event: CalendarEvent; public let start: Date; public let end: Date }
    public struct Placement: Identifiable, Sendable { public let event: CalendarEvent; public let start: Date; public let end: Date; public let column: Int; public let columns: Int; public var id: Int64 { event.id } }

    public static func minute(_ date: Date, on day: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: day)
        let following = calendar.date(byAdding: .day, value: 1, to: start)!
        if date >= following { return dayMinutes }
        if date <= start { return 0 }
        // The visual grid is always 24 wall-clock hours, including DST days.
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return max(0, min(dayMinutes, (parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
    }
    public static func clip(_ event: CalendarEvent, to day: Date, calendar: Calendar = .current) -> Clipped? {
        let start = calendar.startOfDay(for: day); let end = calendar.date(byAdding: .day, value: 1, to: start)!
        guard event.startsAt < end && event.endsAt > start else { return nil }
        return Clipped(event: event, start: max(event.startsAt, start), end: min(event.endsAt, end))
    }
    public static func placements(_ events: [CalendarEvent], on day: Date, calendar: Calendar = .current) -> [Placement] {
        let items = events.compactMap { clip($0, to: day, calendar: calendar) }.sorted {
            $0.start == $1.start ? ($0.end == $1.end ? $0.event.id < $1.event.id : $0.end < $1.end) : $0.start < $1.start
        }
        var answer: [Placement] = []; var index = 0
        func visualEnd(_ item: Clipped) -> Date { max(item.end, item.start.addingTimeInterval(TimeInterval(minimumCardHeight * 60))) }
        while index < items.count {
            var group = [items[index]]; var groupEnd = visualEnd(items[index]); index += 1
            while index < items.count && items[index].start < groupEnd { group.append(items[index]); groupEnd = max(groupEnd, visualEnd(items[index])); index += 1 }
            var active: [(Date, Int)] = []; var available: [Int] = []; var next = 0; var assigned: [(Clipped, Int)] = []
            for item in group {
                active.sort { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
                while let first = active.first, first.0 <= item.start { available.append(first.1); active.removeFirst() }
                available.sort(); let column = available.isEmpty ? next : available.removeFirst(); if column == next { next += 1 }
                active.append((visualEnd(item), column)); assigned.append((item, column))
            }
            answer += assigned.map { Placement(event: $0.0.event, start: $0.0.start, end: $0.0.end, column: $0.1, columns: next) }
        }
        return answer
    }
    public static func selection(from firstY: CGFloat, to secondY: CGFloat) -> (Int, Int) {
        let first = max(0, min(CGFloat(dayMinutes), firstY / pixelsPerMinute)); let second = max(0, min(CGFloat(dayMinutes), secondY / pixelsPerMinute))
        var start = Int(floor(min(first, second) / CGFloat(selectionStep))) * selectionStep
        var end = Int(ceil(max(first, second) / CGFloat(selectionStep))) * selectionStep
        start = min(start, dayMinutes - selectionStep); end = min(dayMinutes, max(end, start + selectionStep)); return (start, end)
    }
    public static func timeText(_ minute: Int) -> String { minute == dayMinutes ? "24:00" : String(format: "%02d:%02d", minute / 60, minute % 60) }
}
