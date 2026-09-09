import Foundation
import CSQLite

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class DataPaths {
    public static let shared = DataPaths()
    public let directory: URL
    public let database: URL
    public let settings: URL
    public let geometry: URL
    private init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let override = environment["DAYLINE_DATA_DIR"], !override.isEmpty { directory = URL(fileURLWithPath: override, isDirectory: true) }
        else { directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DayLine", isDirectory: true) }
        database = directory.appendingPathComponent("events.db"); settings = directory.appendingPathComponent("settings.json"); geometry = directory.appendingPathComponent("geometry.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

public final class EventStore {
    private var db: OpaquePointer?
    public let path: URL
    public init(path: URL = DataPaths.shared.database) throws {
        self.path = path; try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw error("无法打开数据库") }
        sqlite3_busy_timeout(db, 3_000); try migrate()
    }
    deinit { sqlite3_close(db) }
    private func error(_ fallback: String = "SQLite 失败") -> DayLineError { DayLineError.sqlite(db.map { String(cString: sqlite3_errmsg($0)) } ?? fallback) }
    private func run(_ sql: String) throws { guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() } }
    private func migrate() throws {
        try run("CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, title TEXT NOT NULL, starts_at TEXT NOT NULL, ends_at TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '', completed INTEGER NOT NULL DEFAULT 0, alerted_at TEXT, reminder_at TEXT, created_at TEXT NOT NULL)")
        try run("CREATE INDEX IF NOT EXISTS idx_events_schedule ON events(starts_at, ends_at)")
        try run("CREATE INDEX IF NOT EXISTS idx_events_due ON events(completed, alerted_at, reminder_at, starts_at)")
    }
    private func statement(_ sql: String) throws -> OpaquePointer? { var s: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK else { throw error() }; return s }
    private func bind(_ statement: OpaquePointer?, _ values: [String?]) { for (i, value) in values.enumerated() { if let value { sqlite3_bind_text(statement, Int32(i + 1), value, -1, sqliteTransient) } else { sqlite3_bind_null(statement, Int32(i + 1)) } } }
    private func validate(_ title: String, _ start: Date, _ end: Date) throws -> (String, Date, Date) { let title = title.trimmingCharacters(in: .whitespacesAndNewlines); if title.isEmpty { throw DayLineError.emptyTitle }; if title.count > 120 { throw DayLineError.titleTooLong }; if end <= start { throw DayLineError.invalidDates }; return (title, DateCodec.rounded(start), DateCodec.rounded(end)) }
    public func add(title: String, startsAt: Date, endsAt: Date, notes: String = "", now: Date = Date()) throws -> CalendarEvent {
        let (title, start, end) = try validate(title, startsAt, endsAt); let now = DateCodec.rounded(now); let s = try statement("INSERT INTO events(title,starts_at,ends_at,notes,alerted_at,created_at) VALUES(?,?,?,?,?,?)"); defer { sqlite3_finalize(s) }
        bind(s, [title, DateCodec.string(start), DateCodec.string(end), notes.trimmingCharacters(in: .whitespacesAndNewlines), start <= now ? DateCodec.string(now) : nil, DateCodec.string(now)])
        guard sqlite3_step(s) == SQLITE_DONE else { throw error() }; return try get(sqlite3_last_insert_rowid(db))!
    }
    public func update(id: Int64, title: String, startsAt: Date, endsAt: Date, notes: String = "", now: Date = Date()) throws -> CalendarEvent {
        let old = try get(id); guard let old else { throw DayLineError.sqlite("事件不存在") }; let (title, start, end) = try validate(title, startsAt, endsAt)
        let changed = start != old.startsAt || end != old.endsAt; let rearm = changed && start > now && !old.completed
        let s = try statement("UPDATE events SET title=?,starts_at=?,ends_at=?,notes=?,alerted_at=?,reminder_at=? WHERE id=?"); defer { sqlite3_finalize(s) }
        bind(s, [title, DateCodec.string(start), DateCodec.string(end), notes.trimmingCharacters(in: .whitespacesAndNewlines), rearm ? nil : old.alertedAt.map(DateCodec.string), rearm ? nil : old.reminderAt.map(DateCodec.string)])
        sqlite3_bind_int64(s, 7, id); guard sqlite3_step(s) == SQLITE_DONE else { throw error() }; return try get(id)!
    }
    public func get(_ id: Int64) throws -> CalendarEvent? { try query("SELECT * FROM events WHERE id=?", [String(id)]).first }
    public func events(on day: Date, calendar: Calendar = .current) throws -> [CalendarEvent] { let start = calendar.startOfDay(for: day), end = calendar.date(byAdding: .day, value: 1, to: start)!; return try query("SELECT * FROM events WHERE starts_at < ? AND ends_at > ? ORDER BY starts_at,id", [DateCodec.string(end), DateCodec.string(start)]) }
    public func upcoming(limit: Int = 5, now: Date = Date()) throws -> [CalendarEvent] { try query("SELECT * FROM events WHERE completed=0 AND ends_at >= ? ORDER BY starts_at,id LIMIT ?", [DateCodec.string(now), String(limit)]) }
    public func due(now: Date = Date()) throws -> [CalendarEvent] { let old = now.addingTimeInterval(-86_400); return try query("SELECT * FROM events WHERE completed=0 AND alerted_at IS NULL AND COALESCE(reminder_at,starts_at) BETWEEN ? AND ? ORDER BY COALESCE(reminder_at,starts_at),id", [DateCodec.string(old), DateCodec.string(now)]) }
    @discardableResult public func expireStale(now: Date = Date()) throws -> Int { let s = try statement("UPDATE events SET alerted_at=? WHERE completed=0 AND alerted_at IS NULL AND COALESCE(reminder_at,starts_at) < ?"); defer { sqlite3_finalize(s) }; bind(s,[DateCodec.string(now),DateCodec.string(now.addingTimeInterval(-86_400))]); guard sqlite3_step(s) == SQLITE_DONE else { throw error() }; return Int(sqlite3_changes(db)) }
    public func markAlerted(_ id: Int64, now: Date = Date()) throws { try mutate("UPDATE events SET alerted_at=?,reminder_at=NULL WHERE id=?", [DateCodec.string(now), String(id)]) }
    public func snooze(_ id: Int64, minutes: Int = 10, now: Date = Date()) throws { try mutate("UPDATE events SET alerted_at=NULL,reminder_at=? WHERE id=?", [DateCodec.string(now.addingTimeInterval(TimeInterval(minutes * 60))), String(id)]) }
    public func complete(_ id: Int64, completed: Bool = true, now: Date = Date()) throws { guard let event = try get(id) else { return }; let rearm = !completed && event.startsAt > now; try mutate("UPDATE events SET completed=?,alerted_at=? WHERE id=?", [completed ? "1" : "0", rearm ? nil : DateCodec.string(event.alertedAt ?? now), String(id)]) }
    public func delete(_ id: Int64) throws { try mutate("DELETE FROM events WHERE id=?", [String(id)]) }
    private func mutate(_ sql: String, _ values: [String?]) throws { let s = try statement(sql); defer { sqlite3_finalize(s) }; bind(s, values); guard sqlite3_step(s) == SQLITE_DONE else { throw error() } }
    private func query(_ sql: String, _ values: [String?]) throws -> [CalendarEvent] { let s = try statement(sql); defer { sqlite3_finalize(s) }; bind(s, values); var result:[CalendarEvent] = []; while true { let resultCode=sqlite3_step(s); if resultCode == SQLITE_DONE { return result }; guard resultCode == SQLITE_ROW else { throw error() }; result.append(try row(s)) } }
    private func row(_ s: OpaquePointer?) throws -> CalendarEvent { func text(_ n:Int32)->String { sqlite3_column_text(s,n).map { String(cString:$0) } ?? "" }; func optional(_ n:Int32)->Date? { sqlite3_column_type(s,n) == SQLITE_NULL ? nil : DateCodec.date(text(n)) }; guard let start=DateCodec.date(text(2)), let end=DateCodec.date(text(3)) else { throw DayLineError.sqlite("事件日期格式无效") }; return CalendarEvent(id: sqlite3_column_int64(s,0), title:text(1), startsAt:start, endsAt:end, notes:text(4), completed:sqlite3_column_int(s,5) != 0, alertedAt:optional(6), reminderAt:optional(7)) }
}

public final class SettingsStore {
    public let path: URL; public private(set) var current: AppSettings
    public init(path: URL = DataPaths.shared.settings) { self.path = path; current = (try? JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: path))) ?? AppSettings() }
    public func save(_ settings: AppSettings) throws { current = settings; try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true); let data = try JSONEncoder().encode(settings); try data.write(to: path, options: .atomic) }
}
