import XCTest
import CSQLite
@testable import DayLineCore

final class NoteTests: XCTestCase {
    private func withStore(_ operation: (EventStore, URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.db")
        try operation(EventStore(path: path), path)
    }

    func testNoteCRUDPreservesBodyCreationTimeAndReopens() throws {
        try withStore { store, path in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let body = "\n  买牛奶  \n第二行\n"
            let first = try store.addNote(body: body, now: now)
            XCTAssertEqual(first.title, "买牛奶"); XCTAssertEqual(first.body, body); XCTAssertTrue(first.autoTitle)
            XCTAssertEqual(first.createdAt, now)
            let second = try store.addNote(body: "第二条", now: now.addingTimeInterval(60))
            XCTAssertEqual(try store.listNotes().map(\.id), [second.id, first.id])
            let edited = try store.updateNote(first.id, body: "新正文\n更多内容", title: " 自定标题 ", now: now.addingTimeInterval(120))
            XCTAssertEqual(edited.title, "自定标题"); XCTAssertFalse(edited.autoTitle)
            XCTAssertEqual(edited.createdAt, first.createdAt); XCTAssertEqual(edited.updatedAt, now.addingTimeInterval(120))
            XCTAssertEqual(try store.listNotes().map(\.id), [first.id, second.id])
            XCTAssertEqual(try EventStore(path: path).getNote(first.id), edited)
            try store.deleteNote(first.id)
            XCTAssertNil(try EventStore(path: path).getNote(first.id))
            XCTAssertEqual(try store.listNotes().map(\.id), [second.id])
        }
    }

    func testAutomaticTitlesTrackBodyAndManualPlaceholderStaysManual() throws {
        try withStore { store, _ in
            let automatic = try store.addNote(body: "原正文")
            let edited = try store.updateNote(automatic.id, body: "新首行\n其他内容")
            XCTAssertEqual(edited.title, "新首行"); XCTAssertTrue(edited.autoTitle)
            let blank = try store.updateNote(edited.id, body: "")
            XCTAssertEqual(blank.title, "无标题便笺"); XCTAssertEqual(blank.body, "")
            let manual = try store.addNote(body: "正文", title: "无标题便笺")
            XCTAssertFalse(manual.autoTitle)
            XCTAssertEqual(try store.updateNote(manual.id, body: "新正文", title: manual.title).title, manual.title)
        }
    }

    func testNoteValidationAndStableTieOrdering() throws {
        try withStore { store, _ in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            XCTAssertThrowsError(try store.addNote(body: "正文", title: String(repeating: "长", count: 121))) {
                XCTAssertEqual($0 as? DayLineError, .noteTitleTooLong)
            }
            XCTAssertThrowsError(try store.updateNote(999, body: "不存在"))
            let first = try store.addNote(body: String(repeating: "长", count: 121), now: now)
            XCTAssertEqual(first.title.count, 120)
            let second = try store.addNote(body: "第二条", now: now)
            XCTAssertEqual(try store.listNotes().map(\.id), [second.id, first.id])
        }
    }

    func testUbuntuLegacyNoteMigrationPreservesEventsAndFractionalTimestamps() throws {
        try withStore { store, path in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let event = try store.add(title: "已有日程", startsAt: now, endsAt: now.addingTimeInterval(3600), now: now)
            var db: OpaquePointer?
            XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
            defer { sqlite3_close(db) }
            let sql = """
                DROP TABLE notes;
                CREATE TABLE notes(id INTEGER PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
                INSERT INTO notes VALUES(7,'旧标题','旧正文','2026-09-14 09:00:00.123456','2026-09-14 09:01:00.654321');
                """
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
            let migrated = try EventStore(path: path)
            let note = try XCTUnwrap(migrated.getNote(7))
            XCTAssertEqual(note.title, "旧标题"); XCTAssertEqual(note.body, "旧正文"); XCTAssertFalse(note.autoTitle)
            XCTAssertEqual(note.updatedAt.timeIntervalSince(note.createdAt), 60.531, accuracy: 0.002)
            XCTAssertEqual(try migrated.get(event.id), event)
            _ = try migrated.updateNote(note.id, body: "新版正文", title: note.title)
            XCTAssertEqual(try EventStore(path: path).getNote(note.id)?.body, "新版正文")
        }
    }

    @MainActor func testDraftFlushesBeforeSelectionAndNewNote() async throws {
        try withStore { store, _ in
            let existing = try store.addNote(body: "已有正文", title: "已有标题")
            let model = NotebookModel(store: store)
            model.body = "第一条自动标题\n正文"
            model.select(existing.id)
            XCTAssertEqual(model.selectedID, existing.id)
            XCTAssertEqual(model.title, "已有标题"); XCTAssertEqual(model.body, "已有正文")
            let draft = try XCTUnwrap(store.listNotes().first { $0.id != existing.id })
            XCTAssertTrue(draft.autoTitle)
            model.select(draft.id)
            XCTAssertEqual(model.title, "")
            model.body = "修改首行\n正文"
            XCTAssertTrue(model.newNote())
            XCTAssertEqual(try store.getNote(draft.id)?.title, "修改首行")
            XCTAssertNil(model.selectedID); XCTAssertEqual(model.body, "")
        }
    }

    @MainActor func testFailedSaveKeepsDraftAndSelection() async throws {
        try withStore { store, _ in
            let note = try store.addNote(body: "已有内容")
            let model = NotebookModel(store: store)
            model.title = String(repeating: "长", count: 121); model.body = "不能丢失"
            XCTAssertFalse(model.newNote())
            model.select(note.id)
            XCTAssertNil(model.selectedID); XCTAssertEqual(model.body, "不能丢失")
            XCTAssertNotNil(model.errorMessage)
            model.title = "修正标题"
            XCTAssertTrue(model.flush()); XCTAssertNil(model.errorMessage)
            XCTAssertEqual(try store.getNote(try XCTUnwrap(model.selectedID))?.body, "不能丢失")
        }
    }

    @MainActor func testBlankDraftIsSkippedButBlankExistingNoteIsSaved() async throws {
        try withStore { store, path in
            let model = NotebookModel(store: store)
            model.body = " \n "; XCTAssertTrue(model.flush()); XCTAssertTrue(model.notes.isEmpty)
            model.body = "初始内容"; XCTAssertTrue(model.flush())
            let id = try XCTUnwrap(model.selectedID)
            model.body = ""; XCTAssertTrue(model.flush())
            XCTAssertEqual(try EventStore(path: path).getNote(id)?.body, "")
            XCTAssertEqual(try store.getNote(id)?.title, "无标题便笺")
        }
    }

    @MainActor func testDebouncedAutosaveAndDeleteCancelPendingWrite() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EventStore(path: directory.appendingPathComponent("events.db"))
        let model = NotebookModel(store: store)
        model.body = "旧输入"; model.body = "最新输入"
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(try store.listNotes().map(\.body), ["最新输入"])
        model.body = "删除前待保存内容"
        model.deleteSelected()
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(try store.listNotes().isEmpty); XCTAssertNil(model.selectedID)
        XCTAssertEqual(model.body, ""); XCTAssertEqual(model.status, "便笺已删除")
    }
}
