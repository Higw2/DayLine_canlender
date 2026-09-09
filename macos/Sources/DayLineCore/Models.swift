import Foundation

public struct CalendarEvent: Identifiable, Equatable, Sendable {
    public let id: Int64
    public var title: String
    public var startsAt: Date
    public var endsAt: Date
    public var notes: String
    public var completed: Bool
    public var alertedAt: Date?
    public var reminderAt: Date?

    public init(id: Int64 = 0, title: String, startsAt: Date, endsAt: Date, notes: String = "", completed: Bool = false, alertedAt: Date? = nil, reminderAt: Date? = nil) {
        self.id = id; self.title = title; self.startsAt = startsAt; self.endsAt = endsAt
        self.notes = notes; self.completed = completed; self.alertedAt = alertedAt; self.reminderAt = reminderAt
    }

    public var dueAt: Date { reminderAt ?? startsAt }
}

public enum DayLineError: LocalizedError, Equatable {
    case emptyTitle, titleTooLong, invalidDates, sqlite(String)
    public var errorDescription: String? {
        switch self {
        case .emptyTitle: return "请填写事件名称"
        case .titleTooLong: return "事件名称不能超过 120 个字符"
        case .invalidDates: return "结束时间必须晚于开始时间"
        case .sqlite(let message): return "数据库错误：\(message)"
        }
    }
}

public enum DateCodec {
    public static let formatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()
    public static func string(_ date: Date) -> String { formatter.string(from: date) }
    public static func date(_ value: String) -> Date? {
        if let date = formatter.date(from: value) { return date }
        let minuteFormatter = DateFormatter(); minuteFormatter.locale = Locale(identifier: "en_US_POSIX"); minuteFormatter.calendar = Calendar(identifier: .gregorian); minuteFormatter.timeZone = .current; minuteFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        return minuteFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    /// Match the Ubuntu database: strip only microseconds, never change wall-clock seconds.
    public static func rounded(_ date: Date) -> Date { Date(timeIntervalSince1970: floor(date.timeIntervalSince1970)) }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var themeColor: String = "#28735f"
    public var desktopTheme: String = "dark"
    public var fontScale: Double = 1.0
    public var launchAtLogin: Bool = false
    public init() {}
    enum CodingKeys: String, CodingKey { case themeColor = "theme_color", desktopTheme = "desktop_theme", fontScale = "font_scale", launchAtLogin = "launch_at_login" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let color = try c.decodeIfPresent(String.self, forKey: .themeColor) ?? "#28735f"
        themeColor = color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil ? color : "#28735f"
        let theme = try c.decodeIfPresent(String.self, forKey: .desktopTheme) ?? "dark"; desktopTheme = DesktopTheme(rawValue: theme)?.rawValue ?? "dark"
        let scale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1; fontScale = FontScale.allCases.contains(where: { $0.rawValue == scale }) ? scale : 1
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }
    public func encode(to encoder: Encoder) throws { var c=encoder.container(keyedBy:CodingKeys.self); try c.encode(themeColor,forKey:.themeColor); try c.encode(desktopTheme,forKey:.desktopTheme); try c.encode(fontScale,forKey:.fontScale); try c.encode(launchAtLogin,forKey:.launchAtLogin) }
}

public enum Accent: String, CaseIterable, Identifiable {
    case emerald = "#28735f", blue = "#2563eb", teal = "#0d9488", violet = "#7c3aed"
    case orange = "#ea580c", rose = "#e11d48", gold = "#d97706", slate = "#475569"
    public var id: String { rawValue }
}

public enum DesktopTheme: String, CaseIterable, Identifiable { case dark, tinted, light; public var id: String { rawValue } }
public enum FontScale: Double, CaseIterable, Identifiable { case small = 0.9, normal = 1, large = 1.15, extraLarge = 1.3; public var id: Double { rawValue } }
