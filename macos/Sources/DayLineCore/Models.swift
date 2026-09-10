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
    public var bgColor: String = "#1e242b"
    public var bgOpacity: Double = 0.90
    public var bgImagePath: String = ""
    public var bgType: String = "color"
    public var sidebarRatio: Double = Double(MainSplitLayout.defaultRatio)
    public var automaticUpdatesEnabled: Bool = false
    public var updateCheckInterval: UpdateCheckInterval = .daily
    public init() {}
    enum CodingKeys: String, CodingKey {
        case themeColor = "theme_color"
        case desktopTheme = "desktop_theme"
        case fontScale = "font_scale"
        case launchAtLogin = "launch_at_login"
        case bgColor = "bg_color"
        case bgOpacity = "bg_opacity"
        case bgImagePath = "bg_image_path"
        case bgType = "bg_type"
        case sidebarRatio = "sidebar_ratio"
        case automaticUpdatesEnabled = "automatic_updates_enabled"
        case updateCheckInterval = "update_check_interval"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let color = try c.decodeIfPresent(String.self, forKey: .themeColor) ?? "#28735f"
        themeColor = color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil ? color : "#28735f"
        let theme = try c.decodeIfPresent(String.self, forKey: .desktopTheme) ?? "dark"
        desktopTheme = DesktopTheme(rawValue: theme)?.rawValue ?? "dark"
        let scale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1
        fontScale = FontScale.allCases.contains(where: { $0.rawValue == scale }) ? scale : 1
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false

        let bgCol = try c.decodeIfPresent(String.self, forKey: .bgColor) ?? "#1e242b"
        bgColor = bgCol.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil ? bgCol : "#1e242b"
        let opacity = try c.decodeIfPresent(Double.self, forKey: .bgOpacity) ?? 0.90
        bgOpacity = max(0.1, min(1.0, opacity))
        bgImagePath = try c.decodeIfPresent(String.self, forKey: .bgImagePath) ?? ""
        let bgt = try c.decodeIfPresent(String.self, forKey: .bgType) ?? "color"
        bgType = (bgt == "image") ? "image" : "color"
        let ratio = try c.decodeIfPresent(Double.self, forKey: .sidebarRatio) ?? Double(MainSplitLayout.defaultRatio)
        sidebarRatio = Double(MainSplitLayout.clampedRatio(CGFloat(ratio)))
        automaticUpdatesEnabled = try c.decodeIfPresent(Bool.self, forKey: .automaticUpdatesEnabled) ?? false
        updateCheckInterval = (try? c.decode(UpdateCheckInterval.self, forKey: .updateCheckInterval)) ?? .daily
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(themeColor, forKey: .themeColor)
        try c.encode(desktopTheme, forKey: .desktopTheme)
        try c.encode(fontScale, forKey: .fontScale)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(bgColor, forKey: .bgColor)
        try c.encode(bgOpacity, forKey: .bgOpacity)
        try c.encode(bgImagePath, forKey: .bgImagePath)
        try c.encode(bgType, forKey: .bgType)
        try c.encode(sidebarRatio, forKey: .sidebarRatio)
        try c.encode(automaticUpdatesEnabled, forKey: .automaticUpdatesEnabled)
        try c.encode(updateCheckInterval, forKey: .updateCheckInterval)
    }
}

public enum UpdateCheckInterval: String, CaseIterable, Codable, Identifiable, Sendable {
    case sixHours = "six_hours"
    case daily
    case weekly

    public var id: String { rawValue }
    public var seconds: TimeInterval {
        switch self {
        case .sixHours: return 6 * 60 * 60
        case .daily: return 24 * 60 * 60
        case .weekly: return 7 * 24 * 60 * 60
        }
    }
    public var title: String {
        switch self {
        case .sixHours: return "每 6 小时"
        case .daily: return "每天"
        case .weekly: return "每周"
        }
    }
}

public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(parsing value: String) {
        let pattern = #"(?:^|[^0-9])(\d+)\.(\d+)\.(\d+)(?:[^0-9]|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges == 4,
              let majorRange = Range(match.range(at: 1), in: value),
              let minorRange = Range(match.range(at: 2), in: value),
              let patchRange = Range(match.range(at: 3), in: value),
              let major = Int(value[majorRange]),
              let minor = Int(value[minorRange]),
              let patch = Int(value[patchRange]) else { return nil }
        self.init(major, minor, patch)
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

public enum UpdateVersionPolicy {
    public static func newerVersion(
        releaseTag: String,
        releaseName: String?,
        installedVersion: String,
        currentReleaseTag: String?
    ) -> SemanticVersion? {
        guard releaseTag != currentReleaseTag,
              let installed = SemanticVersion(parsing: installedVersion),
              let released = SemanticVersion(parsing: releaseTag) ?? releaseName.flatMap(SemanticVersion.init(parsing:)),
              released > installed else { return nil }
        return released
    }
}

public enum BackgroundPreset: String, CaseIterable, Identifiable {
    case darkSlate = "#1e242b"
    case obsidian = "#121417"
    case forest = "#142820"
    case navy = "#121b2b"
    case wine = "#2b141e"
    case cream = "#f5f3ee"
    case snow = "#ffffff"
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .darkSlate: return "暗岩灰"
        case .obsidian: return "曜石黑"
        case .forest: return "静谧森"
        case .navy: return "深海蓝"
        case .wine: return "暗夜梅"
        case .cream: return "温润米"
        case .snow: return "极简白"
        }
    }
}

public enum Accent: String, CaseIterable, Identifiable {
    case emerald = "#28735f", blue = "#2563eb", teal = "#0d9488", violet = "#7c3aed"
    case orange = "#ea580c", rose = "#e11d48", gold = "#d97706", slate = "#475569"
    public var id: String { rawValue }
}

public enum DesktopTheme: String, CaseIterable, Identifiable { case dark, tinted, light; public var id: String { rawValue } }
public enum FontScale: Double, CaseIterable, Identifiable { case small = 0.9, normal = 1, large = 1.15, extraLarge = 1.3; public var id: Double { rawValue } }
