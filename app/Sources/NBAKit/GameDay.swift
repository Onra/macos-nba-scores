import Foundation

/// Game days are ESPN's: a day is a US Eastern calendar date, written as a "YYYYMMDD" key.
/// A game that tips off at 01:30 in Paris belongs to the day before.
public enum GameDay {
    /// "2026-10-12" or "2026-10-12T07:00Z" -> "20261012"
    public static func key(fromISO text: String) -> String {
        String(text.prefix(10)).replacingOccurrences(of: "-", with: "")
    }

    public static func isKey(_ text: String) -> Bool {
        text.count == 8 && text.allSatisfy(\.isNumber)
    }

    /// "20261114" -> "Sat 14 Nov"
    public static func label(_ key: String) -> String {
        guard let date = date(key) else { return "" }
        return labelFormatter.string(from: date)
    }

    /// "20261114" -> "14 Nov"
    public static func shortLabel(_ key: String) -> String {
        label(key).split(separator: " ").dropFirst().joined(separator: " ")
    }

    /// Noon UTC of that day: safe to format in UTC whatever the user's time zone.
    static func date(_ key: String) -> Date? {
        guard isKey(key) else { return nil }
        var parts = DateComponents()
        parts.year = Int(key.prefix(4))
        parts.month = Int(key.dropFirst(4).prefix(2))
        parts.day = Int(key.suffix(2))
        parts.hour = 12
        return utc.date(from: parts)
    }

    /// Union of sorted key lists, so that a known day never drops out of the navigation
    /// (the calendar ESPN sends changes with the phase of the season).
    public static func merge(_ lists: [String]...) -> [String] {
        Set(lists.joined().filter(isKey)).sorted()
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let labelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()
}

public enum Season {
    /// ESPN season types.
    public static func phase(_ type: Int) -> String {
        switch type {
        case 1: "Preseason"
        case 2: "Regular season"
        case 3: "Playoffs"
        case 5: "Play-in"
        default: ""
        }
    }

    /// "2025-26" -> 2026, and "1993" -> 1993: ESPN names the seasons before 1993-94 by the year they end.
    public static func endYear(_ label: String) -> Int {
        guard let start = Int(label.prefix(4)) else { return 0 }
        return label.count > 4 ? start + 1 : start
    }

    /// 2026 -> "2025-26". Seasons are numbered by the year they end, as ESPN does.
    public static func label(_ endYear: Int) -> String {
        endYear > 0 ? "\(endYear - 1)-\(String(format: "%02d", endYear % 100))" : ""
    }
}
