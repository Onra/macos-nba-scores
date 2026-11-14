import Foundation

/// The awards that are voted on. Finals, All-Star and Cup MVPs have no voting to show.
public enum AwardKind: String, Codable, CaseIterable, Sendable {
    case mvp, roy, dpoy, smoy, mip, clutch
    case allNBA = "all-nba"
    case allDefensive = "all-defensive"
    case allRookie = "all-rookie"

    /// From ESPN's name of an award on a player card.
    public init?(awardName name: String) {
        switch name {
        case "MVP": self = .mvp
        case "Rookie of the Year": self = .roy
        case "Defensive Player of the Year": self = .dpoy
        case "Most Improved Player": self = .mip
        case _ where name.hasPrefix("Sixth Man"): self = .smoy
        case _ where name.hasPrefix("Clutch Player"): self = .clutch
        case _ where name.hasPrefix("All-NBA"): self = .allNBA
        case _ where name.hasPrefix("All-Defensive"): self = .allDefensive
        case _ where name.hasPrefix("All-Rookie"): self = .allRookie
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .mvp: "MVP"
        case .roy: "Rookie of the Year"
        case .dpoy: "Defensive Player of the Year"
        case .smoy: "Sixth Man of the Year"
        case .mip: "Most Improved Player"
        case .clutch: "Clutch Player of the Year"
        case .allNBA: "All-NBA"
        case .allDefensive: "All-Defensive"
        case .allRookie: "All-Rookie"
        }
    }

    /// The id of its table on Basketball-Reference's page of a season's awards.
    var table: String {
        switch self {
        case .clutch: "clutch_poy"
        case .allNBA: "leading_all_nba"
        case .allDefensive: "leading_all_defense"
        case .allRookie: "leading_all_rookie"
        default: rawValue
        }
    }

    /// Listed by team (1st, 2nd, 3rd), then the other players who got votes.
    public var grouped: Bool { self == .allNBA || self == .allDefensive || self == .allRookie }

    /// The first season with a voting table on Basketball-Reference, by the year it ends.
    public var firstSeason: Int {
        switch self {
        case .mvp: 1956
        case .roy: 1964
        case .dpoy: 1983
        case .smoy: 1984
        case .mip: 1986
        case .clutch: 2023
        case .allNBA: 1966
        case .allDefensive: 1969
        case .allRookie: 1963
        }
    }
}

/// One player of an award's voting.
public struct Vote: Codable, Hashable, Sendable, Identifiable {
    /// "1st team", "Other votes"; empty for an award that is not listed by team.
    public var group = ""
    public var rank = ""
    public var name = ""
    public var pos = ""
    /// Basketball-Reference's team code.
    public var team = ""
    public var first = ""
    public var points = ""
    public var share = ""
    /// ESPN's athlete id, when its search finds the player.
    public var athlete = ""
    /// ESPN's team id, for the seasons that have a team page.
    public var teamID = ""

    public var id: String { group + name }

    /// "0.935" -> "93.5%", "1" -> "100%"
    public var shareText: String {
        guard let value = Double(share) else { return "" }
        return "\(Game.trim((value * 1000).rounded() / 10))%"
    }
}

/// The voting of one award in one season.
public struct AwardPage: Codable, Sendable {
    public var kind = AwardKind.mvp
    /// The season, by the year it ends.
    public var season = 0
    /// Empty when the award was not voted that season.
    public var rows: [Vote] = []
}

public enum Awards {
    /// Basketball-Reference codes of franchises since 1992-93 that ESPN names after the team they became.
    static let oldTeams = ["SEA": "OKC", "NJN": "BKN", "VAN": "MEM", "WSB": "WSH", "CHH": "CHA", "NOH": "NO", "NOK": "NO"]

    /// The latest season whose awards are out: they are voted in April and announced by June.
    public static func lastSeason(now: Date = Date()) -> Int {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: now)
        return (parts.year ?? 0) - ((parts.month ?? 1) >= 7 ? 0 : 1)
    }

    /// Every award table of a season's page, by table id.
    public static func parse(html: String) -> [String: [Vote]] {
        // Basketball-Reference hides some tables in HTML comments.
        let page = html.replacingOccurrences(of: "<!--", with: "").replacingOccurrences(of: "-->", with: "")
        let groups: [Character: String] = ["1": "1st team", "2": "2nd team", "3": "3rd team", "O": "Other votes"]
        var tables: [String: [Vote]] = [:]
        for match in page.matches(of: /<table[^>]*\bid="([a-z_]+)"/) {
            let id = String(match.1)
            guard tables[id] == nil else { continue }
            let rest = page[match.range.upperBound...]
            let body = rest.range(of: "</table>").map { rest[..<$0.lowerBound] } ?? rest
            var rows: [Vote] = [], seen: Set<String> = []
            for row in Text.rows(String(body)) {
                func cell(_ stat: String) -> String {
                    guard let range = row.range(of: "data-stat=\"\(stat)\""),
                          let open = row[range.upperBound...].firstIndex(of: ">") else { return "" }
                    let rest = row[row.index(after: open)...]
                    let end = rest.range(of: "</t")?.lowerBound ?? rest.endIndex
                    return Text.unescape(String(rest[..<end]).replacing(/<[^>]+>/, with: "")).trimmingCharacters(in: .whitespaces)
                }
                // A Hall of Famer is starred: "Oscar Robertson*".
                let name = cell("player").trimmingCharacters(in: CharacterSet(charactersIn: "*"))
                guard !name.isEmpty, name != "Player" else { continue }
                let group = cell("all_nba_team")
                guard seen.insert(group + name).inserted else { continue }
                rows.append(Vote(group: group.first.flatMap { groups[$0] } ?? "", rank: cell("rank"), name: name,
                                 pos: cell("pos"), team: cell("team_id"), first: cell("votes_first"),
                                 points: cell("points_won"), share: cell("award_share")))
            }
            tables[id] = rows
        }
        return tables
    }

    /// The rows of one award. The ABA years list the NBA award as "nba_mvp", beside "aba_mvp".
    public static func rows(_ kind: AwardKind, in tables: [String: [Vote]]) -> [Vote] {
        if let rows = tables["nba_" + kind.table], !rows.isEmpty { return rows }
        return tables[kind.table] ?? []
    }

    /// ESPN's id of a team code, for the seasons that have a team page.
    public static func teamID(_ code: String, season: Int, teams: [TeamRef]) -> String {
        guard season >= TeamPage.firstSeason, !code.isEmpty, code != "TOT" else { return "" }
        return Teams.resolve(oldTeams[code] ?? code, in: teams)
    }

    /// The athlete of ESPN's search who bears that name: first without accents but keeping "Jr." and "II"
    /// (the search may put Gary Payton II before Gary Payton), then loosely.
    public static func match(_ name: String, among players: [SearchResult]) -> String {
        func plain(_ name: String) -> String {
            name.folding(options: .diacriticInsensitive, locale: nil).lowercased()
                .replacingOccurrences(of: ".", with: "").split(separator: " ").joined(separator: " ")
        }
        for same in [plain, Text.normalizedName] {
            if let hit = players.first(where: { same($0.name) == same(name) }) { return hit.target }
        }
        return ""
    }
}
