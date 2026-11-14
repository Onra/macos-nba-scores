import Foundation

/// One of the 30 teams of today.
public struct TeamRef: Codable, Hashable, Sendable {
    public var id = ""
    public var abbr = ""
    public var name = ""
    public var logo: URL?
}

public enum Teams {
    /// Basketball-Reference team codes that differ from ESPN's.
    static let bbrefCodes = ["GSW": "GS", "NYK": "NY", "SAS": "SA", "NOP": "NO", "UTA": "UTAH", "WAS": "WSH",
                             "PHO": "PHX", "BRK": "BKN", "CHO": "CHA"]

    public static func parse(_ json: JSON) -> [TeamRef] {
        json["sports"][0]["leagues"][0]["teams"].array.map { item in
            let t = item["team"]
            return TeamRef(id: t["id"].text, abbr: t["abbreviation"].text, name: t["displayName"].text,
                           logo: URL(string: t["logos"][0]["href"].text))
        }
    }

    /// "13", "LAL", "lal" or Basketball-Reference's "GSW" -> ESPN team id; "" when unknown.
    public static func resolve(_ code: String, in teams: [TeamRef]) -> String {
        let code = code.trimmingCharacters(in: .whitespaces)
        if !code.isEmpty, code.allSatisfy(\.isNumber) { return code }
        let abbr = bbrefCodes[code.uppercased()] ?? code.uppercased()
        return teams.first { $0.abbr.uppercased() == abbr }?.id ?? ""
    }
}
