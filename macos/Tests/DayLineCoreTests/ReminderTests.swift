import XCTest
import CSQLite
@testable import DayLineCore

final class ReminderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func withStore(_ operation: (EventStore, URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.db")
        try operation(EventStore(path: path), path)
    }
    private func add(_ store: EventStore, start: Date? = nil) throws -> CalendarEvent {
        let start = start ?? self.start
        return try store.add(title: "两阶段提醒", startsAt: start, endsAt: start.addingTimeInterval(3600), now: start.addingTimeInterval(-3600))
    }

    func testAdvanceAndDueAreIndependentAndEachDeliveredOnceAcrossReopen() throws {
        try withStore { store, path in
            let event = try add(store)
            XCTAssertTrue(try store.takeReminders(now: start.addingTimeInterval(-301)).isEmpty)
            let early = try store.takeReminders(now: start.addingTimeInterval(-300))
            XCTAssertEqual(early.map(\.stage), [.advance]); XCTAssertEqual(early.map(\.event.id), [event.id])
            XCTAssertNotNil(try store.get(event.id)?.preAlertedAt)
            XCTAssertNil(try store.get(event.id)?.alertedAt)
            let reopened = try EventStore(path: path)
            XCTAssertTrue(try reopened.takeReminders(now: start.addingTimeInterval(-299)).isEmpty)
            XCTAssertTrue(try reopened.takeReminders(now: start.addingTimeInterval(-1)).isEmpty)
            XCTAssertEqual(try reopened.takeReminders(now: start).map(\.stage), [.due])
            XCTAssertNotNil(try reopened.get(event.id)?.alertedAt)
            XCTAssertTrue(try EventStore(path: path).takeReminders(now: start.addingTimeInterval(3)).isEmpty)
        }
    }

    func testStartingAfterEventTimeOnlyDeliversDueAndKeepsStalePolicy() throws {
        try withStore { store, _ in
            let current = try add(store)
            let boundary = try add(store, start: start.addingTimeInterval(-86_400))
            let stale = try add(store, start: start.addingTimeInterval(-86_401))
            let deliveries = try store.takeReminders(now: start)
            XCTAssertEqual(deliveries.map(\.event.id), [boundary.id, current.id])
            XCTAssertEqual(deliveries.map(\.stage), [.due, .due])
            XCTAssertNil(try store.get(current.id)?.preAlertedAt)
            XCTAssertNotNil(try store.get(stale.id)?.alertedAt)
            XCTAssertTrue(try store.takeReminders(now: start.addingTimeInterval(1)).isEmpty)
        }
    }

    func testSnoozeRepeatsOnlyDueAtTenMinutesAndCompletionCancelsPendingSnooze() throws {
        try withStore { store, path in
            let event = try add(store)
            _ = try store.takeReminders(now: start.addingTimeInterval(-300))
            _ = try store.takeReminders(now: start)
            try store.snooze(event.id, now: start)
            let reopened = try EventStore(path: path)
            XCTAssertTrue(try reopened.takeReminders(now: start.addingTimeInterval(599)).isEmpty)
            let later = try reopened.takeReminders(now: start.addingTimeInterval(600))
            XCTAssertEqual(later.map(\.stage), [.due])
            XCTAssertEqual(later.first?.event.reminderAt, start.addingTimeInterval(600))
            try reopened.snooze(event.id, now: start.addingTimeInterval(600))
            try reopened.complete(event.id, now: start.addingTimeInterval(601))
            XCTAssertNil(try reopened.get(event.id)?.reminderAt)
            XCTAssertTrue(try EventStore(path: path).takeReminders(now: start.addingTimeInterval(1200)).isEmpty)
        }
    }

    func testEditsPreserveAdvanceAcknowledgementButReschedulingRearmsBothStages() throws {
        try withStore { store, _ in
            let event = try add(store)
            let now = start.addingTimeInterval(-300)
            _ = try store.takeReminders(now: now)
            let stamp = try store.get(event.id)?.preAlertedAt
            _ = try store.update(id: event.id, title: "改名和备注", startsAt: start, endsAt: event.endsAt, notes: "内容", now: now)
            XCTAssertEqual(try store.get(event.id)?.preAlertedAt, stamp)
            XCTAssertTrue(try store.takeReminders(now: now).isEmpty)
            _ = try store.update(id: event.id, title: "只改结束时间", startsAt: start, endsAt: event.endsAt.addingTimeInterval(600), now: now)
            XCTAssertEqual(try store.get(event.id)?.preAlertedAt, stamp)
            _ = try store.takeReminders(now: start)
            let newStart = start.addingTimeInterval(3600)
            let changed = try store.update(id: event.id, title: "改期", startsAt: newStart, endsAt: newStart.addingTimeInterval(3600), now: start)
            XCTAssertNil(changed.preAlertedAt); XCTAssertNil(changed.alertedAt); XCTAssertNil(changed.reminderAt)
            XCTAssertTrue(try store.takeReminders(now: start).isEmpty)
            XCTAssertEqual(try store.takeReminders(now: newStart.addingTimeInterval(-300)).map(\.stage), [.advance])
            XCTAssertEqual(try store.takeReminders(now: newStart).map(\.stage), [.due])
        }
    }

    func testCompletedDeletedAndHistoricalEventsDoNotRemindAndRestoreRearms() throws {
        try withStore { store, _ in
            let event = try add(store)
            let deleted = try add(store)
            try store.delete(deleted.id)
            _ = try store.add(title: "新建过去事件", startsAt: start.addingTimeInterval(-3600), endsAt: start, now: start)
            _ = try store.takeReminders(now: start.addingTimeInterval(-300))
            try store.complete(event.id, now: start.addingTimeInterval(-290))
            XCTAssertTrue(try store.takeReminders(now: start.addingTimeInterval(-280)).isEmpty)
            try store.complete(event.id, completed: false, now: start.addingTimeInterval(-270))
            XCTAssertEqual(try store.takeReminders(now: start.addingTimeInterval(-260)).map(\.stage), [.advance])
            try store.complete(event.id, completed: false, now: start.addingTimeInterval(-255))
            XCTAssertTrue(try store.takeReminders(now: start.addingTimeInterval(-254)).isEmpty)
            try store.complete(event.id, now: start.addingTimeInterval(-250))
            XCTAssertTrue(try store.takeReminders(now: start).isEmpty)
        }
    }

    func testConfigurableLeadTimeAndEventsCreatedInsideAdvanceWindow() throws {
        try withStore { store, _ in
            let event = try add(store)
            XCTAssertTrue(try store.takeReminders(advanceMinutes: 5, now: start.addingTimeInterval(-600)).isEmpty)
            XCTAssertEqual(try store.takeReminders(advanceMinutes: 10, now: start.addingTimeInterval(-600)).map(\.stage), [.advance])
            XCTAssertTrue(try store.takeReminders(advanceMinutes: 30, now: start.addingTimeInterval(-500)).isEmpty)
            let justCreated = try store.add(title: "临近开始时创建", startsAt: start, endsAt: event.endsAt, now: start.addingTimeInterval(-120))
            XCTAssertEqual(try store.takeReminders(now: start.addingTimeInterval(-120)).map(\.event.id), [justCreated.id])
            XCTAssertTrue(try store.advanceDue(minutes: 0, now: start.addingTimeInterval(-60)).isEmpty)
            XCTAssertEqual(try store.takeReminders(now: start).map(\.stage), [.due, .due])
        }
    }

    func testLegacyDatabaseMigrationPreservesEventsNotesAndReminderState() throws {
        try withStore { store, path in
            let event = try add(store)
            try store.snooze(event.id, now: start)
            let note = try store.addNote(body: "已有便笺")
            var db: OpaquePointer?
            XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
            defer { sqlite3_close(db) }
            // Recreate the exact legacy events schema without the new column.
            let sql = """
                DROP INDEX idx_events_advance;
                ALTER TABLE events DROP COLUMN pre_alerted_at;
                """
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
            let migrated = try EventStore(path: path)
            XCTAssertEqual(try migrated.get(event.id)?.reminderAt, start.addingTimeInterval(600))
            XCTAssertNil(try migrated.get(event.id)?.preAlertedAt)
            XCTAssertEqual(try migrated.getNote(note.id), note)
            XCTAssertEqual(try migrated.takeReminders(now: start.addingTimeInterval(600)).map(\.stage), [.due])
        }
    }

    func testAdvanceReminderSettingsDefaultInvalidAndRoundTrip() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        for contents in ["{}", "{\"advance_reminder_minutes\":0}", "{\"advance_reminder_minutes\":999}", "{\"advance_reminder_minutes\":\"bad\"}"] {
            try Data(contents.utf8).write(to: path)
            XCTAssertEqual(SettingsStore(path: path).current.advanceReminderInterval, .fiveMinutes)
        }
        let store = SettingsStore(path: path)
        var settings = store.current
        settings.advanceReminderInterval = .fifteenMinutes
        try store.save(settings)
        XCTAssertEqual(SettingsStore(path: path).current.advanceReminderInterval, .fifteenMinutes)
    }
}
