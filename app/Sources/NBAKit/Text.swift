import Foundation

/// Small text helpers for the pages scraped from Basketball-Reference and for names.
enum Text {
    /// "Nikola Jokić" / "Jaren Jackson Jr." -> "nikola jokic" / "jaren jackson"
    static func normalizedName(_ name: String) -> String {
        let plain = name.decomposedStringWithCompatibilityMapping.unicodeScalars
            .filter { !$0.properties.isDiacritic && $0.properties.generalCategory != .nonspacingMark }
        return String(String.UnicodeScalarView(plain)).lowercased()
            .replacing(/[.'’,-]/, with: " ")
            .replacing(/\b(jr|sr|ii|iii|iv|v)\b/, with: " ")
            .split(separator: " ").joined(separator: " ")
    }

    /// The few HTML entities a name can hold.
    static func unescape(_ html: String) -> String {
        guard html.contains("&") else { return html }
        var text = html
        for (entity, character) in ["&amp;": "&", "&#39;": "'", "&apos;": "'", "&quot;": "\"", "&lt;": "<", "&gt;": ">", "&nbsp;": " "] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.replacing(/&#(\d+);/) { match in
            Int(match.1).flatMap(UnicodeScalar.init).map { String(Character($0)) } ?? ""
        }
    }

    /// Text without its tags, entities and extra spaces.
    static func clean(_ html: String) -> String {
        unescape(html.replacing(/<[^>]+>/, with: "")).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The table of that id in a page, or "".
    static func table(_ id: String, in html: String) -> String {
        guard let start = html.range(of: "id=\"\(id)\"") else { return "" }
        let rest = html[start.upperBound...]
        return String(rest[..<(rest.range(of: "</table>")?.lowerBound ?? rest.endIndex)])
    }

    /// The text of a row's cell, by its data-stat.
    static func cell(_ row: Substring, _ stat: String) -> String {
        guard let range = row.range(of: "data-stat=\"\(stat)\""),
              let open = row[range.upperBound...].firstIndex(of: ">") else { return "" }
        let rest = row[row.index(after: open)...]
        let end = rest.range(of: "</t")?.lowerBound ?? rest.endIndex
        return clean(String(rest[..<end]))
    }

    /// The table rows of a page.
    static func rows(_ html: String) -> [Substring] {
        html.matches(of: /<tr[^>]*>(.*?)<\/tr>/.dotMatchesNewlines()).map(\.1)
    }
}
