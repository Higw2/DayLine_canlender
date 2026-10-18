import XCTest
@testable import DayLineCore

final class TimelineResizeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
    private func date(_ hour: Int, _ minute: Int) -> Date { date(18, hour, minute) }
    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func event(start: Date? = nil, end: Date? = nil) -> CalendarEvent {
        CalendarEvent(id: 1, title: "拖拽事件", startsAt: start ?? date(9, 0), endsAt: end ?? date(10, 0), notes: "保留备注")
    }
    private func resize(_ event: CalendarEvent, _ edge: TimelineLayout.ResizeEdge, _ delta: CGFloat) throws -> DateInterval {
        try XCTUnwrap(TimelineLayout.resizedInterval(event, edge: edge, on: date(0, 0), deltaY: delta, calendar: calendar))
    }

    func testEachEdgeSnapsToQuarterHourAndPreservesOppositeEndpoint() throws {
        let event = event()
        let laterStart = try resize(event, .start, 19)
        XCTAssertEqual(laterStart.start, date(9, 15)); XCTAssertEqual(laterStart.end, event.endsAt)
        XCTAssertEqual(try resize(event, .start, -19).start, date(8, 45))
        let laterEnd = try resize(event, .end, 23)
        XCTAssertEqual(laterEnd.start, event.startsAt); XCTAssertEqual(laterEnd.end, date(10, 30))
        XCTAssertEqual(try resize(event, .end, -23).end, date(9, 30))
    }

    func testCrossingOtherEdgeKeepsAtLeastFifteenMinutes() throws {
        let event = event()
        XCTAssertEqual(try resize(event, .start, 300).start, date(9, 45))
        XCTAssertEqual(try resize(event, .end, -300).end, date(9, 15))
        let unaligned = self.event(start: date(9, 7), end: date(10, 4))
        XCTAssertEqual(try resize(unaligned, .start, 300).start, date(9, 45))
        XCTAssertEqual(try resize(unaligned, .end, -300).end, date(9, 30))
    }

    func testDayLimitsAndMidnightEnd() throws {
        let event = event()
        XCTAssertEqual(try resize(event, .start, -10_000).start, date(0, 0))
        XCTAssertEqual(try resize(event, .end, 10_000).end, date(19, 0, 0))
        XCTAssertEqual(TimelineLayout.date(atMinute: 1440, on: date(0, 0), calendar: calendar), date(19, 0, 0))
        XCTAssertEqual(TimelineLayout.minute(try resize(event, .end, 10_000).end, on: date(0, 0), calendar: calendar), 1440)
        XCTAssertNil(TimelineLayout.resizedInterval(event, edge: .end, on: date(0, 0), deltaY: .infinity, calendar: calendar))
    }

    func testClippedCrossDayEdgesCannotChangeHiddenEndpoints() throws {
        let overnight = event(start: date(17, 23, 0), end: date(1, 0))
        XCTAssertFalse(TimelineLayout.canResize(overnight, edge: .start, on: date(0, 0), calendar: calendar))
        XCTAssertNil(TimelineLayout.resizedInterval(overnight, edge: .start, on: date(0, 0), deltaY: 30, calendar: calendar))
        XCTAssertEqual(try resize(overnight, .end, 30), DateInterval(start: overnight.startsAt, end: date(1, 30)))
        let nextDay = event(start: date(23, 0), end: date(19, 1, 0))
        XCTAssertFalse(TimelineLayout.canResize(nextDay, edge: .end, on: date(0, 0), calendar: calendar))
        XCTAssertEqual(try resize(nextDay, .start, -30).end, nextDay.endsAt)
        let midnightEnd = event(start: date(23, 0), end: date(19, 0, 0))
        XCTAssertTrue(TimelineLayout.canResize(midnightEnd, edge: .end, on: date(0, 0), calendar: calendar))
    }

    func testShortVisualCardUsesMovementRelativeToActualEndpoint() throws {
        let short = event(start: date(9, 0), end: date(9, 5))
        let range = try resize(short, .end, 15)
        XCTAssertEqual(range.start, short.startsAt)
        XCTAssertEqual(range.end, date(9, 15))
    }

    func testWallClockSnapOnDaylightSavingDay() throws {
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let start = calendar.date(bySettingHour: 1, minute: 0, second: 0, of: day)!
        let end = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: day)!
        let event = event(start: start, end: end)
        let range = try XCTUnwrap(TimelineLayout.resizedInterval(event, edge: .end, on: day, deltaY: 30, calendar: calendar))
        XCTAssertEqual(calendar.component(.hour, from: range.end), 4)
        XCTAssertEqual(calendar.component(.minute, from: range.end), 30)
        XCTAssertEqual(range.start, start)
    }

    func testResizedEventPersistsMetadataAndRearmsFutureReminder() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.db")
        let store = try EventStore(path: path)
        let event = try store.add(title: "标题保留", startsAt: date(9, 0), endsAt: date(10, 0), notes: "备注保留", now: date(8, 0))
        _ = try store.takeReminders(now: date(8, 55))
        let range = try resize(event, .start, 30)
        let updated = try store.update(id: event.id, title: event.title, startsAt: range.start, endsAt: range.end, notes: event.notes, now: date(8, 56))
        XCTAssertEqual(updated.id, event.id); XCTAssertEqual(updated.title, event.title); XCTAssertEqual(updated.notes, event.notes)
        XCTAssertFalse(updated.completed); XCTAssertNil(updated.preAlertedAt); XCTAssertNil(updated.alertedAt)
        XCTAssertEqual(try EventStore(path: path).get(event.id), updated)
        XCTAssertTrue(try store.takeReminders(now: date(8, 57)).isEmpty)
        XCTAssertEqual(try store.takeReminders(now: date(9, 25)).map(\.stage), [.advance])
    }

    func testDueNotificationsNeverRequestAnActionPanel() {
        XCTAssertTrue(ReminderStage.advance.presentsPanel)
        XCTAssertFalse(ReminderStage.due.presentsPanel)
    }
}
