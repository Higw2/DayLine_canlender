import XCTest
@testable import DayLineCore
@testable import DayLineApp

final class WeekTimelineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1 // The weekly timeline must still start Monday.
        return calendar
    }
    private func date(_ year: Int = 2026, _ month: Int = 11, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    private func withStore(_ operation: (EventStore, URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(EventStore(path: directory.appendingPathComponent("events.db")), directory)
    }

    func testWeekIsMondayThroughSundayForEverySelectedDay() {
        let expected = (16...22).map { date(day: $0) }
        for day in 16...22 {
            XCTAssertEqual(WeekTimelineLayout.days(containing: date(day: day, hour: 15), calendar: calendar), expected)
            XCTAssertEqual(WeekTimelineLayout.interval(containing: date(day: day), calendar: calendar), DateInterval(start: expected[0], end: date(day: 23)))
        }
    }

    func testCrossMonthYearAndLeapDayWeeks() {
        let newYear = WeekTimelineLayout.days(containing: date(2027, 1, day: 1), calendar: calendar)
        XCTAssertEqual(newYear.first, date(2026, 12, day: 28)); XCTAssertEqual(newYear.last, date(2027, 1, day: 3))
        let leap = WeekTimelineLayout.days(containing: date(2024, 2, day: 29), calendar: calendar)
        XCTAssertEqual(leap.first, date(2024, 2, day: 26)); XCTAssertEqual(leap.last, date(2024, 3, day: 3))
    }

    func testDSTWeekUsesCalendarDaysRatherThanFixedSeconds() {
        let week = WeekTimelineLayout.interval(containing: date(2026, 3, day: 8), calendar: calendar)
        XCTAssertEqual(week.start, date(2026, 3, day: 2)); XCTAssertEqual(week.end, date(2026, 3, day: 9))
        XCTAssertEqual(week.duration, 7 * 86_400 - 3600)
        XCTAssertEqual(WeekTimelineLayout.days(containing: week.start, calendar: calendar).count, 7)
    }

    func testStoreLoadsWholeWeekOnceAndClipsOutsideBoundaries() throws {
        try withStore { store, _ in
            let old = date(day: 1)
            func add(_ title: String, _ start: Date, _ end: Date) throws -> CalendarEvent {
                try store.add(title: title, startsAt: start, endsAt: end, now: old)
            }
            let monday = try add("周一", date(day: 16, hour: 9), date(day: 16, hour: 10))
            let sunday = try add("周日", date(day: 22, hour: 20), date(day: 22, hour: 21))
            let incoming = try add("上周跨入", date(day: 15, hour: 23), date(day: 16, hour: 1))
            let outgoing = try add("本周跨出", date(day: 22, hour: 23), date(day: 23, hour: 1))
            let spanning = try add("贯穿一周", date(day: 15, hour: 22), date(day: 23, hour: 2))
            _ = try add("恰好本周前结束", date(day: 15, hour: 22), date(day: 16))
            _ = try add("下周开始", date(day: 23), date(day: 23, hour: 1))
            let events = try store.events(inWeekContaining: date(day: 18), calendar: calendar)
            XCTAssertEqual(Set(events.map(\.id)), Set([monday.id, sunday.id, incoming.id, outgoing.id, spanning.id]))
            XCTAssertEqual(events.count, 5)
            let days = WeekTimelineLayout.days(containing: date(day: 18), calendar: calendar)
            XCTAssertEqual(days.filter { TimelineLayout.clip(spanning, to: $0, calendar: calendar) != nil }.count, 7)
        }
    }

    func testOverlapOnlyWidensWithinSameDayAndWeeklyWidthRemainsUsable() {
        let monday = CalendarEvent(id: 1, title: "周一", startsAt: date(day: 16, hour: 9), endsAt: date(day: 16, hour: 10))
        let tuesday = CalendarEvent(id: 2, title: "周二", startsAt: date(day: 17, hour: 9), endsAt: date(day: 17, hour: 10))
        let overlap = CalendarEvent(id: 3, title: "周一重叠", startsAt: date(day: 16, hour: 9, minute: 30), endsAt: date(day: 16, hour: 11))
        let days = WeekTimelineLayout.days(containing: date(day: 18), calendar: calendar)
        let normal = WeekTimelineLayout.columnWidth(availableWidth: 904, events: [monday, tuesday], days: days, calendar: calendar)
        XCTAssertEqual(normal, 120)
        let wide = WeekTimelineLayout.columnWidth(availableWidth: 904, events: [monday, tuesday, overlap], days: days, calendar: calendar)
        XCTAssertGreaterThan(wide, normal)
        XCTAssertEqual(TimelineLayout.placements([monday, tuesday, overlap], on: days[1], calendar: calendar).map(\.columns), [1])
        XCTAssertGreaterThanOrEqual(WeekTimelineLayout.columnWidth(availableWidth: 320, events: [], days: days), 92)
        XCTAssertGreaterThan(WeekTimelineLayout.columnWidth(availableWidth: 320, events: [], days: days, fontScale: 1.3), 92)
    }

    @MainActor func testModelLoadsWeekAndNavigatesExactlySevenDays() async throws {
        try withStore { store, directory in
            let model = DayLineModel(store: store, settingsStore: SettingsStore(path: directory.appendingPathComponent("settings.json")))
            let selected = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18))!
            let days = WeekTimelineLayout.days(containing: selected)
            let first = try store.add(title: "周首", startsAt: TimelineLayout.date(atMinute: 540, on: days[0]), endsAt: TimelineLayout.date(atMinute: 600, on: days[0]))
            let last = try store.add(title: "周末", startsAt: TimelineLayout.date(atMinute: 540, on: days[6]), endsAt: TimelineLayout.date(atMinute: 600, on: days[6]))
            model.selectedDay = selected; model.reload()
            XCTAssertEqual(Set(model.events.map(\.id)), Set([first.id, last.id]))
            model.go(7)
            XCTAssertEqual(model.selectedDay, Calendar.current.date(byAdding: .day, value: 7, to: selected))
            XCTAssertTrue(model.events.isEmpty)
            model.go(-7)
            XCTAssertEqual(Set(model.events.map(\.id)), Set([first.id, last.id]))
        }
    }

    @MainActor func testSavingAndResizingInAnotherDayPreservesWeeklyEventSet() async throws {
        try withStore { store, directory in
            let model = DayLineModel(store: store, settingsStore: SettingsStore(path: directory.appendingPathComponent("settings.json")))
            let days = WeekTimelineLayout.days(containing: Date())
            model.selectedDay = days[0]
            let start = TimelineLayout.date(atMinute: 540, on: days[4]), end = TimelineLayout.date(atMinute: 600, on: days[4])
            model.presentNewEvent((start, end))
            XCTAssertTrue(model.save(title: "周五事件", start: start, end: end, notes: "备注"))
            let event = try XCTUnwrap(model.events.first)
            XCTAssertEqual(event.startsAt, start)
            let range = DateInterval(start: start, end: end.addingTimeInterval(1800))
            model.resize(event, to: range)
            XCTAssertEqual(model.events.first?.endsAt, range.end)
            XCTAssertEqual(try store.get(event.id)?.notes, "备注")
            model.delete(try XCTUnwrap(model.events.first))
            XCTAssertTrue(model.events.isEmpty)
        }
    }
}
